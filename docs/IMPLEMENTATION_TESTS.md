# Implementation Test Examples

This document contains high-value unit test examples for each phase of the music extension and games implementation. Reference these tests by phase/subphase as you implement features.

**Note:** These are example tests - adapt them to your specific implementation and add more as needed.

---

## Phase 1: Security & Remaining Work Fixes

### Subphase 1.1: Authorization Security Fix

**File: `test/realtime_web/channels/music_room_channel_auth_test.exs`**

```elixir
defmodule RealtimeWeb.MusicRoomChannelAuthTest do
  use RealtimeWeb.ChannelCase, async: true
  
  setup do
    tenant = Containers.checkout_tenant(run_migrations: true)
    Cachex.put!(Realtime.Tenants.Cache, {{:get_tenant_by_external_id, 1}, [tenant.external_id]}, {:cached, tenant})
    
    {:ok, room_id} = Realtime.Music.SessionManager.create_room("teacher-1", tenant.external_id, bpm: 120)
    
    {:ok, tenant: tenant, room_id: room_id}
  end
  
  test "role is extracted from JWT claims, not client params", %{tenant: tenant, room_id: room_id} do
    # Generate JWT with teacher role
    jwt = Generators.generate_jwt_token(tenant, %{"role" => "teacher"})
    {:ok, socket} = connect(UserSocket, %{}, conn_opts(tenant, jwt))
    
    # Client tries to send student role (should be ignored)
    params = %{"student_id" => "teacher-1", "role" => "student"}
    {:ok, _, socket} = subscribe_and_join(socket, "music_room:#{room_id}", params)
    
    # Verify role is from JWT (teacher), not params (student)
    assert socket.assigns.role == "teacher"
  end
  
  test "unauthorized user cannot access teacher controls", %{tenant: tenant, room_id: room_id} do
    # Student JWT
    jwt = Generators.generate_jwt_token(tenant, %{"role" => "student"})
    {:ok, socket} = connect(UserSocket, %{}, conn_opts(tenant, jwt))
    {:ok, _, socket} = subscribe_and_join(socket, "music_room:#{room_id}", %{"student_id" => "student-1"})
    
    # Try to set tempo (teacher-only)
    push(socket, "set_tempo", %{"bpm" => 140})
    assert_reply {:error, %{reason: "unauthorized"}}
  end
  
  test "teacher can access teacher controls", %{tenant: tenant, room_id: room_id} do
    jwt = Generators.generate_jwt_token(tenant, %{"role" => "teacher"})
    {:ok, socket} = connect(UserSocket, %{}, conn_opts(tenant, jwt))
    {:ok, _, socket} = subscribe_and_join(socket, "music_room:#{room_id}", %{"student_id" => "teacher-1"})
    
    push(socket, "set_tempo", %{"bpm" => 140})
    assert_reply :ok
  end
end
```

---

### Subphase 1.2: Tempo Server Timing Drift Fix

**File: `test/extensions/music/tempo_server_timing_test.exs`**

