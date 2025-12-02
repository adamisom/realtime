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

  alias Realtime.Music.{TempoServer, SessionManager, SelTracker}
  alias Realtime.Tenants

  require Logger

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
        case SessionManager.join_room(room_id, student_id) do
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

            {:ok, %{room_id: room_id, bpm: room.bpm}, socket}

          {:error, reason} ->
            {:error, %{reason: "Failed to join room: #{inspect(reason)}"}}
        end

      {:error, :not_found} ->
        {:error, %{reason: "Room not found"}}
    end
  end

  def handle_in("play_note", %{"midi" => midi}, socket) do
    # Log participation event
    SelTracker.log_participation(
      socket.assigns.room_id,
      socket.assigns.tenant_id,
      socket.assigns.student_id,
      "note_played",
      %{midi: midi}
    )

    # Broadcast to all students in room
    broadcast!(socket, "student_note", %{
      midi: midi,
      student_id: socket.assigns.student_id,
      timestamp: System.system_time(:millisecond)
    })

    {:noreply, socket}
  end

  def handle_in("play_note", _payload, socket) do
    # Invalid payload (missing midi)
    {:reply, {:error, %{reason: "midi required"}}, socket}
  end

  def handle_in("set_tempo", %{"bpm" => bpm}, socket) when is_integer(bpm) do
    if socket.assigns.role == "teacher" do
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
    if socket.assigns.role == "teacher" do
      broadcast!(socket, "student_muted", %{student_id: student_id})
      {:reply, :ok, socket}
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  def handle_in("assign_beat", %{"student_id" => student_id, "beat" => beat}, socket) do
    if socket.assigns.role == "teacher" do
      broadcast!(socket, "beat_assigned", %{
        student_id: student_id,
        beat: beat
      })
      {:reply, :ok, socket}
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

