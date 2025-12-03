defmodule Realtime.Music.SessionManagerTest do
  use ExUnit.Case, async: false

  alias Realtime.Music.SessionManager

  setup do
    # Clear any existing rooms (in case of test pollution)
    # Note: In a real scenario, we'd reset the GenServer state
    :ok
  end

  describe "create_room/3" do
    test "creates a room with unique join code" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      assert {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id, bpm: 120)
      assert String.starts_with?(room_id, "MUSIC-")
      # "MUSIC-####"
      assert String.length(room_id) == 10
    end

    test "creates room with custom BPM" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      assert {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id, bpm: 140)

      assert {:ok, room} = SessionManager.get_room(room_id)
      assert room.bpm == 140
    end

    test "creates room with default BPM" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      assert {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)

      assert {:ok, room} = SessionManager.get_room(room_id)
      assert room.bpm == 120
    end

    test "stores tenant_id in room" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      assert {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)

      assert {:ok, room} = SessionManager.get_room(room_id)
      assert room.tenant_id == tenant_id
      assert room.teacher_id == teacher_id
    end

    test "starts tempo server for new room" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      assert {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id, bpm: 120)

      # Verify tempo server is running
      assert [{_pid, nil}] = Registry.lookup(Realtime.Music.Registry, {:tempo_server, tenant_id, room_id})
    end
  end

  describe "get_room/1" do
    test "returns room information" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id, bpm: 120)

      assert {:ok, room} = SessionManager.get_room(room_id)
      assert room.room_id == room_id
      assert room.teacher_id == teacher_id
      assert room.tenant_id == tenant_id
      assert room.bpm == 120
      assert room.students == []
      assert is_integer(room.created_at)
    end

    test "returns error for non-existent room" do
      assert {:error, :not_found} = SessionManager.get_room("NONEXISTENT")
    end
  end

  describe "join_room/3" do
    test "adds student to room" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"
      student_id = "student-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)

      assert :ok = SessionManager.join_room(room_id, tenant_id, student_id)

      assert {:ok, room} = SessionManager.get_room(room_id)
      assert student_id in room.students
    end

    test "allows multiple students to join" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)

      assert :ok = SessionManager.join_room(room_id, tenant_id, "student-1")
      assert :ok = SessionManager.join_room(room_id, tenant_id, "student-2")
      assert :ok = SessionManager.join_room(room_id, tenant_id, "student-3")

      assert {:ok, room} = SessionManager.get_room(room_id)
      assert length(room.students) == 3
      assert "student-1" in room.students
      assert "student-2" in room.students
      assert "student-3" in room.students
    end

    test "does not duplicate student if already in room" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"
      student_id = "student-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)

      assert :ok = SessionManager.join_room(room_id, tenant_id, student_id)
      # Join again
      assert :ok = SessionManager.join_room(room_id, tenant_id, student_id)

      assert {:ok, room} = SessionManager.get_room(room_id)
      assert length(room.students) == 1
      assert student_id in room.students
    end

    test "returns error for non-existent room" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      assert {:error, :not_found} = SessionManager.join_room("NONEXISTENT", tenant_id, "student-1")
    end

    test "returns error when tenant_id does not match" do
      tenant_id1 = "test-tenant-#{System.unique_integer([:positive])}"
      tenant_id2 = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"
      student_id = "student-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id1)

      # Try to join with different tenant_id
      assert {:error, :not_found} = SessionManager.join_room(room_id, tenant_id2, student_id)
    end
  end

  describe "close_room/1" do
    test "closes room and stops tempo server" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)

      # Verify tempo server is running
      assert [{_pid, nil}] = Registry.lookup(Realtime.Music.Registry, {:tempo_server, tenant_id, room_id})

      assert :ok = SessionManager.close_room(room_id)

      # Verify room is gone
      assert {:error, :not_found} = SessionManager.get_room(room_id)

      # Verify tempo server is stopped
      # Give it time to stop
      Process.sleep(100)
      assert Registry.lookup(Realtime.Music.Registry, {:tempo_server, tenant_id, room_id}) == []
    end

    test "returns error for non-existent room" do
      assert {:error, :not_found} = SessionManager.close_room("NONEXISTENT")
    end
  end

  describe "beat assignments" do
    test "assign_beat stores assignment" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)

      assert :ok = SessionManager.assign_beat(room_id, 1, "student-1")
      assert {:ok, assignments} = SessionManager.get_beat_assignments(room_id)
      assert assignments == %{1 => "student-1"}
    end

    test "assign_beat updates existing assignment" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)

      # Assign beat 1 to student-1
      assert :ok = SessionManager.assign_beat(room_id, 1, "student-1")

      # Reassign beat 1 to student-2
      assert :ok = SessionManager.assign_beat(room_id, 1, "student-2")

      assert {:ok, assignments} = SessionManager.get_beat_assignments(room_id)
      assert assignments == %{1 => "student-2"}
    end

    test "assign_beat supports multiple beats" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)

      assert :ok = SessionManager.assign_beat(room_id, 1, "student-1")
      assert :ok = SessionManager.assign_beat(room_id, 2, "student-2")
      assert :ok = SessionManager.assign_beat(room_id, 3, "student-1")

      assert {:ok, assignments} = SessionManager.get_beat_assignments(room_id)
      assert assignments == %{1 => "student-1", 2 => "student-2", 3 => "student-1"}
    end

    test "assign_beat returns error for non-existent room" do
      assert {:error, :not_found} = SessionManager.assign_beat("NONEXISTENT", 1, "student-1")
    end

    test "get_beat_assignments returns empty map for room with no assignments" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)

      assert {:ok, assignments} = SessionManager.get_beat_assignments(room_id)
      assert assignments == %{}
    end

    test "get_beat_assignments returns error for non-existent room" do
      assert {:error, :not_found} = SessionManager.get_beat_assignments("NONEXISTENT")
    end

    test "clear_beat_assignment removes assignment" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)

      assert :ok = SessionManager.assign_beat(room_id, 1, "student-1")
      assert :ok = SessionManager.assign_beat(room_id, 2, "student-2")

      assert :ok = SessionManager.clear_beat_assignment(room_id, 1)

      assert {:ok, assignments} = SessionManager.get_beat_assignments(room_id)
      assert assignments == %{2 => "student-2"}
    end

    test "clear_beat_assignment handles non-existent assignment gracefully" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)

      # Clearing non-existent assignment should not error
      assert :ok = SessionManager.clear_beat_assignment(room_id, 99)
    end

    test "clear_all_assignments removes all assignments" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)

      assert :ok = SessionManager.assign_beat(room_id, 1, "student-1")
      assert :ok = SessionManager.assign_beat(room_id, 2, "student-2")
      assert :ok = SessionManager.assign_beat(room_id, 3, "student-3")

      assert :ok = SessionManager.clear_all_assignments(room_id)

      assert {:ok, assignments} = SessionManager.get_beat_assignments(room_id)
      assert assignments == %{}
    end

    test "beat assignments persist across room operations" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)

      assert :ok = SessionManager.assign_beat(room_id, 1, "student-1")

      # Join a student (should not affect assignments)
      assert :ok = SessionManager.join_room(room_id, tenant_id, "student-2")

      assert {:ok, assignments} = SessionManager.get_beat_assignments(room_id)
      assert assignments == %{1 => "student-1"}
    end
  end

  describe "game state management" do
    test "create_room initializes game fields" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)

      assert {:ok, room} = SessionManager.get_room(room_id)
      assert room.game_type == nil
      assert room.game_state == %{}
    end

    test "set_game_type sets game type" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)

      assert :ok = SessionManager.set_game_type(room_id, tenant_id, :melody_builder)

      assert {:ok, game_state} = SessionManager.get_game_state(room_id, tenant_id)
      assert game_state.game_type == :melody_builder
      assert game_state.game_state == %{}
    end

    test "update_game_state merges state" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)

      assert :ok = SessionManager.update_game_state(room_id, tenant_id, %{key1: "value1"})
      assert :ok = SessionManager.update_game_state(room_id, tenant_id, %{key2: "value2"})

      assert {:ok, game_state} = SessionManager.get_game_state(room_id, tenant_id)
      assert game_state.game_state.key1 == "value1"
      assert game_state.game_state.key2 == "value2"
    end

    test "get_game_state returns error for non-existent room" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      assert {:error, :not_found} = SessionManager.get_game_state("NONEXISTENT", tenant_id)
    end

    test "set_game_type validates game type" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)

      # Invalid game type should raise FunctionClauseError
      assert_raise FunctionClauseError, fn ->
        SessionManager.set_game_type(room_id, tenant_id, :invalid_game)
      end
    end
  end

  describe "turn management" do
    test "start_turn_rotation creates turn rotation" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)
      :ok = SessionManager.join_room(room_id, tenant_id, "student-1")
      :ok = SessionManager.join_room(room_id, tenant_id, "student-2")

      {:ok, room} = SessionManager.get_room(room_id)

      assert :ok =
               SessionManager.start_turn_rotation(room_id, tenant_id, room.students, 30)

      {:ok, turn_info} = SessionManager.get_current_turn(room_id, tenant_id)
      assert turn_info.current_turn in room.students
      assert turn_info.turn_state == :waiting
    end

    test "start_current_turn begins timing" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)
      :ok = SessionManager.join_room(room_id, tenant_id, "student-1")

      {:ok, room} = SessionManager.get_room(room_id)
      :ok = SessionManager.start_turn_rotation(room_id, tenant_id, room.students, 30)
      :ok = SessionManager.start_current_turn(room_id, tenant_id)

      {:ok, turn_info} = SessionManager.get_current_turn(room_id, tenant_id)
      assert turn_info.turn_state == :active
      assert is_integer(turn_info.time_remaining)
    end

    test "advance_turn moves to next student" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)
      :ok = SessionManager.join_room(room_id, tenant_id, "student-1")
      :ok = SessionManager.join_room(room_id, tenant_id, "student-2")

      {:ok, room} = SessionManager.get_room(room_id)
      :ok = SessionManager.start_turn_rotation(room_id, tenant_id, room.students, 30)

      {:ok, turn_info1} = SessionManager.get_current_turn(room_id, tenant_id)
      first_turn = turn_info1.current_turn

      :ok = SessionManager.advance_turn(room_id, tenant_id)

      {:ok, turn_info2} = SessionManager.get_current_turn(room_id, tenant_id)
      assert turn_info2.current_turn != first_turn
    end
  end

  describe "pattern matching" do
    test "set_call_pattern stores call pattern" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)

      pattern = [%{midi: 60, timestamp: 0, duration: 500, velocity: 80}]

      assert :ok = SessionManager.set_call_pattern(room_id, tenant_id, pattern)

      {:ok, game_state} = SessionManager.get_game_state(room_id, tenant_id)
      assert game_state.game_state.call_pattern == pattern
    end

    test "record_response stores student response" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)

      response = [%{midi: 60, timestamp: 0, duration: 500, velocity: 80}]

      assert :ok = SessionManager.record_response(room_id, tenant_id, "student-1", response)

      {:ok, game_state} = SessionManager.get_game_state(room_id, tenant_id)
      assert game_state.game_state.responses["student-1"] == response
    end

    test "validate_response compares call and response" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)

      call_pattern = [%{midi: 60, timestamp: 0, duration: 500, velocity: 80}]
      response_pattern = [%{midi: 60, timestamp: 0, duration: 500, velocity: 80}]

      :ok = SessionManager.set_call_pattern(room_id, tenant_id, call_pattern)
      :ok = SessionManager.record_response(room_id, tenant_id, "student-1", response_pattern)

      {:ok, feedback} = SessionManager.validate_response(room_id, tenant_id, "student-1")

      assert feedback.match == true
      assert feedback.accuracy >= 99.0
    end

    test "validate_response returns error when no call pattern" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)

      assert {:error, :no_call_pattern} =
               SessionManager.validate_response(room_id, tenant_id, "student-1")
    end

    test "validate_response returns error when no response" do
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"
      teacher_id = "teacher-1"

      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)

      call_pattern = [%{midi: 60, timestamp: 0, duration: 500, velocity: 80}]
      :ok = SessionManager.set_call_pattern(room_id, tenant_id, call_pattern)

      assert {:error, :no_response} =
               SessionManager.validate_response(room_id, tenant_id, "student-1")
    end
  end
end
