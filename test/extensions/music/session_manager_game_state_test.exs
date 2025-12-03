defmodule Realtime.Music.SessionManagerGameStateTest do
  use ExUnit.Case, async: false

  alias Realtime.Music.SessionManager

  setup do
    tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
    {:ok, room_id} = SessionManager.create_room("teacher-1", tenant_id, bpm: 120)
    {:ok, tenant_id: tenant_id, room_id: room_id}
  end

  test "can set game type", %{room_id: room_id, tenant_id: tenant_id} do
    :ok = SessionManager.set_game_type(room_id, tenant_id, :melody_builder)

    {:ok, state} = SessionManager.get_game_state(room_id, tenant_id)
    assert state.game_type == :melody_builder
  end

  test "can update game state", %{room_id: room_id, tenant_id: tenant_id} do
    :ok = SessionManager.set_game_type(room_id, tenant_id, :melody_builder)

    :ok =
      SessionManager.update_game_state(room_id, tenant_id, %{
        melody_sequence: [%{midi: 60, velocity: 80}],
        melody_state: :building
      })

    {:ok, state} = SessionManager.get_game_state(room_id, tenant_id)
    assert state.game_state.melody_sequence == [%{midi: 60, velocity: 80}]
    assert state.game_state.melody_state == :building
  end

  test "game state is merged, not replaced", %{room_id: room_id, tenant_id: tenant_id} do
    :ok = SessionManager.set_game_type(room_id, tenant_id, :melody_builder)
    :ok = SessionManager.update_game_state(room_id, tenant_id, %{melody_sequence: []})
    :ok = SessionManager.update_game_state(room_id, tenant_id, %{melody_state: :building})

    {:ok, state} = SessionManager.get_game_state(room_id, tenant_id)
    assert state.game_state.melody_sequence == []
    assert state.game_state.melody_state == :building
  end
end

