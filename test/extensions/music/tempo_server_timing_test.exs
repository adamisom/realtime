defmodule Realtime.Music.TempoServerTimingTest do
  use ExUnit.Case, async: false

  setup do
    tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
    room_id = "test-room-#{System.unique_integer([:positive])}"
    {:ok, pid} = Realtime.Music.Supervisor.start_tempo_server(room_id, 120, tenant_id)

    topic = Realtime.Tenants.tenant_topic(tenant_id, "music_room:#{room_id}", true)
    Phoenix.PubSub.subscribe(Realtime.PubSub, topic)

    {:ok, room_id: room_id, tenant_id: tenant_id, pid: pid, topic: topic}
  end

  test "beats arrive at correct intervals over extended period", %{
    room_id: room_id,
    tenant_id: tenant_id
  } do
    :ok = Realtime.Music.TempoServer.start_clock(room_id, tenant_id)

    # Collect 10 beats and measure intervals
    intervals =
      Enum.reduce(1..10, {[], System.monotonic_time(:millisecond)}, fn _, {acc, last_time} ->
        assert_receive {:beat, _}, 600
        current_time = System.monotonic_time(:millisecond)
        interval = current_time - last_time
        {[interval | acc], current_time}
      end)
      |> elem(0)
      |> Enum.reverse()

    # 120 BPM = 500ms per beat
    # Allow ±50ms tolerance for system scheduling
    avg_interval = Enum.sum(intervals) / length(intervals)
    assert avg_interval >= 450 and avg_interval <= 550
  end

  test "tempo changes don't cause drift accumulation", %{room_id: room_id, tenant_id: tenant_id} do
    :ok = Realtime.Music.TempoServer.start_clock(room_id, tenant_id)

    # Wait for first beat
    assert_receive {:beat, _}, 600

    # Change tempo multiple times
    :ok = Realtime.Music.TempoServer.set_tempo(room_id, tenant_id, 140)
    assert_receive {:beat, _}, 500

    :ok = Realtime.Music.TempoServer.set_tempo(room_id, tenant_id, 100)
    assert_receive {:beat, _}, 700

    :ok = Realtime.Music.TempoServer.set_tempo(room_id, tenant_id, 120)

    # Verify beats still arrive at correct intervals
    intervals =
      Enum.reduce(1..5, {[], System.monotonic_time(:millisecond)}, fn _, {acc, last_time} ->
        assert_receive {:beat, _}, 600
        current_time = System.monotonic_time(:millisecond)
        interval = current_time - last_time
        {[interval | acc], current_time}
      end)
      |> elem(0)
      |> Enum.reverse()

    avg_interval = Enum.sum(intervals) / length(intervals)
    assert avg_interval >= 450 and avg_interval <= 550
  end
end
