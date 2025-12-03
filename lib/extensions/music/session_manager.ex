defmodule Realtime.Music.SessionManager do
  @moduledoc """
  Manages music room sessions.

  Handles:
  - Room creation
  - Join code generation
  - Room state tracking
  - Room cleanup
  """
  use GenServer

  require Logger

  alias Realtime.Music.Supervisor

  ## Client API

  @doc """
  Create a new music room.

  ⚠️ CRITICAL: Requires tenant_id - see Roadblock #2

  Returns: {:ok, room_id} where room_id is a unique join code
  """
  def create_room(teacher_id, tenant_id, opts \\ []) do
    GenServer.call(__MODULE__, {:create_room, teacher_id, tenant_id, opts})
  end

  @doc """
  Get room information.
  """
  def get_room(room_id) do
    GenServer.call(__MODULE__, {:get_room, room_id})
  end

  @doc """
  Join a room.

  ⚠️ CRITICAL: Requires tenant_id for proper multi-tenant isolation
  """
  def join_room(room_id, tenant_id, student_id) do
    GenServer.call(__MODULE__, {:join_room, room_id, tenant_id, student_id})
  end

  @doc """
  Close a room.
  """
  def close_room(room_id) do
    GenServer.call(__MODULE__, {:close_room, room_id})
  end

  @doc """
  Assign a beat to a student.
  """
  def assign_beat(room_id, beat, student_id) do
    GenServer.call(__MODULE__, {:assign_beat, room_id, beat, student_id})
  end

  @doc """
  Get beat assignments for a room.
  """
  def get_beat_assignments(room_id) do
    GenServer.call(__MODULE__, {:get_beat_assignments, room_id})
  end

  @doc """
  Clear a beat assignment.
  """
  def clear_beat_assignment(room_id, beat) do
    GenServer.call(__MODULE__, {:clear_beat_assignment, room_id, beat})
  end

  @doc """
  Clear all beat assignments for a room.
  """
  def clear_all_assignments(room_id) do
    GenServer.call(__MODULE__, {:clear_all_assignments, room_id})
  end

  @doc """
  Cleanup expired rooms (rooms inactive for more than max_age_hours).
  """
  def cleanup_expired_rooms(tenant_id, max_age_hours \\ 24) do
    GenServer.call(__MODULE__, {:cleanup_expired_rooms, tenant_id, max_age_hours})
  end

  @doc """
  Set the game type for a room.
  """
  def set_game_type(room_id, tenant_id, game_type)
      when game_type in [
             :rhythm_circle,
             :melody_builder,
             :dynamics_dance,
             :improvisation_jam,
             :call_and_response
           ] do
    GenServer.call(__MODULE__, {:set_game_type, room_id, tenant_id, game_type})
  end

  @doc """
  Update game state for a room (merges into existing state).
  """
  def update_game_state(room_id, tenant_id, new_state) when is_map(new_state) do
    GenServer.call(__MODULE__, {:update_game_state, room_id, tenant_id, new_state})
  end

  @doc """
  Get current game state for a room.
  """
  def get_game_state(room_id, tenant_id) do
    GenServer.call(__MODULE__, {:get_game_state, room_id, tenant_id})
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  ## Server Callbacks

  @impl true
  def init(_) do
    # State: %{room_id => %{teacher_id, tenant_id, bpm, created_at, students}}
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_call({:create_room, teacher_id, tenant_id, opts}, _from, state) do
    room_id = generate_join_code(state)
    bpm = Keyword.get(opts, :bpm, 120)

    # Start tempo server with tenant_id
    case Supervisor.start_tempo_server(room_id, bpm, tenant_id) do
      {:ok, _pid} ->
        room = %{
          room_id: room_id,
          tenant_id: tenant_id,
          teacher_id: teacher_id,
          bpm: bpm,
          created_at: System.system_time(:second),
          students: [],
          # %{beat_number => student_id}
          beat_assignments: %{},
          game_type: nil,
          game_state: %{}
        }

        Logger.info("Created music room #{room_id} for teacher #{teacher_id} (tenant: #{tenant_id})")
        {:reply, {:ok, room_id}, Map.put(state, room_id, room)}

      error ->
        Logger.error("Failed to start tempo server for room #{room_id}: #{inspect(error)}")
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_call({:get_room, room_id}, _from, state) do
    case Map.get(state, room_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      room ->
        {:reply, {:ok, room}, state}
    end
  end

  @impl true
  def handle_call({:join_room, room_id, tenant_id, student_id}, _from, state) do
    case Map.get(state, room_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      room ->
        # Verify tenant_id matches (multi-tenant isolation)
        if room.tenant_id != tenant_id do
          {:reply, {:error, :not_found}, state}
        else
          # Add student to room if not already present
          students =
            if student_id in room.students do
              room.students
            else
              [student_id | room.students]
            end

          updated_room = %{room | students: students}
          Logger.info("Student #{student_id} joined room #{room_id} (tenant: #{tenant_id})")
          {:reply, :ok, Map.put(state, room_id, updated_room)}
        end
    end
  end

  @impl true
  def handle_call({:close_room, room_id}, _from, state) do
    # Get tenant_id from room state
    case Map.get(state, room_id) do
      %{tenant_id: tenant_id} ->
        # Stop tempo server with tenant_id
        Supervisor.stop_tempo_server(room_id, tenant_id)
        Logger.info("Closed music room #{room_id}")
        {:reply, :ok, Map.delete(state, room_id)}

      nil ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:assign_beat, room_id, beat, student_id}, _from, state) do
    case Map.get(state, room_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      room ->
        beat_assignments = Map.put(room.beat_assignments, beat, student_id)
        updated_room = %{room | beat_assignments: beat_assignments}
        Logger.info("Assigned beat #{beat} to student #{student_id} in room #{room_id}")
        {:reply, :ok, Map.put(state, room_id, updated_room)}
    end
  end

  @impl true
  def handle_call({:get_beat_assignments, room_id}, _from, state) do
    case Map.get(state, room_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      room ->
        {:reply, {:ok, room.beat_assignments}, state}
    end
  end

  @impl true
  def handle_call({:clear_beat_assignment, room_id, beat}, _from, state) do
    case Map.get(state, room_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      room ->
        beat_assignments = Map.delete(room.beat_assignments, beat)
        updated_room = %{room | beat_assignments: beat_assignments}
        {:reply, :ok, Map.put(state, room_id, updated_room)}
    end
  end

  @impl true
  def handle_call({:clear_all_assignments, room_id}, _from, state) do
    case Map.get(state, room_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      room ->
        updated_room = %{room | beat_assignments: %{}}
        {:reply, :ok, Map.put(state, room_id, updated_room)}
    end
  end

  @impl true
  def handle_call({:cleanup_expired_rooms, tenant_id, max_age_hours}, _from, state) do
    now = System.system_time(:second)
    max_age_seconds = max_age_hours * 3600

    expired =
      Enum.filter(state, fn {_room_id, room} ->
        room.tenant_id == tenant_id and
          now - room.created_at > max_age_seconds and
          room.students == []
      end)

    Enum.each(expired, fn {room_id, room} ->
      Supervisor.stop_tempo_server(room_id, room.tenant_id)
    end)

    new_state = Map.drop(state, Enum.map(expired, &elem(&1, 0)))
    {:reply, {:ok, length(expired)}, new_state}
  end

  @impl true
  def handle_call({:set_game_type, room_id, tenant_id, game_type}, _from, state) do
    case Map.get(state, room_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      room ->
        if room.tenant_id == tenant_id do
          updated_room = %{room | game_type: game_type, game_state: %{}}
          {:reply, :ok, Map.put(state, room_id, updated_room)}
        else
          {:reply, {:error, :unauthorized}, state}
        end
    end
  end

  @impl true
  def handle_call({:update_game_state, room_id, tenant_id, new_state}, _from, state) do
    case Map.get(state, room_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      room ->
        if room.tenant_id == tenant_id do
          current_game_state = Map.get(room, :game_state, %{})
          updated_game_state = Map.merge(current_game_state, new_state)
          updated_room = %{room | game_state: updated_game_state}
          {:reply, :ok, Map.put(state, room_id, updated_room)}
        else
          {:reply, {:error, :unauthorized}, state}
        end
    end
  end

  @impl true
  def handle_call({:get_game_state, room_id, tenant_id}, _from, state) do
    case Map.get(state, room_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      room ->
        if room.tenant_id == tenant_id do
          game_type = Map.get(room, :game_type, nil)
          game_state = Map.get(room, :game_state, %{})
          {:reply, {:ok, %{game_type: game_type, game_state: game_state}}, state}
        else
          {:reply, {:error, :unauthorized}, state}
        end
    end
  end

  @impl true
  def handle_info(:cleanup_rooms, state) do
    # Cleanup all tenants (simplified - can be improved)
    # In production, you might want to track tenants separately
    schedule_cleanup()
    {:noreply, state}
  end

  ## Private Functions

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_rooms, 3_600_000)
  end

  # Check for duplicates to prevent collisions
  defp generate_join_code(state) do
    code = "MUSIC-#{:rand.uniform(9999) |> Integer.to_string() |> String.pad_leading(4, "0")}"

    if Map.has_key?(state, code) do
      # Retry if collision
      generate_join_code(state)
    else
      code
    end
  end
end