```elixir
defmodule Realtime.Music.TempoServerTimingTest do
  use ExUnit.Case, async: false  # Not async for timing tests
  
  setup do
    tenant_id = "test-tenant"
    room_id = "test-room-#{System.unique_integer([:positive])}"
    {:ok, pid} = Realtime.Music.Supervisor.start_tempo_server(room_id, 120, tenant_id)
    
    topic = Realtime.Tenants.tenant_topic(tenant_id, "music_room:#{room_id}", true)
    Phoenix.PubSub.subscribe(Realtime.PubSub, topic)
    
    {:ok, room_id: room_id, tenant_id: tenant_id, pid: pid, topic: topic}
  end
  
  test "beats arrive at correct intervals over extended period", %{room_id: room_id, tenant_id: tenant_id, topic: topic} do
    :ok = Realtime.Music.TempoServer.start_clock(room_id, tenant_id)
    
    # Collect 10 beats and measure intervals
    intervals = []
    last_time = System.monotonic_time(:millisecond)
    
    for _ <- 1..10 do
      assert_receive {:beat, _}, 600
      current_time = System.monotonic_time(:millisecond)
      interval = current_time - last_time
      intervals = intervals ++ [interval]
      last_time = current_time
    end
    
    # 120 BPM = 500ms per beat
    # Allow ±50ms tolerance for system scheduling
    avg_interval = Enum.sum(intervals) / length(intervals)
    assert avg_interval >= 450 and avg_interval <= 550
  end
  
  test "tempo changes don't cause drift accumulation", %{room_id: room_id, tenant_id: tenant_id} do
    topic = Realtime.Tenants.tenant_topic(tenant_id, "music_room:#{room_id}", true)
    Phoenix.PubSub.subscribe(Realtime.PubSub, topic)
    
    :ok = Realtime.Music.TempoServer.start_clock(room_id, tenant_id)
    
    # Wait for first beat
    assert_receive {:beat, _}, 600
    
    # Change tempo multiple times
    :ok = Realtime.Music.TempoServer.set_tempo(room_id, tenant_id, 140)
    assert_receive {:beat, _}, 500
    
    :ok = Realtime.Music.TempoServer.set_tempo(room_id, tenant_id, 100)
    assert_receive {:beat, _}, 700
    
    :ok = Realtime.Music.TempoServer.set_tempo(room_id, tenant_id, 120)
    
    # Verify beats still arrive at correct intervals
    intervals = []
    last_time = System.monotonic_time(:millisecond)
    
    for _ <- 1..5 do
      assert_receive {:beat, _}, 600
      current_time = System.monotonic_time(:millisecond)
      interval = current_time - last_time
      intervals = intervals ++ [interval]
      last_time = current_time
    end
    
    avg_interval = Enum.sum(intervals) / length(intervals)
    assert avg_interval >= 450 and avg_interval <= 550
  end
end
```

---

### Subphase 1.3: Room Cleanup Mechanism

**File: `test/extensions/music/session_manager_cleanup_test.exs`**

```elixir
defmodule Realtime.Music.SessionManagerCleanupTest do
  use ExUnit.Case
  
  setup do
    tenant_id = "test-tenant"
    {:ok, tenant_id: tenant_id}
  end
  
  test "expired rooms are cleaned up", %{tenant_id: tenant_id} do
    # Create room with old timestamp
    {:ok, room_id} = Realtime.Music.SessionManager.create_room("teacher-1", tenant_id, bpm: 120)
    
    # Manually set old created_at (in real scenario, this would be from time passing)
    # For test, we'll use cleanup with very short max_age
    {:ok, 1} = Realtime.Music.SessionManager.cleanup_expired_rooms(tenant_id, 0)  # 0 hours = expired
    
    # Verify room is gone
    assert {:error, :not_found} = Realtime.Music.SessionManager.get_room(room_id)
  end
  
  test "active rooms (with students) are not cleaned up", %{tenant_id: tenant_id} do
    {:ok, room_id} = Realtime.Music.SessionManager.create_room("teacher-1", tenant_id, bpm: 120)
    :ok = Realtime.Music.SessionManager.join_room(room_id, tenant_id, "student-1")
    
    # Try to cleanup (should not remove room with students)
    {:ok, 0} = Realtime.Music.SessionManager.cleanup_expired_rooms(tenant_id, 0)
    
    # Verify room still exists
    assert {:ok, _room} = Realtime.Music.SessionManager.get_room(room_id)
  end
  
  test "tempo server is stopped when room is cleaned up", %{tenant_id: tenant_id} do
    {:ok, room_id} = Realtime.Music.SessionManager.create_room("teacher-1", tenant_id, bpm: 120)
    
    # Verify tempo server exists
    assert [{pid, nil}] = Registry.lookup(Realtime.Music.Registry, {:tempo_server, tenant_id, room_id})
    assert Process.alive?(pid)
    
    # Cleanup
    {:ok, 1} = Realtime.Music.SessionManager.cleanup_expired_rooms(tenant_id, 0)
    
    # Verify tempo server is stopped
    Process.sleep(100)  # Give time for process to terminate
    assert [] = Registry.lookup(Realtime.Music.Registry, {:tempo_server, tenant_id, room_id})
  end
end
```

