defmodule Realtime.Music.SupervisorTempoTest do
  use ExUnit.Case, async: false

  test "can start tempo server" do
    tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
    room_id = "test-room-#{System.unique_integer([:positive])}"

    assert {:ok, pid} = Realtime.Music.Supervisor.start_tempo_server(room_id, 120, tenant_id)
    assert Process.alive?(pid)
  end

  test "can stop tempo server" do
    tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
    room_id = "test-room-#{System.unique_integer([:positive])}"

    {:ok, pid} = Realtime.Music.Supervisor.start_tempo_server(room_id, 120, tenant_id)
    assert Process.alive?(pid)

    :ok = Realtime.Music.Supervisor.stop_tempo_server(room_id, tenant_id)

    # Process should be terminated
    refute Process.alive?(pid)
  end

  test "stop_tempo_server returns error for non-existent room" do
    tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
    room_id = "non-existent-room"

    assert {:error, :not_found} = Realtime.Music.Supervisor.stop_tempo_server(room_id, tenant_id)
  end
end
