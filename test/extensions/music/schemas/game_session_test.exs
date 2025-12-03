defmodule Realtime.Music.Schemas.GameSessionTest do
  use Realtime.DataCase

  alias Realtime.Music.Schemas.GameSession
  alias Realtime.Repo

  test "can save game session" do
    game_state = %{
      "melody_sequence" => [%{"midi" => 60, "velocity" => 80}],
      "melody_state" => "building"
    }

    changeset =
      GameSession.changeset(%GameSession{}, %{
        room_id: "MUSIC-123",
        tenant_id: "test-tenant",
        game_type: "melody_builder",
        game_state: game_state,
        started_at: DateTime.utc_now()
      })

    assert changeset.valid?
    assert {:ok, session} = Repo.insert(changeset)
    assert session.game_type == "melody_builder"
    # game_state is stored as JSONB, comes back with string keys
    assert session.game_state["melody_sequence"] == [%{"midi" => 60, "velocity" => 80}]
  end

  test "can load game sessions for room" do
    room_id = "MUSIC-123"
    tenant_id = "test-tenant"

    # Create multiple sessions
    for i <- 1..3 do
      changeset =
        GameSession.changeset(%GameSession{}, %{
          room_id: room_id,
          tenant_id: tenant_id,
          game_type: "melody_builder",
          game_state: %{"session" => i},
          started_at: DateTime.utc_now()
        })

      Repo.insert!(changeset)
    end

    sessions = Realtime.Music.SessionManager.get_game_sessions(room_id, tenant_id)
    assert length(sessions) == 3
  end

  test "validates required fields" do
    changeset = GameSession.changeset(%GameSession{}, %{})

    refute changeset.valid?

    assert %{
             room_id: ["can't be blank"],
             tenant_id: ["can't be blank"],
             game_type: ["can't be blank"],
             game_state: ["can't be blank"]
           } = errors_on(changeset)
  end

  test "validates game_type inclusion" do
    changeset =
      GameSession.changeset(%GameSession{}, %{
        room_id: "MUSIC-123",
        tenant_id: "test-tenant",
        game_type: "invalid_game",
        game_state: %{}
      })

    refute changeset.valid?
    assert %{game_type: ["is invalid"]} = errors_on(changeset)
  end

  test "sessions are ordered by started_at descending" do
    room_id = "MUSIC-123"
    tenant_id = "test-tenant"

    # Create sessions with different timestamps
    base_time = DateTime.utc_now()

    for i <- 1..3 do
      changeset =
        GameSession.changeset(%GameSession{}, %{
          room_id: room_id,
          tenant_id: tenant_id,
          game_type: "melody_builder",
          game_state: %{"session" => i},
          started_at: DateTime.add(base_time, i, :second)
        })

      Repo.insert!(changeset)
    end

    sessions = Realtime.Music.SessionManager.get_game_sessions(room_id, tenant_id)
    assert length(sessions) == 3

    # Should be ordered descending (most recent first)
    started_times = Enum.map(sessions, & &1.started_at)
    assert started_times == Enum.sort(started_times, {:desc, DateTime})
  end

  test "sessions are isolated by tenant" do
    room_id = "MUSIC-123"
    tenant_a = "tenant-a"
    tenant_b = "tenant-b"

    # Create session for tenant A
    changeset_a =
      GameSession.changeset(%GameSession{}, %{
        room_id: room_id,
        tenant_id: tenant_a,
        game_type: "melody_builder",
        game_state: %{"session" => "a"},
        started_at: DateTime.utc_now()
      })

    Repo.insert!(changeset_a)

    # Create session for tenant B
    changeset_b =
      GameSession.changeset(%GameSession{}, %{
        room_id: room_id,
        tenant_id: tenant_b,
        game_type: "rhythm_circle",
        game_state: %{"session" => "b"},
        started_at: DateTime.utc_now()
      })

    Repo.insert!(changeset_b)

    # Each tenant should only see their own sessions
    sessions_a = Realtime.Music.SessionManager.get_game_sessions(room_id, tenant_a)
    assert length(sessions_a) == 1
    assert hd(sessions_a).game_state["session"] == "a"

    sessions_b = Realtime.Music.SessionManager.get_game_sessions(room_id, tenant_b)
    assert length(sessions_b) == 1
    assert hd(sessions_b).game_state["session"] == "b"
  end
end