---

## Phase 2: Foundation Infrastructure

### Subphase 2.1: Volume/Dynamics Support

**File: `test/realtime_web/channels/music_room_channel_velocity_test.exs`**

```elixir
defmodule RealtimeWeb.MusicRoomChannelVelocityTest do
  use RealtimeWeb.ChannelCase, async: true
  
  setup do
    tenant = Containers.checkout_tenant(run_migrations: true)
    Cachex.put!(Realtime.Tenants.Cache, {{:get_tenant_by_external_id, 1}, [tenant.external_id]}, {:cached, tenant})
    jwt = Generators.generate_jwt_token(tenant)
    {:ok, socket} = connect(UserSocket, %{}, conn_opts(tenant, jwt))
    
    {:ok, room_id} = Realtime.Music.SessionManager.create_room("teacher-1", tenant.external_id, bpm: 120)
    {:ok, _, socket} = subscribe_and_join(socket, "music_room:#{room_id}", %{"student_id" => "student-1"})
    
    {:ok, socket: socket, room_id: room_id}
  end
  
  test "play_note includes velocity in broadcast", %{socket: socket} do
    push(socket, "play_note", %{"midi" => 60, "velocity" => 100})
    
    assert_broadcast "student_note", %{
      midi: 60,
      velocity: 100,
      student_id: "student-1"
    }
  end
  
  test "play_note defaults to velocity 64 if not provided", %{socket: socket} do
    push(socket, "play_note", %{"midi" => 60})
    
    assert_broadcast "student_note", %{
      midi: 60,
      velocity: 64,  # Default
      student_id: "student-1"
    }
  end
  
  test "velocity is clamped to valid range (0-127)", %{socket: socket} do
    push(socket, "play_note", %{"midi" => 60, "velocity" => 200})
    
    assert_broadcast "student_note", %{
      midi: 60,
      velocity: 127,  # Clamped
      student_id: "student-1"
    }
    
    push(socket, "play_note", %{"midi" => 60, "velocity" => -10})
    
    assert_broadcast "student_note", %{
      midi: 60,
      velocity: 0,  # Clamped
      student_id: "student-1"
    }
  end
end
```

---

### Subphase 2.2: Game State Management

**File: `test/extensions/music/session_manager_game_state_test.exs`**

```elixir
defmodule Realtime.Music.SessionManagerGameStateTest do
  use ExUnit.Case
  
  setup do
    tenant_id = "test-tenant"
    {:ok, room_id} = Realtime.Music.SessionManager.create_room("teacher-1", tenant_id, bpm: 120)
    {:ok, tenant_id: tenant_id, room_id: room_id}
  end
  
  test "can set game type", %{room_id: room_id, tenant_id: tenant_id} do
    :ok = Realtime.Music.SessionManager.set_game_type(room_id, tenant_id, :melody_builder)
    
    {:ok, state} = Realtime.Music.SessionManager.get_game_state(room_id, tenant_id)
    assert state.game_type == :melody_builder
  end
  
  test "can update game state", %{room_id: room_id, tenant_id: tenant_id} do
    :ok = Realtime.Music.SessionManager.set_game_type(room_id, tenant_id, :melody_builder)
    :ok = Realtime.Music.SessionManager.update_game_state(room_id, tenant_id, %{
      melody_sequence: [%{midi: 60, velocity: 80}],
      melody_state: :building
    })
    
    {:ok, state} = Realtime.Music.SessionManager.get_game_state(room_id, tenant_id)
    assert state.game_state.melody_sequence == [%{midi: 60, velocity: 80}]
    assert state.game_state.melody_state == :building
  end
  
  test "game state is merged, not replaced", %{room_id: room_id, tenant_id: tenant_id} do
    :ok = Realtime.Music.SessionManager.set_game_type(room_id, tenant_id, :melody_builder)
    :ok = Realtime.Music.SessionManager.update_game_state(room_id, tenant_id, %{melody_sequence: []})
    :ok = Realtime.Music.SessionManager.update_game_state(room_id, tenant_id, %{melody_state: :building})
    
    {:ok, state} = Realtime.Music.SessionManager.get_game_state(room_id, tenant_id)
    assert state.game_state.melody_sequence == []
    assert state.game_state.melody_state == :building
  end
  
  test "returns error for invalid game type", %{room_id: room_id, tenant_id: tenant_id} do
    assert {:error, :invalid_game_type} = 
      Realtime.Music.SessionManager.set_game_type(room_id, tenant_id, :invalid_game)
  end
end
```

