defmodule Realtime.Music.AnalyticsTest do
  use ExUnit.Case, async: false

  alias Realtime.Music.Analytics
  alias Realtime.Music.SelTracker

  setup do
    # Ensure we're using the test repo
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Realtime.Repo)
  end

  describe "get_room_statistics/2" do
    test "returns zero statistics for room with no events" do
      stats = Analytics.get_room_statistics("EMPTY-ROOM", "tenant-1")

      assert stats.total_notes == 0
      assert stats.notes_per_minute == 0
      assert stats.tempo_changes == 0
      assert stats.session_duration_minutes == 0
      assert stats.unique_students == 0
    end

    test "calculates statistics correctly" do
      room_id = "TEST-ROOM-1"
      tenant_id = "tenant-1"

      # Log some events
      SelTracker.log_participation(room_id, tenant_id, "student-1", "note_played", %{midi: 60})
      SelTracker.log_participation(room_id, tenant_id, "student-1", "note_played", %{midi: 64})
      SelTracker.log_participation(room_id, tenant_id, "student-2", "note_played", %{midi: 67})
      SelTracker.log_participation(room_id, tenant_id, "teacher-1", "tempo_changed", %{bpm: 140})

      # Wait a moment for timestamps
      Process.sleep(100)

      stats = Analytics.get_room_statistics(room_id, tenant_id)

      assert stats.total_notes == 3
      assert stats.tempo_changes == 1
      # student-1, student-2, teacher-1 (all participants)
      assert stats.unique_students == 3
      assert stats.session_duration_minutes >= 0
    end
  end

  describe "get_participation_breakdown/2" do
    test "returns empty map for room with no events" do
      breakdown = Analytics.get_participation_breakdown("EMPTY-ROOM", "tenant-1")
      assert breakdown == %{}
    end

    test "counts events per student" do
      room_id = "TEST-ROOM-2"
      tenant_id = "tenant-1"

      # Log events for different students
      SelTracker.log_participation(room_id, tenant_id, "student-1", "note_played", %{midi: 60})
      SelTracker.log_participation(room_id, tenant_id, "student-1", "note_played", %{midi: 64})
      SelTracker.log_participation(room_id, tenant_id, "student-2", "note_played", %{midi: 67})

      breakdown = Analytics.get_participation_breakdown(room_id, tenant_id)

      assert breakdown["student-1"] == 2
      assert breakdown["student-2"] == 1
    end
  end

  describe "get_activity_over_time/3" do
    test "returns empty list for room with no events" do
      activity = Analytics.get_activity_over_time("EMPTY-ROOM", "tenant-1")
      assert activity == []
    end

    test "groups events by time intervals" do
      room_id = "TEST-ROOM-3"
      tenant_id = "tenant-1"

      # Log some events
      SelTracker.log_participation(room_id, tenant_id, "student-1", "note_played", %{midi: 60})
      SelTracker.log_participation(room_id, tenant_id, "student-1", "note_played", %{midi: 64})

      activity = Analytics.get_activity_over_time(room_id, tenant_id, 1)

      assert length(activity) > 0
      assert List.first(activity).event_count > 0
    end
  end
end
