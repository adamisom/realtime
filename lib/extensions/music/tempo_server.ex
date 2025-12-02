defmodule Realtime.Music.TempoServer do
  @moduledoc """
  GenServer that maintains a tempo clock and broadcasts beat events.
  
  Each music room has its own TempoServer process.
  The server sends beat events at the specified BPM to all clients in the room.
  """
  use GenServer
  require Logger

  ## Client API (to be implemented in Phase 2)
  
  @doc """
  Start a tempo server for a room.
  """
  def start_link({room_id, bpm, tenant_id}) do
    GenServer.start_link(__MODULE__, {room_id, bpm, tenant_id}, name: via_tuple(room_id, tenant_id))
  end

  @doc """
  Get current tempo for a room.
  """
  def get_tempo(room_id, tenant_id) do
    GenServer.call(via_tuple(room_id, tenant_id), :get_tempo)
  end

  ## Server Callbacks (to be implemented in Phase 2)
  
  @impl true
  def init({room_id, bpm, tenant_id}) do
    Logger.info("Starting tempo server for room #{room_id} (tenant: #{tenant_id}) at #{bpm} BPM")
    {:ok, %{room_id: room_id, tenant_id: tenant_id, bpm: bpm, beat: 0, running: false, timer_ref: nil}}
  end

  @impl true
  def handle_call(:get_tempo, _from, state) do
    {:reply, {:ok, state.bpm}, state}
  end

  ## Private Functions
  
  defp via_tuple(room_id, tenant_id) do
    {:via, Registry, {Realtime.Music.Registry, {:tempo_server, tenant_id, room_id}}}
  end
end

