defmodule Realtime.Music.TempoServerTest do
  use ExUnit.Case, async: false
  
  alias Realtime.Tenants
  
  setup do
    tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
    room_id = "test-room-#{System.unique_integer([:positive])}"
    {:ok, pid} = Realtime.Music.Supervisor.start_tempo_server(room_id, 120, tenant_id)
    {:ok, room_id: room_id, tenant_id: tenant_id, pid: pid}
  end
  
  test "starts with correct BPM", %{room_id: room_id, tenant_id: tenant_id} do
    assert {:ok, 120} = Realtime.Music.TempoServer.get_tempo(room_id, tenant_id)
  end
  
  test "can change tempo", %{room_id: room_id, tenant_id: tenant_id} do
    :ok = Realtime.Music.TempoServer.set_tempo(room_id, tenant_id, 140)
    assert {:ok, 140} = Realtime.Music.TempoServer.get_tempo(room_id, tenant_id)
  end
  
  test "broadcasts beat events", %{room_id: room_id, tenant_id: tenant_id} do
    # Subscribe to PubSub topic using Tenants.tenant_topic/3
    tenant_topic = Tenants.tenant_topic(tenant_id, "music_room:#{room_id}", true)
    Phoenix.PubSub.subscribe(Realtime.PubSub, tenant_topic)
    
    # Start clock
    :ok = Realtime.Music.TempoServer.start_clock(room_id, tenant_id)
    
    # Wait for beat (120 BPM = ~500ms per beat)
    assert_receive {:beat, beat_number}, 600
    assert beat_number >= 0
    
    # Should receive more beats
    assert_receive {:beat, _}, 600
  end
  
  test "can start and stop clock", %{room_id: room_id, tenant_id: tenant_id} do
    tenant_topic = Tenants.tenant_topic(tenant_id, "music_room:#{room_id}", true)
    Phoenix.PubSub.subscribe(Realtime.PubSub, tenant_topic)
    
    :ok = Realtime.Music.TempoServer.start_clock(room_id, tenant_id)
    
    # Wait for one beat to confirm it's running
    assert_receive {:beat, _}, 600
    
    :ok = Realtime.Music.TempoServer.stop_clock(room_id, tenant_id)
    
    # Should not receive beats after stopping
    refute_receive {:beat, _}, 600
  end
  
  test "handles tempo changes while running", %{room_id: room_id, tenant_id: tenant_id} do
    tenant_topic = Tenants.tenant_topic(tenant_id, "music_room:#{room_id}", true)
    Phoenix.PubSub.subscribe(Realtime.PubSub, tenant_topic)
    
    # Start with slow tempo
    :ok = Realtime.Music.TempoServer.set_tempo(room_id, tenant_id, 60)
    :ok = Realtime.Music.TempoServer.start_clock(room_id, tenant_id)
    
    # Wait for first beat (slow tempo = ~1000ms)
    assert_receive {:beat, _}, 1200
    
    # Change to fast tempo
    :ok = Realtime.Music.TempoServer.set_tempo(room_id, tenant_id, 180)
    
    # Should receive beats faster now (180 BPM = ~333ms per beat)
    assert_receive {:beat, _}, 400
  end
  
  test "validates BPM range", %{room_id: room_id, tenant_id: tenant_id} do
    # Too low
    assert {:error, :invalid_bpm} = Realtime.Music.TempoServer.set_tempo(room_id, tenant_id, 0)
    assert {:error, :invalid_bpm} = Realtime.Music.TempoServer.set_tempo(room_id, tenant_id, -10)
    
    # Too high
    assert {:error, :invalid_bpm} = Realtime.Music.TempoServer.set_tempo(room_id, tenant_id, 300)
    assert {:error, :invalid_bpm} = Realtime.Music.TempoServer.set_tempo(room_id, tenant_id, 500)
    
    # Valid range
    assert :ok = Realtime.Music.TempoServer.set_tempo(room_id, tenant_id, 1)
    assert :ok = Realtime.Music.TempoServer.set_tempo(room_id, tenant_id, 299)
  end
  
  test "beat counter increments", %{room_id: room_id, tenant_id: tenant_id} do
    tenant_topic = Tenants.tenant_topic(tenant_id, "music_room:#{room_id}", true)
    Phoenix.PubSub.subscribe(Realtime.PubSub, tenant_topic)
    
    :ok = Realtime.Music.TempoServer.start_clock(room_id, tenant_id)
    
    # Receive first beat
    assert_receive {:beat, 0}, 600
    
    # Receive second beat
    assert_receive {:beat, 1}, 600
    
    # Receive third beat
    assert_receive {:beat, 2}, 600
  end
end

