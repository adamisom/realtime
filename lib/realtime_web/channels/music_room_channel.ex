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

  alias Realtime.Music.{TempoServer, SessionManager, SelTracker, RateLimiter}
  alias Realtime.Tenants

  require Logger

  ## Private Helpers

  defp is_teacher?(socket) do
    socket.assigns.role == "teacher"
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
      if is_teacher?(socket) do
        Application.get_env(:realtime, :extensions)[:music][:rate_limit][:teacher_notes_per_second]
      else
        Application.get_env(:realtime, :extensions)[:music][:rate_limit][:notes_per_second]
      end

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

        {:reply, :ok, socket}

      {:error, :rate_limit_exceeded} ->
        {:reply, {:error, %{reason: "rate_limit_exceeded"}}, socket}
    end
  end

  def handle_in("play_note", _payload, socket) do
    # Invalid payload (missing midi)
    {:reply, {:error, %{reason: "midi required"}}, socket}
  end

  def handle_in("set_tempo", %{"bpm" => bpm}, socket) when is_integer(bpm) do
    if is_teacher?(socket) do
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
    if is_teacher?(socket) do
      broadcast!(socket, "student_muted", %{student_id: student_id})
      {:reply, :ok, socket}
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  def handle_in("assign_beat", %{"student_id" => student_id, "beat" => beat}, socket) do
    if is_teacher?(socket) do
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
    if is_teacher?(socket) do
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
    if is_teacher?(socket) do
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
    if is_teacher?(socket) do
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

  def handle_info({:beat, beat_number}, socket) do
    # Push beat to WebSocket client
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
