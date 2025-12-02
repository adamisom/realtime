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

  ## Client API (to be implemented in Phase 4)
  
  @doc """
  Create a new music room.
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

  ## Server Callbacks (to be implemented in Phase 4)
  
  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:create_room, _teacher_id, _tenant_id, _opts}, _from, state) do
    {:reply, {:error, :not_implemented}, state}
  end

  @impl true
  def handle_call({:get_room, _room_id}, _from, state) do
    {:reply, {:error, :not_implemented}, state}
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
end