---

### Subphase 2.3: Pattern Storage Module

**File: `test/extensions/music/pattern_test.exs`**

```elixir
defmodule Realtime.Music.PatternTest do
  use ExUnit.Case
  
  test "can create pattern" do
    notes = [
      %{midi: 60, duration: 500, velocity: 80},
      %{midi: 64, duration: 500, velocity: 80},
      %{midi: 67, duration: 500, velocity: 80}
    ]
    
    pattern = Realtime.Music.Pattern.create("Test Pattern", notes)
    
    assert pattern.name == "Test Pattern"
    assert length(pattern.notes) == 3
    assert pattern.notes[0].midi == 60
    assert pattern.notes[0].timestamp == 0
    assert pattern.notes[1].timestamp == 500
    assert pattern.notes[2].timestamp == 1000
  end
  
  test "validates pattern" do
    valid_notes = [%{midi: 60, duration: 500, velocity: 80}]
    pattern = Realtime.Music.Pattern.create("Valid", valid_notes)
    
    assert :ok = Realtime.Music.Pattern.validate(pattern)
  end
  
  test "returns error for invalid pattern" do
    invalid_notes = [%{midi: -10, duration: 500}]  # Invalid MIDI
    pattern = Realtime.Music.Pattern.create("Invalid", invalid_notes)
    
    assert {:error, :invalid_notes} = Realtime.Music.Pattern.validate(pattern)
  end
  
  test "calculates pattern duration" do
    notes = [
      %{midi: 60, duration: 500},
      %{midi: 64, duration: 300},
      %{midi: 67, duration: 200}
    ]
    
    pattern = Realtime.Music.Pattern.create("Test", notes)
    assert Realtime.Music.Pattern.duration(pattern) == 1000  # 500 + 300 + 200
  end
  
  test "schedules playback correctly" do
    notes = [%{midi: 60, duration: 500, velocity: 80}]
    pattern = Realtime.Music.Pattern.create("Test", notes)
    
    start_time = 1000
    scheduled = Realtime.Music.Pattern.schedule_playback(pattern, start_time)
    
    assert length(scheduled) == 1
    assert scheduled[0].timestamp == 1000
    assert scheduled[0].midi == 60
  end
end
```

---

## Phase 3: Turn Management

### Subphase 3.1: TurnManager Module

**File: `test/extensions/music/turn_manager_test.exs`**

