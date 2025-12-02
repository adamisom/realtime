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
      assert String.length(room_id) == 10  # "MUSIC-####"
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
      assert :ok = SessionManager.join_room(room_id, tenant_id, student_id)  # Join again
      
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
      Process.sleep(100)  # Give it time to stop
      assert Registry.lookup(Realtime.Music.Registry, {:tempo_server, tenant_id, room_id}) == []
    end

    test "returns error for non-existent room" do
      assert {:error, :not_found} = SessionManager.close_room("NONEXISTENT")
    end
  end
end
