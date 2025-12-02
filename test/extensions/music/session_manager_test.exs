defmodule Realtime.Music.SessionManagerTest do
  use ExUnit.Case
  
  test "module exists" do
    assert Code.ensure_loaded?(Realtime.Music.SessionManager)
  end
  
  test "session manager is running" do
    assert Process.whereis(Realtime.Music.SessionManager) != nil
  end
end