```elixir
defmodule Realtime.Music.TurnManagerTest do
  use ExUnit.Case
  
  test "can start turn rotation" do
    student_ids = ["student-1", "student-2", "student-3"]
    turn_manager = Realtime.Music.TurnManager.start_turn_rotation(student_ids, 30)
    
    assert turn_manager.current_turn == "student-1"
    assert turn_manager.queue == ["student-2", "student-3"]
    assert turn_manager.turn_duration_seconds == 30
    assert turn_manager.turn_state == :waiting
  end
  
  test "can start current turn" do
    turn_manager = Realtime.Music.TurnManager.start_turn_rotation(["student-1"], 30)
    turn_manager = Realtime.Music.TurnManager.start_turn(turn_manager)
    
    assert turn_manager.turn_state == :active
    assert not is_nil(turn_manager.turn_start_time)
  end
  
  test "can advance to next turn" do
    turn_manager = Realtime.Music.TurnManager.start_turn_rotation(["student-1", "student-2"], 30)
    turn_manager = Realtime.Music.TurnManager.next_turn(turn_manager)
    
    assert turn_manager.current_turn == "student-2"
    assert turn_manager.queue == ["student-1"]
  end
  
  test "can check if student can act" do
    turn_manager = Realtime.Music.TurnManager.start_turn_rotation(["student-1"], 30)
    turn_manager = Realtime.Music.TurnManager.start_turn(turn_manager)
    
    assert Realtime.Music.TurnManager.can_act?(turn_manager, "student-1")
    refute Realtime.Music.TurnManager.can_act?(turn_manager, "student-2")
  end
  
  test "calculates time remaining" do
    turn_manager = Realtime.Music.TurnManager.start_turn_rotation(["student-1"], 30)
    turn_manager = Realtime.Music.TurnManager.start_turn(turn_manager)
    
    remaining = Realtime.Music.TurnManager.time_remaining(turn_manager)
    assert remaining <= 30
    assert remaining >= 29  # Allow 1 second for test execution
  end
  
  test "can serialize and deserialize" do
    turn_manager = Realtime.Music.TurnManager.start_turn_rotation(["student-1", "student-2"], 30)
    turn_manager = Realtime.Music.TurnManager.start_turn(turn_manager)
    
    map = Realtime.Music.TurnManager.to_map(turn_manager)
    restored = Realtime.Music.TurnManager.from_map(map)
    
    assert restored.current_turn == turn_manager.current_turn
    assert restored.queue == turn_manager.queue
    assert restored.turn_state == turn_manager.turn_state
  end
end
```

---

## Phase 4: Pattern Matching

### Subphase 4.1: PatternMatcher Module

**File: `test/extensions/music/pattern_matcher_test.exs`**

```elixir
defmodule Realtime.Music.PatternMatcherTest do
  use ExUnit.Case
  
  test "matches identical patterns" do
    call = [%{midi: 60, timestamp: 0, duration: 500}]
    response = [%{midi: 60, timestamp: 0, duration: 500}]
    
    assert Realtime.Music.PatternMatcher.match?(call, response)
    assert Realtime.Music.PatternMatcher.accuracy(call, response) >= 90.0
  end
  
  test "handles timing tolerance" do
    call = [%{midi: 60, timestamp: 0, duration: 500}]
    response = [%{midi: 60, timestamp: 150, duration: 500}]  # 150ms off (within 200ms tolerance)
    
    assert Realtime.Music.PatternMatcher.match?(call, response, timing_tolerance_ms: 200)
  end
  
  test "handles pitch tolerance" do
    call = [%{midi: 60, timestamp: 0, duration: 500}]
    response = [%{midi: 61, timestamp: 0, duration: 500}]  # 1 semitone off
    
    assert Realtime.Music.PatternMatcher.match?(call, response, pitch_tolerance_semitones: 1)
  end
  
  test "returns low accuracy for very different patterns" do
    call = [%{midi: 60, timestamp: 0, duration: 500}]
    response = [%{midi: 72, timestamp: 1000, duration: 200}]  # Very different
    
    accuracy = Realtime.Music.PatternMatcher.accuracy(call, response)
    assert accuracy < 50.0
  end
  
  test "handles empty patterns" do
    call = []
    response = []
    
    # Should not crash
    accuracy = Realtime.Music.PatternMatcher.accuracy(call, response)
    assert is_float(accuracy)
  end
  
  test "handles length mismatch" do
    call = [%{midi: 60, timestamp: 0, duration: 500}]
    response = [
      %{midi: 60, timestamp: 0, duration: 500},
      %{midi: 64, timestamp: 500, duration: 500}
    ]
    
    # Response is longer - should apply length penalty
    accuracy = Realtime.Music.PatternMatcher.accuracy(call, response)
    assert accuracy < 100.0
  end
  
  test "provides detailed feedback" do
    call = [%{midi: 60, timestamp: 0, duration: 500}]
    response = [%{midi: 60, timestamp: 100, duration: 500}]
    
    feedback = Realtime.Music.PatternMatcher.feedback(call, response)
    
    assert Map.has_key?(feedback, :match)
    assert Map.has_key?(feedback, :accuracy)
    assert Map.has_key?(feedback, :notes_matched)
    assert feedback.call_length == 1
    assert feedback.response_length == 1
  end
end
```

