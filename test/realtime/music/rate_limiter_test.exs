defmodule Realtime.Music.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Realtime.Music.RateLimiter

  setup do
    # RateLimiter is started by the application supervisor
    # Clear ETS table between tests
    :ets.delete_all_objects(RateLimiter)

    :ok
  end

  describe "check_rate_limit/4" do
    test "allows note play when under limit" do
      assert {:ok, :allowed} = RateLimiter.check_rate_limit("room-1", "tenant-1", "student-1", 10)
    end

    test "allows note play when no previous plays" do
      assert {:ok, :allowed} = RateLimiter.check_rate_limit("room-1", "tenant-1", "student-2", 10)
    end

    test "rejects note play when rate limit exceeded" do
      room_id = "room-1"
      tenant_id = "tenant-1"
      student_id = "student-1"
      max_per_second = 5

      # Record 5 notes rapidly (within 1 second)
      Enum.each(1..5, fn _ ->
        RateLimiter.record_note_play(room_id, tenant_id, student_id)
      end)

      # 6th note should be rejected
      assert {:error, :rate_limit_exceeded} =
               RateLimiter.check_rate_limit(room_id, tenant_id, student_id, max_per_second)
    end

    test "allows note play after time window passes" do
      room_id = "room-1"
      tenant_id = "tenant-1"
      student_id = "student-3"
      max_per_second = 2

      # Record 2 notes
      RateLimiter.record_note_play(room_id, tenant_id, student_id)
      RateLimiter.record_note_play(room_id, tenant_id, student_id)

      # Should be at limit
      assert {:error, :rate_limit_exceeded} =
               RateLimiter.check_rate_limit(room_id, tenant_id, student_id, max_per_second)

      # Wait 1.1 seconds (just over the window)
      Process.sleep(1100)

      # Should now be allowed
      assert {:ok, :allowed} = RateLimiter.check_rate_limit(room_id, tenant_id, student_id, max_per_second)
    end
  end

  describe "record_note_play/3" do
    test "records note play timestamp" do
      room_id = "room-2"
      tenant_id = "tenant-1"
      student_id = "student-4"

      assert :ok = RateLimiter.record_note_play(room_id, tenant_id, student_id)

      # After recording, check should still allow (only 1 note)
      assert {:ok, :allowed} = RateLimiter.check_rate_limit(room_id, tenant_id, student_id, 10)
    end

    test "tracks separate limits per student" do
      room_id = "room-3"
      tenant_id = "tenant-1"
      max_per_second = 2

      # Student 1 plays 2 notes
      RateLimiter.record_note_play(room_id, tenant_id, "student-5")
      RateLimiter.record_note_play(room_id, tenant_id, "student-5")

      # Student 1 should be at limit
      assert {:error, :rate_limit_exceeded} =
               RateLimiter.check_rate_limit(room_id, tenant_id, "student-5", max_per_second)

      # Student 2 should still be allowed
      assert {:ok, :allowed} = RateLimiter.check_rate_limit(room_id, tenant_id, "student-6", max_per_second)
    end

    test "tracks separate limits per room" do
      tenant_id = "tenant-1"
      student_id = "student-7"
      max_per_second = 2

      # Play 2 notes in room-4
      RateLimiter.record_note_play("room-4", tenant_id, student_id)
      RateLimiter.record_note_play("room-4", tenant_id, student_id)

      # Should be at limit in room-4
      assert {:error, :rate_limit_exceeded} =
               RateLimiter.check_rate_limit("room-4", tenant_id, student_id, max_per_second)

      # Should still be allowed in room-5
      assert {:ok, :allowed} = RateLimiter.check_rate_limit("room-5", tenant_id, student_id, max_per_second)
    end

    test "tracks separate limits per tenant" do
      room_id = "room-6"
      student_id = "student-8"
      max_per_second = 2

      # Play 2 notes in tenant-1
      RateLimiter.record_note_play(room_id, "tenant-1", student_id)
      RateLimiter.record_note_play(room_id, "tenant-1", student_id)

      # Should be at limit in tenant-1
      assert {:error, :rate_limit_exceeded} =
               RateLimiter.check_rate_limit(room_id, "tenant-1", student_id, max_per_second)

      # Should still be allowed in tenant-2
      assert {:ok, :allowed} = RateLimiter.check_rate_limit(room_id, "tenant-2", student_id, max_per_second)
    end
  end

  describe "integration" do
    test "check and record workflow" do
      room_id = "room-7"
      tenant_id = "tenant-1"
      student_id = "student-9"
      max_per_second = 3

      # Check before recording (should allow)
      assert {:ok, :allowed} = RateLimiter.check_rate_limit(room_id, tenant_id, student_id, max_per_second)

      # Record 3 notes
      Enum.each(1..3, fn _ ->
        assert {:ok, :allowed} = RateLimiter.check_rate_limit(room_id, tenant_id, student_id, max_per_second)
        RateLimiter.record_note_play(room_id, tenant_id, student_id)
      end)

      # 4th should be rejected
      assert {:error, :rate_limit_exceeded} =
               RateLimiter.check_rate_limit(room_id, tenant_id, student_id, max_per_second)
    end
  end
end
