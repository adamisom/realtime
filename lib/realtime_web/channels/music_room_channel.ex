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
            socket =
              socket
              |> assign(:room_id, room_id)
              |> assign(:tenant_id, tenant_id)
              |> assign(:student_id, student_id)
              |> assign(:role, params["role"] || "student")

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

            # Get current beat assignments and send to joining client
            {:ok, assignments} = SessionManager.get_beat_assignments(room_id)
            socket = push(socket, "beat_assignments", %{assignments: assignments})

            {:ok, %{room_id: room_id, bpm: room.bpm, assignments: assignments}, socket}

          {:error, reason} ->
            {:error, %{reason: "Failed to join room: #{inspect(reason)}"}}
        end

      {:error, :not_found} ->
        {:error, %{reason: "Room not found"}}
    end
  end

  def handle_in("play_note", %{"midi" => midi}, socket) do
    room_id = socket.assigns.room_id
    tenant_id = socket.assigns.tenant_id
    student_id = socket.assigns.student_id
    
    # Get rate limit based on role
    max_per_second = if is_teacher?(socket) do
      Application.get_env(:realtime, :extensions)[:music][:rate_limit][:teacher_notes_per_second]
    else
      Application.get_env(:realtime, :extensions)[:music][:rate_limit][:notes_per_second]
    end

    # Check rate limit
    case RateLimiter.check_rate_limit(room_id, tenant_id, student_id, max_per_second) do
      {:ok, :allowed} ->
        # Record note play
        RateLimiter.record_note_play(room_id, tenant_id, student_id)
        
        # Log participation event
        SelTracker.log_participation(
          room_id,
          tenant_id,
          student_id,
          "note_played",
          %{midi: midi}
        )

        # Broadcast to all students in room
        broadcast!(socket, "student_note", %{
          midi: midi,
          student_id: student_id,
          timestamp: System.system_time(:millisecond)
        })

        {:noreply, socket}
      
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

  def handle_info({:beat, beat_number}, socket) do
    # Push beat to WebSocket client
    push(socket, "beat", %{beat: beat_number})
    {:noreply, socket}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end
end

