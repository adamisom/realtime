defmodule Realtime.Music.SessionManagerTest do
  use ExUnit.Case, async: false

  alias Realtime.Music.SessionManager

  setup do
    # SessionManager is started by the application supervisor
    # Clear state between tests by closing any existing rooms
    :ok
  end

  describe "beat assignments" do
    test "assign_beat stores assignment" do
      tenant_id = "tenant-1"
      teacher_id = "teacher-1"
      
      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)
      
      assert :ok = SessionManager.assign_beat(room_id, 1, "student-1")
      assert {:ok, assignments} = SessionManager.get_beat_assignments(room_id)
      assert assignments == %{1 => "student-1"}
    end

    test "assign_beat updates existing assignment" do
      tenant_id = "tenant-1"
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
      tenant_id = "tenant-1"
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
      tenant_id = "tenant-1"
      teacher_id = "teacher-1"
      
      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)
      
      assert {:ok, assignments} = SessionManager.get_beat_assignments(room_id)
      assert assignments == %{}
    end

    test "get_beat_assignments returns error for non-existent room" do
      assert {:error, :not_found} = SessionManager.get_beat_assignments("NONEXISTENT")
    end

    test "clear_beat_assignment removes assignment" do
      tenant_id = "tenant-1"
      teacher_id = "teacher-1"
      
      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)
      
      assert :ok = SessionManager.assign_beat(room_id, 1, "student-1")
      assert :ok = SessionManager.assign_beat(room_id, 2, "student-2")
      
      assert :ok = SessionManager.clear_beat_assignment(room_id, 1)
      
      assert {:ok, assignments} = SessionManager.get_beat_assignments(room_id)
      assert assignments == %{2 => "student-2"}
    end

    test "clear_beat_assignment handles non-existent assignment gracefully" do
      tenant_id = "tenant-1"
      teacher_id = "teacher-1"
      
      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)
      
      # Clearing non-existent assignment should not error
      assert :ok = SessionManager.clear_beat_assignment(room_id, 99)
    end

    test "clear_all_assignments removes all assignments" do
      tenant_id = "tenant-1"
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
      tenant_id = "tenant-1"
      teacher_id = "teacher-1"
      
      {:ok, room_id} = SessionManager.create_room(teacher_id, tenant_id)
      
      assert :ok = SessionManager.assign_beat(room_id, 1, "student-1")
      
      # Join a student (should not affect assignments)
      assert :ok = SessionManager.join_room(room_id, tenant_id, "student-2")
      
      assert {:ok, assignments} = SessionManager.get_beat_assignments(room_id)
      assert assignments == %{1 => "student-1"}
    end
  end
end

