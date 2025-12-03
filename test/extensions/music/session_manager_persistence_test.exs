defmodule Realtime.Music.SessionManagerPersistenceTest do
  use Realtime.DataCase, async: false

  alias Realtime.Music.SessionManager
  alias Ecto.Adapters.SQL.Sandbox

  test "save_game_session saves active game to database" do
    tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
    teacher_id = "teacher-1"

    {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id, bpm: 120)
    :ok = SessionManager.set_game_type(room_id, tenant_id, :melody_builder)
    :ok = SessionManager.update_game_state(room_id, tenant_id, %{melody_sequence: [%{"midi" => 60}]})

    # Allow spawned task to use database connection
    Sandbox.allow(Repo, self(), Repo)

    # Save game session (async, so wait a bit)
    :ok = SessionManager.save_game_session(room_id, tenant_id)
    Process.sleep(200)

    # Verify session was saved
    sessions = SessionManager.get_game_sessions(room_id, tenant_id)
    assert length(sessions) == 1

    session = hd(sessions)
    assert session.room_id == room_id
    assert session.tenant_id == tenant_id
    assert session.game_type == "melody_builder"
    # game_state comes back from DB as JSONB with string keys
    assert is_map(session.game_state)
    assert Map.has_key?(session.game_state, "melody_sequence")
    assert session.started_at != nil
  end

  test "save_game_session does not save when no game is active" do
    tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
    teacher_id = "teacher-1"

    {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id, bpm: 120)
    # Don't set game type

    # Allow spawned task to use database connection
    Sandbox.allow(Repo, self(), Repo)

    # Save game session (async, so wait a bit)
    :ok = SessionManager.save_game_session(room_id, tenant_id)
    Process.sleep(200)

    # Verify no session was saved
    sessions = SessionManager.get_game_sessions(room_id, tenant_id)
    assert length(sessions) == 0
  end

  test "save_game_session does not save for wrong tenant" do
    tenant_a = "tenant-a-#{System.unique_integer([:positive])}"
    tenant_b = "tenant-b-#{System.unique_integer([:positive])}"
    teacher_id = "teacher-1"

    {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_a, bpm: 120)
    :ok = SessionManager.set_game_type(room_id, tenant_a, :melody_builder)

    # Allow spawned task to use database connection
    Sandbox.allow(Repo, self(), Repo)

    # Try to save with wrong tenant
    :ok = SessionManager.save_game_session(room_id, tenant_b)
    Process.sleep(200)

    # Verify no session was saved for tenant B
    sessions_b = SessionManager.get_game_sessions(room_id, tenant_b)
    assert length(sessions_b) == 0

    # But tenant A can still save
    :ok = SessionManager.save_game_session(room_id, tenant_a)
    Process.sleep(200)

    sessions_a = SessionManager.get_game_sessions(room_id, tenant_a)
    assert length(sessions_a) == 1
  end

  test "get_game_sessions returns empty list for non-existent room" do
    tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
    sessions = SessionManager.get_game_sessions("NONEXISTENT", tenant_id)
    assert sessions == []
  end

  test "can save multiple game sessions for same room" do
    tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
    teacher_id = "teacher-1"

    {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id, bpm: 120)

    # Allow spawned tasks to use database connection
    Sandbox.allow(Repo, self(), Repo)

    # Save first session
    :ok = SessionManager.set_game_type(room_id, tenant_id, :melody_builder)
    :ok = SessionManager.update_game_state(room_id, tenant_id, %{session: 1})
    :ok = SessionManager.save_game_session(room_id, tenant_id)
    Process.sleep(200)

    # Save second session
    :ok = SessionManager.set_game_type(room_id, tenant_id, :rhythm_circle)
    :ok = SessionManager.update_game_state(room_id, tenant_id, %{session: 2})
    :ok = SessionManager.save_game_session(room_id, tenant_id)
    Process.sleep(200)

    # Verify both sessions were saved
    sessions = SessionManager.get_game_sessions(room_id, tenant_id)
    assert length(sessions) == 2

    # Verify they're ordered by started_at descending
    started_times = Enum.map(sessions, & &1.started_at)
    assert started_times == Enum.sort(started_times, {:desc, DateTime})
  end
end
