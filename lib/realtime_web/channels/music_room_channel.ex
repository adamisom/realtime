defmodule RealtimeWeb.MusicRoomChannel do
  @moduledoc """
  Phoenix Channel for collaborative music rooms.

  Handles:
  - Student connections
  - Note broadcasting
  - Tempo changes
  - Teacher controls
  """
  use RealtimeWeb, :channel

  alias Realtime.Music.{TempoServer, SessionManager, SelTracker, RateLimiter, Pattern}
  alias Realtime.Tenants

  require Logger

  ## Private Helpers

  defp teacher?(socket) do
    socket.assigns.role == "teacher"
  end

  defp validate_game_active(socket, required_game_type) do
    room_id = socket.assigns.room_id
    tenant_id = socket.assigns.tenant_id

    case SessionManager.get_game_state(room_id, tenant_id) do
      {:ok, %{game_type: game_type}} when game_type == required_game_type ->
        :ok

      {:ok, %{game_type: nil}} ->
        {:error, :no_game_active}

      {:ok, %{game_type: other}} ->
        {:error, {:wrong_game_type, other}}

      error ->
        error
    end
  end

  @doc """
  Join a music room.

  Channel topic format: "music_room:ROOM_CODE"
  Example: "music_room:MUSIC-2024"
  """
  def join("music_room:" <> room_id, params, socket) do
    tenant_id = socket.assigns.tenant

    # Validate room exists
    case SessionManager.get_room(room_id) do
      {:ok, room} ->
        student_id = params["student_id"]

        # Join room (track student)
        case SessionManager.join_room(room_id, tenant_id, student_id) do
          :ok ->
            # ✅ FIX: Extract role from JWT claims (secure) instead of params (insecure)
            # Note: socket.assigns.claims is set in UserSocket.connect/3 via JWT verification
            role = socket.assigns.claims["role"] || "student"

            socket =
              socket
              |> assign(:room_id, room_id)
              |> assign(:tenant_id, tenant_id)
              |> assign(:student_id, student_id)
              |> assign(:role, role)

            # Start tempo server if not already running
            case Registry.lookup(Realtime.Music.Registry, {:tempo_server, tenant_id, room_id}) do
              [] ->
                # Start tempo server with room's BPM
                case Realtime.Music.Supervisor.start_tempo_server(room_id, room.bpm, tenant_id) do
                  {:ok, _pid} -> :ok
                  error -> Logger.warning("Failed to start tempo server: #{inspect(error)}")
                end

              _ ->
                :ok
            end

            # Subscribe to beat events from tempo server
            tenant_topic = Tenants.tenant_topic(tenant_id, "music_room:#{room_id}", true)
            Phoenix.PubSub.subscribe(Realtime.PubSub, tenant_topic)

            # Start tempo clock
            TempoServer.start_clock(room_id, tenant_id)

            # Get current beat assignments
            {:ok, assignments} = SessionManager.get_beat_assignments(room_id)

            # Send beat assignments after join completes
            send(self(), {:send_beat_assignments, assignments})

            {:ok, %{room_id: room_id, bpm: room.bpm, assignments: assignments}, socket}

          {:error, reason} ->
            {:error, %{reason: "Failed to join room: #{inspect(reason)}"}}
        end

      {:error, :not_found} ->
        {:error, %{reason: "Room not found"}}
    end
  end

  def handle_in("play_note", %{"midi" => midi} = payload, socket) do
    room_id = socket.assigns.room_id
    tenant_id = socket.assigns.tenant_id
    student_id = socket.assigns.student_id

    # Extract velocity (default to 64 for backward compatibility)
    velocity = Map.get(payload, "velocity", 64)

    velocity =
      cond do
        velocity < 0 -> 0
        velocity > 127 -> 127
        true -> velocity
      end

    # Get rate limit based on role
    max_per_second =
      if teacher?(socket) do
        Application.get_env(:realtime, :extensions)[:music][:rate_limit][:teacher_notes_per_second]
      else
        Application.get_env(:realtime, :extensions)[:music][:rate_limit][:notes_per_second]
      end

    # Check if Improvisation Jam is active and enforce solo mode
    solo_check =
      case SessionManager.get_game_state(room_id, tenant_id) do
        {:ok, %{game_type: :improvisation_jam, game_state: game_state}} ->
          current_soloist = Map.get(game_state, :current_soloist)
          improvisation_state = Map.get(game_state, :improvisation_state)

          if improvisation_state == :solo_active && current_soloist != student_id do
            {:error, :not_soloist}
          else
            :ok
          end

        _ ->
          :ok
      end

    case solo_check do
      {:error, :not_soloist} ->
        {:reply, {:error, %{reason: "only_soloist_can_play"}}, socket}

      :ok ->
        # Check rate limit
        case RateLimiter.check_rate_limit(room_id, tenant_id, student_id, max_per_second) do
          {:ok, :allowed} ->
            # Record note play
            RateLimiter.record_note_play(room_id, tenant_id, student_id)

            # Broadcast with velocity
            broadcast!(socket, "student_note", %{
              midi: midi,
              velocity: velocity,
              student_id: student_id,
              timestamp: System.system_time(:millisecond)
            })

            # Log with velocity
            SelTracker.log_participation(
              room_id,
              tenant_id,
              student_id,
              "note_played",
              %{midi: midi, velocity: velocity}
            )

            # Check if Dynamics Dance is active and provide volume feedback
            case SessionManager.get_game_state(room_id, tenant_id) do
              {:ok, %{game_type: :dynamics_dance, game_state: game_state}} ->
                dynamic_goal = Map.get(game_state, :dynamic_goal)
                dynamic_velocity_range = Map.get(game_state, :dynamic_velocity_range)

                if dynamic_goal && dynamic_velocity_range do
                  {min_vel, max_vel} = dynamic_velocity_range
                  in_range = velocity >= min_vel and velocity <= max_vel

                  push(socket, "volume_feedback", %{
                    velocity: velocity,
                    goal: dynamic_goal,
                    in_range: in_range,
                    target_range: dynamic_velocity_range
                  })
                end

              _ ->
                :ok
            end

            {:reply, :ok, socket}

          {:error, :rate_limit_exceeded} ->
            {:reply, {:error, %{reason: "rate_limit_exceeded"}}, socket}
        end
    end
  end

  def handle_in("play_note", _payload, socket) do
    # Invalid payload (missing midi)
    {:reply, {:error, %{reason: "midi required"}}, socket}
  end

  def handle_in("set_tempo", %{"bpm" => bpm}, socket) when is_integer(bpm) do
    if teacher?(socket) do
      room_id = socket.assigns.room_id
      tenant_id = socket.assigns.tenant_id

      # Update tempo server
      case TempoServer.set_tempo(room_id, tenant_id, bpm) do
        :ok ->
          # Log teacher action
          SelTracker.log_participation(
            room_id,
            tenant_id,
            socket.assigns.student_id,
            "tempo_changed",
            %{bpm: bpm, changed_by: "teacher"}
          )

          # Broadcast to all students
          broadcast!(socket, "tempo_changed", %{bpm: bpm})
          {:reply, :ok, socket}

        {:error, :invalid_bpm} ->
          {:reply, {:error, %{reason: "BPM must be between 1 and 299"}}, socket}
      end
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  def handle_in("set_tempo", _payload, socket) do
    {:reply, {:error, %{reason: "bpm must be an integer"}}, socket}
  end

  def handle_in("mute_student", %{"student_id" => student_id}, socket) do
    if teacher?(socket) do
      broadcast!(socket, "student_muted", %{student_id: student_id})
      {:reply, :ok, socket}
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  def handle_in("assign_beat", %{"student_id" => student_id, "beat" => beat}, socket) do
    if teacher?(socket) do
      room_id = socket.assigns.room_id

      # Store assignment in SessionManager
      case SessionManager.assign_beat(room_id, beat, student_id) do
        :ok ->
          # Get updated assignments
          {:ok, assignments} = SessionManager.get_beat_assignments(room_id)

          # Broadcast to all clients
          broadcast!(socket, "beat_assignment_updated", %{
            beat: beat,
            student_id: student_id,
            assignments: assignments
          })

          {:reply, :ok, socket}

        {:error, reason} ->
          {:reply, {:error, %{reason: inspect(reason)}}, socket}
      end
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  def handle_in("start_turn_rotation", %{"student_ids" => student_ids, "duration_seconds" => duration}, socket) do
    if teacher?(socket) do
      room_id = socket.assigns.room_id
      tenant_id = socket.assigns.tenant_id

      case SessionManager.start_turn_rotation(room_id, tenant_id, student_ids, duration) do
        :ok ->
          broadcast!(socket, "turn_rotation_started", %{student_ids: student_ids, duration_seconds: duration})

          {:reply, :ok, socket}

        error ->
          {:reply, {:error, %{reason: inspect(error)}}, socket}
      end
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  def handle_in("start_turn", _payload, socket) do
    if teacher?(socket) do
      room_id = socket.assigns.room_id
      tenant_id = socket.assigns.tenant_id

      case SessionManager.start_current_turn(room_id, tenant_id) do
        :ok ->
          {:ok, turn_info} = SessionManager.get_current_turn(room_id, tenant_id)
          broadcast!(socket, "turn_started", turn_info)
          {:reply, :ok, socket}

        error ->
          {:reply, {:error, %{reason: inspect(error)}}, socket}
      end
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  def handle_in("advance_turn", _payload, socket) do
    if teacher?(socket) do
      room_id = socket.assigns.room_id
      tenant_id = socket.assigns.tenant_id

      case SessionManager.advance_turn(room_id, tenant_id) do
        :ok ->
          {:ok, turn_info} = SessionManager.get_current_turn(room_id, tenant_id)
          broadcast!(socket, "turn_advanced", turn_info)
          {:reply, :ok, socket}

        error ->
          {:reply, {:error, %{reason: inspect(error)}}, socket}
      end
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  def handle_in("request_turn", _payload, socket) do
    room_id = socket.assigns.room_id
    tenant_id = socket.assigns.tenant_id
    student_id = socket.assigns.student_id

    case SessionManager.get_current_turn(room_id, tenant_id) do
      {:ok, turn_info} ->
        if turn_info.current_turn == student_id do
          push(socket, "turn_granted", turn_info)
          {:reply, :ok, socket}
        else
          {:reply, {:error, %{reason: "not_your_turn", current_turn: turn_info.current_turn}}, socket}
        end

      error ->
        {:reply, {:error, %{reason: inspect(error)}}, socket}
    end
  end

  def handle_in("assign_pattern", %{"student_id" => student_id, "pattern" => pattern}, socket) do
    if teacher?(socket) do
      room_id = socket.assigns.room_id
      tenant_id = socket.assigns.tenant_id

      {:ok, game_state} = SessionManager.get_game_state(room_id, tenant_id)
      pattern_assignments = Map.get(game_state.game_state, :pattern_assignments, %{})

      :ok =
        SessionManager.update_game_state(room_id, tenant_id, %{
          pattern_assignments: Map.put(pattern_assignments, student_id, pattern)
        })

      broadcast!(socket, "pattern_assigned", %{student_id: student_id, pattern: pattern})
      {:reply, :ok, socket}
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  def handle_in("pattern_start", _payload, socket) do
    if teacher?(socket) do
      room_id = socket.assigns.room_id
      tenant_id = socket.assigns.tenant_id

      :ok =
        SessionManager.update_game_state(room_id, tenant_id, %{
          pattern_state: :active
        })

      broadcast!(socket, "pattern_started", %{})
      {:reply, :ok, socket}
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  def handle_in("start_melody", _payload, socket) do
    if teacher?(socket) do
      room_id = socket.assigns.room_id
      tenant_id = socket.assigns.tenant_id
      {:ok, room} = SessionManager.get_room(room_id)

      :ok = SessionManager.start_turn_rotation(room_id, tenant_id, room.students, 60)

      :ok =
        SessionManager.update_game_state(room_id, tenant_id, %{
          melody_sequence: [],
          melody_state: :building
        })

      broadcast!(socket, "melody_started", %{})
      {:reply, :ok, socket}
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  def handle_in("add_note", %{"midi" => midi, "velocity" => velocity}, socket) do
    case validate_game_active(socket, :melody_builder) do
      :ok ->
        room_id = socket.assigns.room_id
        tenant_id = socket.assigns.tenant_id
        student_id = socket.assigns.student_id

        case SessionManager.get_current_turn(room_id, tenant_id) do
          {:ok, turn_info} ->
            if turn_info.current_turn == student_id do
              {:ok, game_state} = SessionManager.get_game_state(room_id, tenant_id)
              melody_sequence = Map.get(game_state.game_state, :melody_sequence, [])

              new_note = %{
                midi: midi,
                velocity: velocity,
                student_id: student_id,
                timestamp: System.system_time(:millisecond),
                position: length(melody_sequence)
              }

              updated_melody = melody_sequence ++ [new_note]

              :ok =
                SessionManager.update_game_state(room_id, tenant_id, %{
                  melody_sequence: updated_melody
                })

              broadcast!(socket, "note_added", %{
                note: new_note,
                melody_length: length(updated_melody)
              })

              :ok = SessionManager.advance_turn(room_id, tenant_id)
              :ok = SessionManager.start_current_turn(room_id, tenant_id)

              {:ok, next_turn_info} = SessionManager.get_current_turn(room_id, tenant_id)
              broadcast!(socket, "turn_advanced", next_turn_info)

              {:reply, :ok, socket}
            else
              {:reply, {:error, %{reason: "not_your_turn", current_turn: turn_info.current_turn}}, socket}
            end

          error ->
            {:reply, {:error, %{reason: inspect(error)}}, socket}
        end

      {:error, :no_game_active} ->
        {:reply, {:error, %{reason: "no_game_active"}}, socket}

      {:error, {:wrong_game_type, _}} ->
        {:reply, {:error, %{reason: "wrong_game_type"}}, socket}

      error ->
        {:reply, {:error, %{reason: inspect(error)}}, socket}
    end
  end

  def handle_in("play_melody", _payload, socket) do
    if teacher?(socket) do
      room_id = socket.assigns.room_id
      tenant_id = socket.assigns.tenant_id

      {:ok, game_state} = SessionManager.get_game_state(room_id, tenant_id)
      melody_sequence = Map.get(game_state.game_state, :melody_sequence, [])

      if melody_sequence != [] do
        # Broadcast melody sequence for client-side playback
        # Note: For server-side playback, would need PatternPlayer GenServer
        broadcast!(socket, "melody_playing", %{melody: melody_sequence})
        {:reply, :ok, socket}
      else
        {:reply, {:error, %{reason: "melody_empty"}}, socket}
      end
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  def handle_in("set_dynamic_pattern", %{"pattern" => pattern}, socket) do
    if teacher?(socket) do
      room_id = socket.assigns.room_id
      tenant_id = socket.assigns.tenant_id

      valid_dynamics = ["p", "mp", "mf", "f", "pp", "ff"]

      if Enum.all?(pattern, &(&1 in valid_dynamics)) do
        :ok =
          SessionManager.update_game_state(room_id, tenant_id, %{
            dynamic_pattern: pattern,
            dynamic_current_index: 0
          })

        broadcast!(socket, "dynamic_pattern_set", %{pattern: pattern})
        {:reply, :ok, socket}
      else
        {:reply, {:error, %{reason: "invalid_dynamic_pattern"}}, socket}
      end
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  def handle_in("set_dynamic_goal", %{"dynamic" => dynamic}, socket) do
    if teacher?(socket) do
      room_id = socket.assigns.room_id
      tenant_id = socket.assigns.tenant_id

      velocity_range =
        case dynamic do
          "pp" -> {20, 30}
          "p" -> {40, 50}
          "mp" -> {60, 70}
          "mf" -> {80, 90}
          "f" -> {100, 110}
          "ff" -> {120, 127}
          _ -> {64, 64}
        end

      :ok =
        SessionManager.update_game_state(room_id, tenant_id, %{
          dynamic_goal: dynamic,
          dynamic_velocity_range: velocity_range
        })

      broadcast!(socket, "dynamic_goal_set", %{
        dynamic: dynamic,
        velocity_range: velocity_range
      })

      {:reply, :ok, socket}
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  def handle_in("start_improvisation", %{"solo_duration_seconds" => duration}, socket) do
    if teacher?(socket) do
      room_id = socket.assigns.room_id
      tenant_id = socket.assigns.tenant_id
      {:ok, room} = SessionManager.get_room(room_id)

      :ok = SessionManager.start_turn_rotation(room_id, tenant_id, room.students, duration)

      :ok =
        SessionManager.update_game_state(room_id, tenant_id, %{
          improvisation_state: :waiting,
          current_soloist: nil,
          solo_queue: room.students
        })

      broadcast!(socket, "improvisation_started", %{solo_duration: duration})
      {:reply, :ok, socket}
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  def handle_in("request_solo", _payload, socket) do
    case validate_game_active(socket, :improvisation_jam) do
      :ok ->
        room_id = socket.assigns.room_id
        tenant_id = socket.assigns.tenant_id
        student_id = socket.assigns.student_id

        case SessionManager.get_current_turn(room_id, tenant_id) do
          {:ok, turn_info} ->
            if turn_info.current_turn == student_id do
              :ok =
                SessionManager.update_game_state(room_id, tenant_id, %{
                  current_soloist: student_id,
                  improvisation_state: :solo_active
                })

              broadcast!(socket, "solo_granted", %{soloist: student_id})
              {:reply, :ok, socket}
            else
              {:reply, {:error, %{reason: "not_your_turn", current_turn: turn_info.current_turn}}, socket}
            end

          error ->
            {:reply, {:error, %{reason: inspect(error)}}, socket}
        end

      {:error, :no_game_active} ->
        {:reply, {:error, %{reason: "no_game_active"}}, socket}

      {:error, {:wrong_game_type, _}} ->
        {:reply, {:error, %{reason: "wrong_game_type"}}, socket}

      error ->
        {:reply, {:error, %{reason: inspect(error)}}, socket}
    end
  end

  def handle_in("assign_solo", %{"student_id" => student_id}, socket) do
    if teacher?(socket) do
      room_id = socket.assigns.room_id
      tenant_id = socket.assigns.tenant_id

      :ok =
        SessionManager.update_game_state(room_id, tenant_id, %{
          current_soloist: student_id,
          improvisation_state: :solo_active
        })

      broadcast!(socket, "solo_assigned", %{soloist: student_id})
      {:reply, :ok, socket}
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  def handle_in("end_solo", _payload, socket) do
    if teacher?(socket) do
      room_id = socket.assigns.room_id
      tenant_id = socket.assigns.tenant_id

      :ok =
        SessionManager.update_game_state(room_id, tenant_id, %{
          current_soloist: nil,
          improvisation_state: :waiting
        })

      :ok = SessionManager.advance_turn(room_id, tenant_id)
      :ok = SessionManager.start_current_turn(room_id, tenant_id)

      {:ok, next_turn_info} = SessionManager.get_current_turn(room_id, tenant_id)
      broadcast!(socket, "solo_ended", %{next_turn: next_turn_info})
      {:reply, :ok, socket}
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  def handle_in("play_call", %{"pattern" => pattern}, socket) do
    if teacher?(socket) do
      room_id = socket.assigns.room_id
      tenant_id = socket.assigns.tenant_id

      :ok = SessionManager.set_call_pattern(room_id, tenant_id, pattern)

      # Note: For server-side playback, would need PatternPlayer GenServer
      # For now, broadcast pattern for client-side playback
      # Convert string keys to atoms for Pattern.create if needed
      pattern_with_atoms =
        Enum.map(pattern, fn note ->
          case note do
            %{__struct__: _} ->
              note

            map when is_map(map) ->
              map
              |> Enum.map(fn
                {"midi", v} -> {:midi, v}
                {"duration", v} -> {:duration, v}
                {"timestamp", v} -> {:timestamp, v}
                {"velocity", v} -> {:velocity, v}
                {k, v} when is_atom(k) -> {k, v}
                {k, v} -> {String.to_existing_atom(k), v}
              end)
              |> Map.new()

            _ ->
              note
          end
        end)

      _pattern_obj = Pattern.create("Call", pattern_with_atoms)

      :ok =
        SessionManager.update_game_state(room_id, tenant_id, %{
          response_state: :recording_responses
        })

      broadcast!(socket, "call_playing", %{pattern: pattern})
      {:reply, :ok, socket}
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  def handle_in("record_response", %{"response" => response_pattern}, socket) do
    case validate_game_active(socket, :call_and_response) do
      :ok ->
        room_id = socket.assigns.room_id
        tenant_id = socket.assigns.tenant_id
        student_id = socket.assigns.student_id

        case SessionManager.record_response(room_id, tenant_id, student_id, response_pattern) do
          :ok ->
            broadcast!(socket, "response_recorded", %{student_id: student_id})
            {:reply, :ok, socket}

          error ->
            {:reply, {:error, %{reason: inspect(error)}}, socket}
        end

      {:error, :no_game_active} ->
        {:reply, {:error, %{reason: "no_game_active"}}, socket}

      {:error, {:wrong_game_type, _}} ->
        {:reply, {:error, %{reason: "wrong_game_type"}}, socket}

      error ->
        {:reply, {:error, %{reason: inspect(error)}}, socket}
    end
  end

  def handle_in("validate_response", %{"student_id" => student_id}, socket) do
    if teacher?(socket) do
      room_id = socket.assigns.room_id
      tenant_id = socket.assigns.tenant_id

      case SessionManager.validate_response(room_id, tenant_id, student_id) do
        {:ok, feedback} ->
          broadcast!(socket, "response_feedback", %{student_id: student_id, feedback: feedback})
          {:reply, {:ok, feedback}, socket}

        error ->
          {:reply, {:error, %{reason: inspect(error)}}, socket}
      end
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  def handle_info({:beat, beat_number}, socket) do
    room_id = socket.assigns.room_id
    tenant_id = socket.assigns.tenant_id

    # Check if Rhythm Circle is active and pattern is playing
    case SessionManager.get_game_state(room_id, tenant_id) do
      {:ok, %{game_type: :rhythm_circle, game_state: game_state}} ->
        if Map.get(game_state, :pattern_state) == :active do
          :ok =
            SessionManager.update_game_state(room_id, tenant_id, %{
              pattern_current_beat: beat_number
            })

          push(socket, "pattern_beat", %{beat: beat_number})
        end

      _ ->
        :ok
    end

    # Always push regular beat
    push(socket, "beat", %{beat: beat_number})
    {:noreply, socket}
  end

  def handle_info({:send_beat_assignments, assignments}, socket) do
    push(socket, "beat_assignments", %{assignments: assignments})
    {:noreply, socket}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end
end