---

## Phase 5: Game-Specific Features

### Subphase 5.1: Rhythm Circle

**File: `test/realtime_web/channels/music_room_channel_rhythm_test.exs`**

```elixir
defmodule RealtimeWeb.MusicRoomChannelRhythmTest do
  use RealtimeWeb.ChannelCase, async: true
  
  setup do
    tenant = Containers.checkout_tenant(run_migrations: true)
    Cachex.put!(Realtime.Tenants.Cache, {{:get_tenant_by_external_id, 1}, [tenant.external_id]}, {:cached, tenant})
    
    {:ok, room_id} = Realtime.Music.SessionManager.create_room("teacher-1", tenant.external_id, bpm: 120)
    :ok = Realtime.Music.SessionManager.set_game_type(room_id, tenant.external_id, :rhythm_circle)
    
    teacher_jwt = Generators.generate_jwt_token(tenant, %{"role" => "teacher"})
    {:ok, teacher_socket} = connect(UserSocket, %{}, conn_opts(tenant, teacher_jwt))
    {:ok, _, teacher_socket} = subscribe_and_join(teacher_socket, "music_room:#{room_id}", %{"student_id" => "teacher-1"})
    
    {:ok, teacher_socket: teacher_socket, room_id: room_id, tenant: tenant}
  end
  
  test "teacher can assign pattern to student", %{teacher_socket: teacher_socket} do
    pattern = [%{midi: 60, duration: 500}, %{midi: 60, duration: 500}]
    push(teacher_socket, "assign_pattern", %{"student_id" => "student-1", "pattern" => pattern})
    
    assert_reply :ok
    assert_broadcast "pattern_assigned", %{student_id: "student-1", pattern: ^pattern}
  end
  
  test "student cannot assign pattern", %{tenant: tenant, room_id: room_id} do
    student_jwt = Generators.generate_jwt_token(tenant, %{"role" => "student"})
    {:ok, student_socket} = connect(UserSocket, %{}, conn_opts(tenant, student_jwt))
    {:ok, _, student_socket} = subscribe_and_join(student_socket, "music_room:#{room_id}", %{"student_id" => "student-1"})
    
    push(student_socket, "assign_pattern", %{"student_id" => "student-2", "pattern" => []})
    assert_reply {:error, %{reason: "unauthorized"}}
  end
end
```

---

### Subphase 5.2: Melody Builder

**File: `test/realtime_web/channels/music_room_channel_melody_test.exs`**

