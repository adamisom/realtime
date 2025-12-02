defmodule Realtime.Music.Supervisor do
  @moduledoc """
  DynamicSupervisor for music extension processes.
  Manages tempo servers and other music-related GenServers.
  """
  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(
      [
        name: __MODULE__,
        strategy: :one_for_one
      ] ++ opts
    )
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a tempo server for a room.
  """
  def start_tempo_server(room_id, bpm, tenant_id) do
    spec = {Realtime.Music.TempoServer, {room_id, bpm, tenant_id}}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Stop a tempo server for a room.
  """
  def stop_tempo_server(room_id, tenant_id) do
    case Registry.lookup(Realtime.Music.Registry, {:tempo_server, tenant_id, room_id}) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      [] ->
        {:error, :not_found}
    end
  end
end
