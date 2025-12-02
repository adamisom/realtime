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

  # Placeholder - will be implemented in Phase 2
  def start_tempo_server(_room_id, _bpm, _tenant_id) do
    {:error, :not_implemented}
  end
end