```elixir
defmodule RealtimeWeb.MusicRoomChannelMelodyTest do
  use RealtimeWeb.ChannelCase, async: true
  
  setup do
    tenant = Containers.checkout_tenant(run_migrations: true)
    Cachex.put!(Realtime.Tenants.Cache, {{:get_tenant_by_external_id, 1}, [tenant.external_id]}, {:cached, tenant})
    
    {:ok, room_id} = Realtime.Music.SessionManager.create_room("teacher-1", tenant.external_id, bpm: 120)
    :ok = Realtime.Music.SessionManager.set_game_type(room_id, tenant.external_id, :melody_builder)
    :ok = Realtime.Music.SessionManager.join_room(room_id, tenant.external_id, "student-1")
    :ok = Realtime.Music.SessionManager.join_room(room_id, tenant.external_id, "student-2")
    
    teacher_jwt = Generators.generate_jwt_token(tenant, %{"role" => "teacher"})
    {:ok, teacher_socket} = connect(UserSocket, %{}, conn_opts(tenant, teacher_jwt))
    {:ok, _, teacher_socket} = subscribe_and_join(teacher_socket, "music_room:#{room_id}", %{"student_id" => "teacher-1"})
    
    student1_jwt = Generators.generate_jwt_token(tenant, %{"role" => "student"})
    {:ok, student1_socket} = connect(UserSocket, %{}, conn_opts(tenant, student1_jwt))
    {:ok, _, student1_socket} = subscribe_and_join(student1_socket, "music_room:#{room_id}", %{"student_id" => "student-1"})
    
    {:ok, teacher_socket: teacher_socket, student1_socket: student1_socket, room_id: room_id}
  end
  
  test "teacher can start melody building", %{teacher_socket: teacher_socket} do
    push(teacher_socket, "start_melody", %{})
    assert_reply :ok
    assert_broadcast "melody_started", %{}
  end
  
  test "student can add note when it's their turn", %{student1_socket: student1_socket} do
    # Start melody (via SessionManager directly for test)
    # Then add note
    push(student1_socket, "add_note", %{"midi" => 60, "velocity" => 80})
    
    assert_reply :ok
    assert_broadcast "note_added", %{note: %{midi: 60, velocity: 80}}
    assert_broadcast "turn_advanced", %{}
  end
  
  test "student cannot add note when it's not their turn", %{tenant: tenant, room_id: room_id} do
    # Setup: student-1's turn, but student-2 tries to add note
    student2_jwt = Generators.generate_jwt_token(tenant, %{"role" => "student"})
    {:ok, student2_socket} = connect(UserSocket, %{}, conn_opts(tenant, student2_jwt))
    {:ok, _, student2_socket} = subscribe_and_join(student2_socket, "music_room:#{room_id}", %{"student_id" => "student-2"})
    
    push(student2_socket, "add_note", %{"midi" => 60, "velocity" => 80})
    assert_reply {:error, %{reason: "not_your_turn"}}
  end
end
```

---

## Phase 6: Database Schema & Persistence

### Subphase 6.1: Music Patterns Table

**File: `test/extensions/music/schemas/music_pattern_test.exs`**

```elixir
defmodule Realtime.Music.Schemas.MusicPatternTest do
  use Realtime.DataCase
  
  alias Realtime.Music.Schemas.MusicPattern
  
  test "can create and save pattern" do
    pattern_data = %{
      notes: [%{midi: 60, duration: 500, velocity: 80}],
      time_signature: "4/4",
      tempo: 120
    }
    
    changeset = MusicPattern.changeset(%MusicPattern{}, %{
      room_id: "MUSIC-123",
      tenant_id: "test-tenant",
      pattern_type: "melody",
      pattern_data: pattern_data,
      name: "Test Pattern",
      created_by: "teacher-1"
    })
    
    assert changeset.valid?
    assert {:ok, pattern} = Repo.insert(changeset)
    assert pattern.tenant_id == "test-tenant"
    assert pattern.pattern_type == "melody"
  end
  
  test "validates required fields" do
    changeset = MusicPattern.changeset(%MusicPattern{}, %{})
    refute changeset.valid?
    assert %{tenant_id: ["can't be blank"]} = errors_on(changeset)
  end
  
  test "validates pattern_type inclusion" do
    changeset = MusicPattern.changeset(%MusicPattern{}, %{
      tenant_id: "test-tenant",
      pattern_type: "invalid",
      pattern_data: %{}
    })
    refute changeset.valid?
  end
end
```

---

### Subphase 6.2: Game Sessions Table

**File: `test/extensions/music/schemas/game_session_test.exs`**

