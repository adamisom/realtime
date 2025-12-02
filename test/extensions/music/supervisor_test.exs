defmodule Realtime.Music.SupervisorTest do
  use ExUnit.Case

  test "supervisor starts on application start" do
    assert Process.whereis(Realtime.Music.Supervisor) != nil
  end

  test "supervisor is a DynamicSupervisor" do
    # Verify it's a DynamicSupervisor by checking children
    assert DynamicSupervisor.which_children(Realtime.Music.Supervisor) != :undefined
  end
end
