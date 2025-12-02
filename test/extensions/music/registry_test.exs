defmodule Realtime.Music.RegistryTest do
  use ExUnit.Case
  
  setup do
    # Ensure registry is started (it's started in application)
    :ok
  end
  
  test "registry exists and can register processes" do
    Registry.register(Realtime.Music.Registry, {:test, "room-1"}, nil)
    
    result = Registry.lookup(Realtime.Music.Registry, {:test, "room-1"})
    assert length(result) == 1
    assert {_pid, nil} = List.first(result)
  end
  
  test "registry can look up processes" do
    Registry.register(Realtime.Music.Registry, {:tempo_server, "tenant-1", "room-123"}, nil)
    
    result = Registry.lookup(Realtime.Music.Registry, {:tempo_server, "tenant-1", "room-123"})
    assert length(result) == 1
    assert {_pid, nil} = List.first(result)
  end
  
  test "registry returns empty list for non-existent key" do
    assert Registry.lookup(Realtime.Music.Registry, {:nonexistent, "key"}) == []
  end
end

