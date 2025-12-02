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

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  ## Server Callbacks
  
  @impl true
  def init(_) do
    # State: %{room_id => %{teacher_id, tenant_id, bpm, created_at, students}}
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
          students: []
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
          students = if student_id in room.students do
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

  ## Private Functions
  
  # Check for duplicates to prevent collisions
  defp generate_join_code(state) do
    code = "MUSIC-#{:rand.uniform(9999) |> Integer.to_string() |> String.pad_leading(4, "0")}"
    
    if Map.has_key?(state, code) do
      generate_join_code(state)  # Retry if collision
    else
      code
    end
  end
end

