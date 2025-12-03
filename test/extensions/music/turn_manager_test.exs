defmodule Realtime.Music.TurnManagerTest do
  use ExUnit.Case, async: true

  alias Realtime.Music.TurnManager

  describe "start_turn_rotation/2" do
    test "creates turn manager with first student" do
      students = ["student-1", "student-2", "student-3"]
      tm = TurnManager.start_turn_rotation(students, 30)

      assert tm.current_turn == "student-1"
      assert tm.queue == ["student-2", "student-3"]
      assert tm.turn_duration_seconds == 30
      assert tm.turn_state == :waiting
    end
  end

  describe "start_turn/1" do
    test "starts timing for current turn" do
      students = ["student-1", "student-2"]
      tm = TurnManager.start_turn_rotation(students, 30)
      tm = TurnManager.start_turn(tm)

      assert tm.turn_state == :active
      assert is_integer(tm.turn_start_time)
      assert tm.turn_start_time > 0
    end
  end

  describe "next_turn/1" do
    test "rotates to next student" do
      students = ["student-1", "student-2", "student-3"]
      tm = TurnManager.start_turn_rotation(students, 30)
      tm = TurnManager.next_turn(tm)

      assert tm.current_turn == "student-2"
      assert tm.queue == ["student-3", "student-1"]
      assert tm.turn_state == :waiting
    end

    test "cycles through all students" do
      students = ["student-1", "student-2"]
      tm = TurnManager.start_turn_rotation(students, 30)

      # First turn
      assert tm.current_turn == "student-1"
      tm = TurnManager.next_turn(tm)

      # Second turn
      assert tm.current_turn == "student-2"
      tm = TurnManager.next_turn(tm)

      # Back to first
      assert tm.current_turn == "student-1"
    end
  end

  describe "get_current_turn/1" do
    test "returns current turn student ID" do
      students = ["student-1", "student-2"]
      tm = TurnManager.start_turn_rotation(students, 30)

      assert TurnManager.get_current_turn(tm) == "student-1"
    end
  end

  describe "time_remaining/1" do
    test "returns remaining time for active turn" do
      students = ["student-1"]
      tm = TurnManager.start_turn_rotation(students, 30)
      tm = TurnManager.start_turn(tm)

      remaining = TurnManager.time_remaining(tm)
      assert is_integer(remaining)
      assert remaining >= 0
      assert remaining <= 30
    end

    test "returns nil for waiting turn" do
      students = ["student-1"]
      tm = TurnManager.start_turn_rotation(students, 30)

      assert TurnManager.time_remaining(tm) == nil
    end
  end

  describe "can_act?/2" do
    test "returns true when it's student's turn" do
      students = ["student-1", "student-2"]
      tm = TurnManager.start_turn_rotation(students, 30)
      tm = TurnManager.start_turn(tm)

      assert TurnManager.can_act?(tm, "student-1") == true
      assert TurnManager.can_act?(tm, "student-2") == false
    end
  end

  describe "to_map/1 and from_map/1" do
    test "serializes and deserializes turn manager" do
      students = ["student-1", "student-2"]
      tm = TurnManager.start_turn_rotation(students, 30)
      tm = TurnManager.start_turn(tm)

      map = TurnManager.to_map(tm)
      restored = TurnManager.from_map(map)

      assert restored.current_turn == tm.current_turn
      assert restored.queue == tm.queue
      assert restored.turn_duration_seconds == tm.turn_duration_seconds
      assert restored.turn_state == tm.turn_state
    end
  end
end