```elixir
defmodule Realtime.Music.Schemas.GameSessionTest do
  use Realtime.DataCase
  
  alias Realtime.Music.Schemas.GameSession
  
  test "can save game session" do
    game_state = %{
      melody_sequence: [%{midi: 60, velocity: 80}],
      melody_state: :building
    }
    
    changeset = GameSession.changeset(%GameSession{}, %{
      room_id: "MUSIC-123",
      tenant_id: "test-tenant",
      game_type: "melody_builder",
      game_state: game_state,
      started_at: DateTime.utc_now()
    })
    
    assert changeset.valid?
    assert {:ok, session} = Repo.insert(changeset)
    assert session.game_type == "melody_builder"
    assert session.game_state.melody_sequence == [%{midi: 60, velocity: 80}]
  end
  
  test "can load game sessions for room" do
    # Create multiple sessions
    for i <- 1..3 do
      changeset = GameSession.changeset(%GameSession{}, %{
        room_id: "MUSIC-123",
        tenant_id: "test-tenant",
        game_type: "melody_builder",
        game_state: %{session: i},
        started_at: DateTime.utc_now()
      })
      Repo.insert!(changeset)
    end
    
    sessions = Realtime.Music.SessionManager.get_game_sessions("MUSIC-123", "test-tenant")
    assert length(sessions) == 3
  end
end
```

---

## Phase 7: Integration & Polish

### Subphase 7.1: Error Handling

**File: `test/realtime_web/channels/music_room_channel_error_test.exs`**

```elixir
defmodule RealtimeWeb.MusicRoomChannelErrorTest do
  use RealtimeWeb.ChannelCase, async: true
  
  setup do
    tenant = Containers.checkout_tenant(run_migrations: true)
    Cachex.put!(Realtime.Tenants.Cache, {{:get_tenant_by_external_id, 1}, [tenant.external_id]}, {:cached, tenant})
    
    {:ok, room_id} = Realtime.Music.SessionManager.create_room("teacher-1", tenant.external_id, bpm: 120)
    
    jwt = Generators.generate_jwt_token(tenant)
    {:ok, socket} = connect(UserSocket, %{}, conn_opts(tenant, jwt))
    {:ok, _, socket} = subscribe_and_join(socket, "music_room:#{room_id}", %{"student_id" => "student-1"})
    
    {:ok, socket: socket}
  end
  
  test "returns error when game is not active", %{socket: socket} do
    # Try to add note when no game is active
    push(socket, "add_note", %{"midi" => 60, "velocity" => 80})
    assert_reply {:error, %{reason: "no_game_active"}}
  end
  
  test "returns error for wrong game type", %{tenant: tenant, room_id: room_id} do
    # Set rhythm_circle game
    :ok = Realtime.Music.SessionManager.set_game_type(room_id, tenant.external_id, :rhythm_circle)
    
    jwt = Generators.generate_jwt_token(tenant)
    {:ok, socket} = connect(UserSocket, %{}, conn_opts(tenant, jwt))
    {:ok, _, socket} = subscribe_and_join(socket, "music_room:#{room_id}", %{"student_id" => "student-1"})
    
    # Try melody_builder action
    push(socket, "add_note", %{"midi" => 60, "velocity" => 80})
    assert_reply {:error, %{reason: "wrong_game_type"}}
  end
end
```

---

## Running Tests

### Run All Tests
```bash
mix test
```

### Run Tests for Specific Phase
```bash
# Phase 1
mix test test/realtime_web/channels/music_room_channel_auth_test.exs
mix test test/extensions/music/tempo_server_timing_test.exs

# Phase 2
mix test test/extensions/music/session_manager_game_state_test.exs
mix test test/extensions/music/pattern_test.exs

# Phase 3
mix test test/extensions/music/turn_manager_test.exs

# Phase 4
mix test test/extensions/music/pattern_matcher_test.exs

# Phase 5
mix test test/realtime_web/channels/music_room_channel_rhythm_test.exs
```

### Run with Coverage
```bash
mix test --cover
```

---

**Remember:** These are example tests. Adapt them to your implementation and add more tests as needed. Focus on testing critical paths, edge cases, and security concerns.
