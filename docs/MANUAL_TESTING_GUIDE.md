# Manual Testing Guide: Music Extension

**Last Updated:** December 3, 2024  
**Purpose:** Comprehensive manual testing guide for all music extension features

---

## 🚀 Quick Smoke Test (5 minutes)

**Goal:** Verify core functionality works end-to-end

### Option 1: Automated Test Script (Recommended)

Run the automated test suite which covers most manual tests:

```bash
./scripts/test_music_extension.sh
```

Or with mix directly:

```bash
mix run scripts/test_music_extension.exs
```

This script:
- ✅ Tests all core features automatically
- ✅ Recovers gracefully from failures
- ✅ Collects and reports all failure points
- ✅ Provides detailed success/failure statistics

See `scripts/README.md` for more details.

### Option 2: Manual Smoke Test

**Prerequisites**
- Server running: `mix phx.server`
- Database migrated: `mix ecto.migrate`
- IEx console open: `iex -S mix`

### Steps

1. **Create a room (IEx):**
   ```elixir
   tenant_id = "test-tenant"
   {:ok, room_id} = Realtime.Music.SessionManager.create_room("teacher-1", tenant_id, bpm: 120)
   # Should return: {:ok, "MUSIC-####"}
   ```

2. **Generate JWT tokens (IEx):**
   ```elixir
   # Get or create tenant
   tenant = Realtime.Api.get_tenant_by_external_id(tenant_id) || Generators.tenant_fixture(%{external_id: tenant_id})
   
   # Teacher token
   teacher_jwt = Generators.generate_jwt_token(tenant, %{
     role: "teacher",
     iat: System.system_time(:second),
     exp: System.system_time(:second) + 3600
   })
   
   # Student token
   student_jwt = Generators.generate_jwt_token(tenant, %{
     role: "student",
     iat: System.system_time(:second),
     exp: System.system_time(:second) + 3600
   })
   ```

3. **Connect teacher (Browser Console or WebSocket client):**
   ```javascript
   // Using Phoenix Socket client or Supabase client
   const teacherSocket = new Phoenix.Socket("ws://localhost:4000/socket", {
     params: {},
     transport: WebSocket
   })
   teacherSocket.connect()
   
   const teacherChannel = teacherSocket.channel(`music_room:${room_id}`, {
     student_id: "teacher-1"
   })
   
   teacherChannel.join()
     .receive("ok", resp => console.log("✅ Teacher joined:", resp))
     .receive("error", resp => console.error("❌ Join failed:", resp))
   ```

4. **Connect student (separate browser/client):**
   ```javascript
   const studentSocket = new Phoenix.Socket("ws://localhost:4000/socket", {
     params: {},
     transport: WebSocket
   })
   studentSocket.connect()
   
   const studentChannel = studentSocket.channel(`music_room:${room_id}`, {
     student_id: "student-1"
   })
   
   studentChannel.join()
     .receive("ok", resp => console.log("✅ Student joined:", resp))
   ```

5. **Test core features:**
   ```javascript
   // Teacher sets tempo
   teacherChannel.push("set_tempo", {bpm: 140})
   
   // Listen for beats (should arrive every ~428ms at 140 BPM)
   teacherChannel.on("beat", payload => console.log("🎵 Beat:", payload.beat))
   studentChannel.on("beat", payload => console.log("🎵 Beat:", payload.beat))
   
   // Student plays note
   studentChannel.push("play_note", {midi: 60, velocity: 80})
   
   // Both should receive the note
   teacherChannel.on("student_note", payload => console.log("🎹 Note:", payload))
   studentChannel.on("student_note", payload => console.log("🎹 Note:", payload))
   ```

**✅ Success Criteria:**
- Room created successfully
- Both teacher and student can join
- Beats broadcast every ~428ms (140 BPM)
- Notes broadcast to all participants
- No errors in server logs

**❌ If smoke test fails:** Check server logs, database connection, and JWT token generation.

---

## 📋 Table of Contents

1. [Setup & Prerequisites](#setup--prerequisites)
2. [Core Features Testing](#core-features-testing)
3. [Game Testing](#game-testing)
4. [Error Handling & Validation](#error-handling--validation)
5. [Database Persistence](#database-persistence)
6. [Performance & Edge Cases](#performance--edge-cases)
7. [Troubleshooting](#troubleshooting)

---

## Setup & Prerequisites

### Environment Setup

1. **Start database:**
   ```bash
   docker-compose up -d  # If using Docker
   # OR ensure PostgreSQL is running
   ```

2. **Run migrations:**
   ```bash
   mix ecto.migrate
   ```

3. **Start server:**
   ```bash
   mix phx.server
   # Server runs on http://localhost:4000
   ```

4. **Open IEx console (separate terminal):**
   ```bash
   iex -S mix
   ```

### Test Utilities Setup

**In IEx console, set up helper functions:**
```elixir
# Helper to get or create tenant
defmodule TestHelpers do
  def get_or_create_tenant(external_id \\ "test-tenant") do
    case Realtime.Api.get_tenant_by_external_id(external_id) do
      nil -> Generators.tenant_fixture(%{external_id: external_id})
      tenant -> tenant
    end
  end
  
  def generate_teacher_token(tenant) do
    Generators.generate_jwt_token(tenant, %{
      role: "teacher",
      iat: System.system_time(:second),
      exp: System.system_time(:second) + 3600
    })
  end
  
  def generate_student_token(tenant) do
    Generators.generate_jwt_token(tenant, %{
      role: "student",
      iat: System.system_time(:second),
      exp: System.system_time(:second) + 3600
    })
  end
end

# Usage:
tenant = TestHelpers.get_or_create_tenant("test-tenant")
teacher_jwt = TestHelpers.generate_teacher_token(tenant)
student_jwt = TestHelpers.generate_student_token(tenant)
```

### WebSocket Client Setup

**Option 1: Phoenix Socket (JavaScript)**
```javascript
// Install: npm install phoenix
import {Socket, Channel} from "phoenix"

const socket = new Socket("ws://localhost:4000/socket", {
  params: {},
  transport: WebSocket
})
socket.connect()
```

**Option 2: Supabase Client**
```javascript
import { createClient } from '@supabase/supabase-js'
const supabase = createClient('http://localhost:4000', jwt_token)
```

**Option 3: Raw WebSocket (for testing)**
```javascript
const ws = new WebSocket('ws://localhost:4000/socket/websocket?vsn=2.0.0')
```

---

## Core Features Testing

### 1. Room Creation & Management

#### Test: Create Room
**IEx:**
```elixir
tenant_id = "test-tenant"
{:ok, room_id} = Realtime.Music.SessionManager.create_room("teacher-1", tenant_id, bpm: 120)
# Expected: {:ok, "MUSIC-####"} where #### is a 4-digit number
```

**Verify:**
- ✅ Room ID format: `MUSIC-####`
- ✅ Room stored in SessionManager
- ✅ Default BPM is 120 (or specified value)

#### Test: Get Room Info
```elixir
{:ok, room} = Realtime.Music.SessionManager.get_room(room_id)
# Expected: %{id: room_id, teacher_id: "teacher-1", bpm: 120, students: [], ...}
```

**Verify:**
- ✅ Room data matches creation parameters
- ✅ `students` list is empty initially
- ✅ `created_at` timestamp is set

#### Test: Join Room
```elixir
:ok = Realtime.Music.SessionManager.join_room(room_id, tenant_id, "student-1")
{:ok, room} = Realtime.Music.SessionManager.get_room(room_id)
# Expected: room.students contains "student-1"
```

**Verify:**
- ✅ Student added to room's student list
- ✅ Multiple students can join
- ✅ Same student joining twice doesn't duplicate

#### Test: Room Cleanup
```elixir
# Create old room (simulate by setting old timestamp)
{:ok, old_room_id} = Realtime.Music.SessionManager.create_room("teacher-1", tenant_id, bpm: 120)

# Cleanup rooms older than 1 hour
{:ok, count} = Realtime.Music.SessionManager.cleanup_expired_rooms(tenant_id, 1)
# Expected: count >= 0 (number of cleaned rooms)
```

**Verify:**
- ✅ Old rooms are removed
- ✅ Active rooms are preserved
- ✅ Tempo servers for cleaned rooms are stopped

---

### 2. Tempo Server & Beat Broadcasting

#### Test: Start Tempo Server
**IEx:**
```elixir
{:ok, pid} = Realtime.Music.Supervisor.start_tempo_server(room_id, 120, tenant_id)
# Expected: {:ok, #PID<...>}
```

**Verify:**
- ✅ Process started successfully
- ✅ Process registered in Registry
- ✅ Can be looked up: `Registry.lookup(Realtime.Music.Registry, {:tempo_server, tenant_id, room_id})`

#### Test: Get/Set Tempo
```elixir
# Get tempo
{:ok, bpm} = Realtime.Music.TempoServer.get_tempo(room_id, tenant_id)
# Expected: {:ok, 120}

# Set tempo
:ok = Realtime.Music.TempoServer.set_tempo(room_id, tenant_id, 140)
{:ok, new_bpm} = Realtime.Music.TempoServer.get_tempo(room_id, tenant_id)
# Expected: {:ok, 140}
```

**Verify:**
- ✅ Tempo can be retrieved
- ✅ Tempo can be changed
- ✅ Invalid BPM (e.g., 0, 300) returns error

#### Test: Start/Stop Clock
```elixir
# Start clock
:ok = Realtime.Music.TempoServer.start_clock(room_id, tenant_id)

# Subscribe to beats in IEx
tenant_topic = Realtime.Tenants.tenant_topic(tenant_id, "music_room:#{room_id}", true)
Phoenix.PubSub.subscribe(Realtime.PubSub, tenant_topic)

# Wait for beat (should arrive within 1 second at 120 BPM = 500ms per beat)
receive do
  {:beat, beat_number} -> IO.puts("✅ Beat received: #{beat_number}")
after
  2000 -> IO.puts("❌ No beat received")
end

# Stop clock
:ok = Realtime.Music.TempoServer.stop_clock(room_id, tenant_id)

# Verify no more beats arrive
receive do
  {:beat, _} -> IO.puts("❌ Beat still arriving after stop")
after
  2000 -> IO.puts("✅ Clock stopped correctly")
end
```

**Verify:**
- ✅ Beats broadcast at correct interval (60,000ms / BPM)
- ✅ Beat numbers increment: 0, 1, 2, 3...
- ✅ Clock stops when requested
- ✅ No drift over time (beats stay in sync)

#### Test: Tempo Change via Channel
**WebSocket Client:**
```javascript
// Teacher joins and sets tempo
teacherChannel.push("set_tempo", {bpm: 140})
  .receive("ok", resp => console.log("✅ Tempo set:", resp))
  .receive("error", resp => console.error("❌ Error:", resp))

// Listen for tempo change broadcast
teacherChannel.on("tempo_changed", payload => {
  console.log("⏱️ Tempo changed to:", payload.bpm, "BPM")
  // Verify beat interval changes (should be ~428ms at 140 BPM)
})
```

**Verify:**
- ✅ Teacher receives `:ok` reply
- ✅ All clients receive `tempo_changed` broadcast
- ✅ Beat interval updates to match new tempo
- ✅ Students cannot set tempo (authorization check)

---

### 3. Note Broadcasting

#### Test: Play Note
**WebSocket Client:**
```javascript
// Student plays note
studentChannel.push("play_note", {
  midi: 60,
  velocity: 80  // Optional, 0-127
})
  .receive("ok", () => console.log("✅ Note sent"))
  .receive("error", resp => console.error("❌ Error:", resp))

// All clients (including sender) should receive
teacherChannel.on("student_note", payload => {
  console.log("🎹 Note received:", payload)
  // Expected: {midi: 60, student_id: "student-1", timestamp: ..., velocity: 80}
})

studentChannel.on("student_note", payload => {
  console.log("🎹 Note received:", payload)
})
```

**Verify:**
- ✅ Note broadcasts to all participants
- ✅ Payload includes: `midi`, `student_id`, `timestamp`, `velocity`
- ✅ Velocity defaults to 64 if not provided
- ✅ Velocity clamped to 0-127 range

#### Test: Rate Limiting
```javascript
// Try to play 20 notes rapidly (student limit: 10/sec)
for (let i = 0; i < 20; i++) {
  studentChannel.push("play_note", {midi: 60})
}

// Should receive rate limit error after ~10 notes
studentChannel.on("error", payload => {
  if (payload.reason === "rate_limit_exceeded") {
    console.log("✅ Rate limiting works")
  }
})
```

**Verify:**
- ✅ Students limited to 10 notes/second
- ✅ Teachers limited to 50 notes/second
- ✅ Error message: `{reason: "rate_limit_exceeded"}`
- ✅ Rate limit resets after 1 second

---

### 4. Teacher Controls

#### Test: Mute Student
```javascript
// Teacher mutes student
teacherChannel.push("mute_student", {student_id: "student-1"})
  .receive("ok", () => console.log("✅ Student muted"))

// Muted student tries to play note
studentChannel.push("play_note", {midi: 60})
  .receive("error", resp => {
    if (resp.reason === "student_muted") {
      console.log("✅ Mute enforcement works")
    }
  })

// Teacher unmutes
teacherChannel.push("unmute_student", {student_id: "student-1"})
  .receive("ok", () => console.log("✅ Student unmuted"))

// Student can now play
studentChannel.push("play_note", {midi: 60})
  .receive("ok", () => console.log("✅ Note played after unmute"))
```

**Verify:**
- ✅ Teacher can mute/unmute students
- ✅ Muted students cannot play notes
- ✅ Unmuted students can play again
- ✅ Students cannot mute others (authorization)

#### Test: Beat Assignment
```javascript
// Teacher assigns beat to student
teacherChannel.push("assign_beat", {
  student_id: "student-1",
  beat: 4
})
  .receive("ok", () => console.log("✅ Beat assigned"))

// Listen for beat assignment updates
teacherChannel.on("beat_assignment_updated", payload => {
  console.log("📋 Assignments:", payload)
  // Expected: {assignments: {"student-1": 4}}
})

// Student receives assignments on join
studentChannel.on("beat_assignments", payload => {
  console.log("📋 My assignments:", payload)
})

// Clear assignment
teacherChannel.push("clear_beat_assignment", {beat: 4})
  .receive("ok", () => console.log("✅ Assignment cleared"))
```

**Verify:**
- ✅ Teacher can assign beats to students
- ✅ Assignments broadcast to all clients
- ✅ Students receive assignments on join
- ✅ Assignments can be cleared individually or all at once

---

### 5. SEL Data Collection

#### Test: Participation Logging
**IEx:**
```elixir
# Participation is automatically logged when notes are played
# Check database after playing notes via channel

# Query participation events
import Ecto.Query
events = from e in Realtime.Music.Schemas.ParticipationEvent,
  where: e.room_id == ^room_id and e.tenant_id == ^tenant_id,
  order_by: [desc: e.timestamp]
|> Realtime.Repo.all()

# Expected: List of events with event_type: "note_played"
```

**Verify:**
- ✅ Events logged when notes are played
- ✅ Events include: `room_id`, `tenant_id`, `student_id`, `event_type`, `metadata`
- ✅ Timestamps are accurate

#### Test: Student Reflection
**HTTP API:**
```bash
curl -X POST http://localhost:4000/api/music/reflections \
  -H "Authorization: Bearer $STUDENT_JWT" \
  -H "Content-Type: application/json" \
  -d '{
    "room_id": "MUSIC-1234",
    "student_id": "student-1",
    "reflection_text": "I enjoyed playing with others",
    "reflection_type": "post_session",
    "metadata": {"mood": "happy"}
  }'
```

**IEx:**
```elixir
# Log reflection programmatically
:ok = Realtime.Music.SelTracker.log_reflection(
  room_id, tenant_id, "student-1",
  "I enjoyed playing with others",
  "post_session",
  %{mood: "happy"}
)

# Query reflections
reflections = from r in Realtime.Music.Schemas.StudentReflection,
  where: r.room_id == ^room_id and r.tenant_id == ^tenant_id,
  order_by: [desc: r.inserted_at]
|> Realtime.Repo.all()
```

**Verify:**
- ✅ Reflections saved to database
- ✅ HTTP endpoint accepts POST requests
- ✅ JWT authentication required
- ✅ Metadata stored as JSON

---

### 6. Analytics

#### Test: Room Statistics
**HTTP API:**
```bash
curl http://localhost:4000/api/music/rooms/MUSIC-1234/analytics \
  -H "Authorization: Bearer $TEACHER_JWT"
```

**IEx:**
```elixir
stats = Realtime.Music.Analytics.get_room_statistics(room_id, tenant_id)
# Expected: %{
#   total_notes: 42,
#   notes_per_minute: 10.5,
#   tempo_changes: 3,
#   session_duration_minutes: 4.0,
#   unique_students: 5
# }
```

**Verify:**
- ✅ Statistics calculated correctly
- ✅ `notes_per_minute` = total_notes / session_duration
- ✅ `unique_students` counts distinct students
- ✅ HTTP endpoint returns JSON

#### Test: Participation Breakdown
```elixir
breakdown = Realtime.Music.Analytics.get_participation_breakdown(room_id, tenant_id)
# Expected: %{"student-1" => 15, "student-2" => 8, ...}
```

**Verify:**
- ✅ Counts notes per student
- ✅ Students with no notes return 0
- ✅ Sorted by participation count

#### Test: Activity Over Time
```elixir
activity = Realtime.Music.Analytics.get_activity_over_time(room_id, tenant_id, interval_minutes: 1)
# Expected: [
#   %{interval_start: ~N[2024-12-03 10:00:00], event_count: 5, note_count: 10},
#   %{interval_start: ~N[2024-12-03 10:01:00], event_count: 3, note_count: 8},
#   ...
# ]
```

**Verify:**
- ✅ Data grouped by time intervals
- ✅ `event_count` includes all events (notes, tempo changes, etc.)
- ✅ `note_count` is subset of events
- ✅ Intervals are consecutive

---

## Game Testing

### Game 1: Rhythm Circle

#### Setup
```elixir
# Set game type
:ok = Realtime.Music.SessionManager.set_game_type(room_id, tenant_id, :rhythm_circle)
```

#### Test: Assign Pattern
**WebSocket:**
```javascript
// Teacher assigns pattern to student
teacherChannel.push("assign_pattern", {
  student_id: "student-1",
  pattern: [
    {midi: 60, duration: 500},
    {midi: 64, duration: 500}
  ]
})
  .receive("ok", () => console.log("✅ Pattern assigned"))

// Listen for assignment broadcast
teacherChannel.on("pattern_assigned", payload => {
  console.log("📋 Pattern assigned:", payload)
  // Expected: {student_id: "student-1", pattern: [...]}
})
```

**Verify:**
- ✅ Pattern assigned to student
- ✅ Broadcast sent to all clients
- ✅ Pattern stored in game state

#### Test: Start Pattern Playback
```javascript
// Teacher starts pattern playback
teacherChannel.push("pattern_start", {})
  .receive("ok", () => console.log("✅ Pattern playback started"))

// Listen for pattern beat events
teacherChannel.on("pattern_beat", payload => {
  console.log("🎵 Pattern beat:", payload.beat)
  // Expected: {beat: 0}, {beat: 1}, ... (one per note in pattern)
})
```

**Verify:**
- ✅ Pattern beats broadcast at correct intervals
- ✅ Beat numbers match pattern indices (0, 1, 2...)
- ✅ Beats synchronized with tempo

---

### Game 2: Melody Builder

#### Setup
```elixir
:ok = Realtime.Music.SessionManager.set_game_type(room_id, tenant_id, :melody_builder)

# Start turn rotation
student_ids = ["student-1", "student-2", "student-3"]
:ok = Realtime.Music.SessionManager.start_turn_rotation(room_id, tenant_id, student_ids, turn_duration_seconds: 30)
```

#### Test: Start Melody Building
```javascript
// Teacher starts melody
teacherChannel.push("start_melody", {})
  .receive("ok", () => console.log("✅ Melody building started"))

// Listen for turn updates
teacherChannel.on("turn_update", payload => {
  console.log("👤 Current turn:", payload.current_turn)
  // Expected: {student_id: "student-1", time_remaining: 30}
})
```

**Verify:**
- ✅ Turn rotation started
- ✅ First student's turn is active
- ✅ Turn updates broadcast to all clients

#### Test: Add Note (Turn-Based)
```javascript
// Student on their turn adds note
studentChannel.push("add_note", {
  midi: 60,
  velocity: 80
})
  .receive("ok", () => console.log("✅ Note added"))
  .receive("error", resp => {
    if (resp.reason === "not_your_turn") {
      console.log("✅ Turn enforcement works")
    }
  })

// Listen for melody updates
teacherChannel.on("melody_updated", payload => {
  console.log("🎵 Melody:", payload.melody_sequence)
  // Expected: [{midi: 60, velocity: 80}, ...]
})
```

**Verify:**
- ✅ Only student on their turn can add notes
- ✅ Other students receive error if they try
- ✅ Melody sequence updates and broadcasts
- ✅ Notes added in order

#### Test: Play Completed Melody
```javascript
// After all students add notes, teacher plays melody
teacherChannel.push("play_melody", {})
  .receive("ok", () => console.log("✅ Melody playback started"))

// Listen for melody playback
teacherChannel.on("melody_playing", payload => {
  console.log("🎵 Playing melody:", payload.melody_sequence)
})
```

**Verify:**
- ✅ Melody sequence broadcasts
- ✅ All notes in sequence
- ✅ Can be played multiple times

---

### Game 3: Dynamics Dance

#### Setup
```elixir
:ok = Realtime.Music.SessionManager.set_game_type(room_id, tenant_id, :dynamics_dance)
```

#### Test: Set Dynamic Pattern
```javascript
// Teacher sets dynamic pattern
teacherChannel.push("set_dynamic_pattern", {
  pattern: [
    {midi: 60, velocity: 40},  // Quiet
    {midi: 64, velocity: 100}   // Loud
  ]
})
  .receive("ok", () => console.log("✅ Dynamic pattern set"))
```

**Verify:**
- ✅ Pattern stored in game state
- ✅ Pattern broadcasts to all clients

#### Test: Set Dynamic Goal
```javascript
// Teacher sets goal (e.g., crescendo)
teacherChannel.push("set_dynamic_goal", {
  goal: "crescendo"  // or "diminuendo", "staccato", etc.
})
  .receive("ok", () => console.log("✅ Dynamic goal set"))
```

**Verify:**
- ✅ Goal stored in game state
- ✅ Goal broadcasts to all clients

#### Test: Volume Feedback
```javascript
// Student plays note with different volumes
studentChannel.push("play_note", {midi: 60, velocity: 30})  // Too quiet
  .receive("ok", () => {})

// Listen for volume feedback
studentChannel.on("volume_feedback", payload => {
  console.log("🔊 Feedback:", payload.feedback)
  // Expected: "too_quiet" | "too_loud" | "perfect"
})

studentChannel.push("play_note", {midi: 60, velocity: 100})  // Too loud
studentChannel.push("play_note", {midi: 60, velocity: 70})  // Perfect
```

**Verify:**
- ✅ Feedback provided based on goal/pattern
- ✅ Feedback broadcasts to student who played
- ✅ Feedback is accurate (matches goal)

---

### Game 4: Improvisation Jam

#### Setup
```elixir
:ok = Realtime.Music.SessionManager.set_game_type(room_id, tenant_id, :improvisation_jam)

# Start turn rotation
student_ids = ["student-1", "student-2", "student-3"]
:ok = Realtime.Music.SessionManager.start_turn_rotation(room_id, tenant_id, student_ids, turn_duration_seconds: 30)
```

#### Test: Start Improvisation
```javascript
// Teacher starts improvisation
teacherChannel.push("start_improvisation", {})
  .receive("ok", () => console.log("✅ Improvisation started"))
```

**Verify:**
- ✅ Game state updated
- ✅ Turn rotation active

#### Test: Request Solo
```javascript
// Student on their turn requests solo
studentChannel.push("request_solo", {})
  .receive("ok", () => console.log("✅ Solo requested"))
  .receive("error", resp => {
    if (resp.reason === "not_your_turn") {
      console.log("✅ Turn enforcement works")
    }
  })
```

**Verify:**
- ✅ Only student on their turn can request solo
- ✅ Solo request stored in game state

#### Test: Assign Solo
```javascript
// Teacher assigns solo to student
teacherChannel.push("assign_solo", {student_id: "student-1"})
  .receive("ok", () => console.log("✅ Solo assigned"))

// Listen for solo assignment
teacherChannel.on("solo_assigned", payload => {
  console.log("🎤 Solo assigned:", payload.student_id)
})

// Solo student can play notes (others cannot)
studentChannel.push("play_note", {midi: 60})
  .receive("ok", () => console.log("✅ Solo note played"))

// Other student tries to play (should fail or be muted)
otherStudentChannel.push("play_note", {midi: 60})
  .receive("error", resp => {
    if (resp.reason === "solo_active") {
      console.log("✅ Solo mode enforcement works")
    }
  })
```

**Verify:**
- ✅ Solo student can play notes
- ✅ Other students cannot play during solo
- ✅ Solo assignment broadcasts to all clients

#### Test: End Solo
```javascript
// Teacher ends solo
teacherChannel.push("end_solo", {})
  .receive("ok", () => console.log("✅ Solo ended"))

// All students can now play again
studentChannel.push("play_note", {midi: 60})
  .receive("ok", () => console.log("✅ Note played after solo"))
```

**Verify:**
- ✅ Solo mode deactivated
- ✅ All students can play again
- ✅ Turn rotation continues

---

### Game 5: Call and Response

#### Setup
```elixir
:ok = Realtime.Music.SessionManager.set_game_type(room_id, tenant_id, :call_and_response)
```

#### Test: Play Call Pattern
```javascript
// Teacher plays call pattern
teacherChannel.push("play_call", {
  pattern: [
    {midi: 60, timestamp: 0, duration: 500},
    {midi: 64, timestamp: 500, duration: 500}
  ]
})
  .receive("ok", () => console.log("✅ Call pattern played"))

// Listen for call playing
teacherChannel.on("call_playing", payload => {
  console.log("📢 Call pattern:", payload.pattern)
})
```

**Verify:**
- ✅ Call pattern stored in game state
- ✅ Pattern broadcasts to all clients
- ✅ Response recording state activated

#### Test: Record Response
```javascript
// Student records response
studentChannel.push("record_response", {
  response: [
    {midi: 60, timestamp: 0, duration: 500},
    {midi: 64, timestamp: 500, duration: 500}
  ]
})
  .receive("ok", () => console.log("✅ Response recorded"))
```

**Verify:**
- ✅ Response stored in game state
- ✅ Multiple students can record responses
- ✅ Responses associated with student_id

#### Test: Validate Response
```javascript
// Teacher validates student's response
teacherChannel.push("validate_response", {student_id: "student-1"})
  .receive("ok", feedback => {
    console.log("✅ Validation:", feedback)
    // Expected: {match: true/false, accuracy: 0-100, details: [...]}
  })

// Listen for feedback broadcast
teacherChannel.on("response_feedback", payload => {
  console.log("📊 Feedback:", payload)
  // Expected: {student_id: "student-1", feedback: {...}}
})
```

**Verify:**
- ✅ Pattern matching works correctly
- ✅ Accuracy score calculated (0-100%)
- ✅ Match detection uses tolerance settings
- ✅ Feedback broadcasts to all clients

#### Test: Pattern Matching Accuracy
**IEx:**
```elixir
# Test exact match
call_pattern = [%{midi: 60, timestamp: 0, duration: 500}]
response_pattern = [%{midi: 60, timestamp: 0, duration: 500}]

{:ok, feedback} = Realtime.Music.SessionManager.validate_response(room_id, tenant_id, "student-1")
# Expected: feedback.match == true, feedback.accuracy >= 90.0

# Test pitch mismatch
response_pattern2 = [%{midi: 62, timestamp: 0, duration: 500}]  # 2 semitones off
# Expected: feedback.match == false, feedback.accuracy < 90.0

# Test timing mismatch
response_pattern3 = [%{midi: 60, timestamp: 100, duration: 500}]  # 100ms late
# Expected: feedback.accuracy reduced based on timing tolerance
```

**Verify:**
- ✅ Exact matches return 100% accuracy
- ✅ Pitch differences reduce accuracy
- ✅ Timing differences reduce accuracy
- ✅ Tolerance settings affect matching

---

## Error Handling & Validation

### Test: Invalid Game Type
```javascript
// Try to use game event when wrong game is active
teacherChannel.push("assign_pattern", {student_id: "student-1", pattern: [...]})
  .receive("error", resp => {
    if (resp.reason === "wrong_game_type" || resp.reason === "no_game_active") {
      console.log("✅ Game type validation works")
    }
  })
```

**Verify:**
- ✅ Error when game type doesn't match
- ✅ Error when no game is active
- ✅ Error message is clear

### Test: Authorization Checks
```javascript
// Student tries teacher-only action
studentChannel.push("set_tempo", {bpm: 140})
  .receive("error", resp => {
    if (resp.reason === "unauthorized") {
      console.log("✅ Authorization check works")
    }
  })

// Student tries to mute another student
studentChannel.push("mute_student", {student_id: "student-2"})
  .receive("error", resp => {
    if (resp.reason === "unauthorized") {
      console.log("✅ Authorization check works")
    }
  })
```

**Verify:**
- ✅ Students cannot perform teacher actions
- ✅ Error message: `{reason: "unauthorized"}`
- ✅ Teacher actions work for teachers

### Test: Invalid Payloads
```javascript
// Missing required fields
teacherChannel.push("set_tempo", {})
  .receive("error", resp => {
    console.log("✅ Validation works:", resp)
  })

// Invalid BPM
teacherChannel.push("set_tempo", {bpm: 0})
  .receive("error", resp => {
    if (resp.reason === "invalid_bpm") {
      console.log("✅ BPM validation works")
    }
  })

// Invalid velocity
studentChannel.push("play_note", {midi: 60, velocity: 200})  // > 127
  .receive("ok", () => {
    // Should clamp to 127, not error
  })
```

**Verify:**
- ✅ Missing fields return error
- ✅ Invalid values return error or are clamped
- ✅ Error messages are descriptive

---

## Database Persistence

### Test: Save Game Session
**IEx:**
```elixir
# Set up active game
:ok = Realtime.Music.SessionManager.set_game_type(room_id, tenant_id, :melody_builder)
:ok = Realtime.Music.SessionManager.update_game_state(room_id, tenant_id, %{
  melody_sequence: [%{midi: 60, velocity: 80}]
})

# Save game session (async)
:ok = Realtime.Music.SessionManager.save_game_session(room_id, tenant_id)

# Wait for async save to complete
Process.sleep(200)

# Verify session saved
sessions = Realtime.Music.SessionManager.get_game_sessions(room_id, tenant_id)
# Expected: length(sessions) >= 1

session = hd(sessions)
# Expected: session.game_type == "melody_builder"
# Expected: session.game_state["melody_sequence"] == [%{"midi" => 60, "velocity" => 80}]
```

**Verify:**
- ✅ Session saved to database
- ✅ Game state serialized correctly
- ✅ Timestamps set (started_at, inserted_at)
- ✅ Tenant isolation (sessions from other tenants not visible)

### Test: Load Game Sessions
```elixir
# Get all sessions for room
sessions = Realtime.Music.SessionManager.get_game_sessions(room_id, tenant_id)

# Expected: List ordered by started_at descending
# Expected: Each session has: room_id, tenant_id, game_type, game_state, started_at
```

**Verify:**
- ✅ Sessions loaded correctly
- ✅ Ordered by most recent first
- ✅ Game state deserialized correctly
- ✅ Only sessions for this room/tenant

### Test: Pattern Storage
**IEx:**
```elixir
# Create pattern
pattern = Realtime.Music.Pattern.create("My Pattern", [
  %{midi: 60, duration: 500},
  %{midi: 64, duration: 500}
], time_signature: "4/4", tempo: 120)

# Save to database (via Ecto)
changeset = Realtime.Music.Schemas.MusicPattern.changeset(
  %Realtime.Music.Schemas.MusicPattern{},
  %{
    room_id: room_id,
    tenant_id: tenant_id,
    pattern_type: "rhythm",
    pattern_data: Realtime.Music.Pattern.to_map(pattern),
    name: "My Pattern",
    time_signature: "4/4",
    tempo: 120,
    created_by: "teacher-1"
  }
)

{:ok, saved_pattern} = Realtime.Repo.insert(changeset)

# Load pattern
pattern_from_db = Realtime.Music.Pattern.from_map(saved_pattern.pattern_data)
```

**Verify:**
- ✅ Pattern serialized to map
- ✅ Pattern deserialized from map
- ✅ All fields saved correctly
- ✅ Tenant isolation

---

## Performance & Edge Cases

### Test: Multiple Rooms
```elixir
# Create multiple rooms
{:ok, room1} = Realtime.Music.SessionManager.create_room("teacher-1", tenant_id, bpm: 120)
{:ok, room2} = Realtime.Music.SessionManager.create_room("teacher-2", tenant_id, bpm: 140)

# Each room should have independent tempo
{:ok, bpm1} = Realtime.Music.TempoServer.get_tempo(room1, tenant_id)
{:ok, bpm2} = Realtime.Music.TempoServer.get_tempo(room2, tenant_id)
# Expected: bpm1 == 120, bpm2 == 140
```

**Verify:**
- ✅ Rooms are isolated
- ✅ Tempo servers independent
- ✅ No cross-room interference

### Test: Many Students
```elixir
# Join 20+ students to same room
Enum.each(1..25, fn i ->
  :ok = Realtime.Music.SessionManager.join_room(room_id, tenant_id, "student-#{i}")
end)

{:ok, room} = Realtime.Music.SessionManager.get_room(room_id)
# Expected: length(room.students) == 25
```

**Verify:**
- ✅ All students can join
- ✅ Room state handles many students
- ✅ Performance acceptable (no slowdown)

### Test: Rapid Tempo Changes
```elixir
# Change tempo rapidly
Enum.each([120, 140, 100, 160, 80], fn bpm ->
  :ok = Realtime.Music.TempoServer.set_tempo(room_id, tenant_id, bpm)
  Process.sleep(100)
end)

# Verify final tempo
{:ok, final_bpm} = Realtime.Music.TempoServer.get_tempo(room_id, tenant_id)
# Expected: final_bpm == 80
```

**Verify:**
- ✅ Tempo changes handled correctly
- ✅ No race conditions
- ✅ Final state is correct

### Test: Concurrent Note Plays
**WebSocket (multiple clients):**
```javascript
// 5 students play notes simultaneously
const students = [student1Channel, student2Channel, student3Channel, student4Channel, student5Channel]

students.forEach((channel, i) => {
  channel.push("play_note", {midi: 60 + i})
})

// All clients should receive all 5 notes
teacherChannel.on("student_note", payload => {
  console.log("Received note:", payload.midi)
})
```

**Verify:**
- ✅ All notes broadcast correctly
- ✅ No notes lost
- ✅ Ordering is reasonable (may not be exact due to network)

---

## Troubleshooting

### Common Issues

#### Issue: "Room not found"
**Symptoms:** Cannot join room
**Solutions:**
- Verify room exists: `Realtime.Music.SessionManager.get_room(room_id)`
- Check room_id format: `MUSIC-####`
- Ensure room created in same tenant

#### Issue: "Rate limit exceeded"
**Symptoms:** Notes rejected after rapid playing
**Solutions:**
- Wait 1 second for rate limit to reset
- Check rate limit config: 10/sec for students, 50/sec for teachers
- Verify rate limiter is working: `Realtime.Music.RateLimiter.check_rate_limit(...)`

#### Issue: No beats received
**Symptoms:** Tempo clock not broadcasting
**Solutions:**
- Verify tempo server started: `Registry.lookup(Realtime.Music.Registry, {:tempo_server, tenant_id, room_id})`
- Check clock is started: `TempoServer.start_clock(room_id, tenant_id)`
- Verify PubSub subscription: Check channel is subscribed to tenant topic
- Check server logs for errors

#### Issue: JWT token invalid
**Symptoms:** Cannot connect to WebSocket
**Solutions:**
- Verify token includes required claims: `role`, `iat`, `exp`
- Check token not expired: `exp > current_time`
- Verify JWT secret matches tenant: `tenant.jwt_secret`
- Regenerate token with correct claims

#### Issue: Database connection errors
**Symptoms:** Persistence operations fail
**Solutions:**
- Verify database running: `docker-compose ps` or `pg_isready`
- Check migrations: `mix ecto.migrate`
- Verify tenant has database connection configured
- Check `_realtime` schema exists

#### Issue: Game state not updating
**Symptoms:** Game events don't work
**Solutions:**
- Verify game type is set: `SessionManager.get_game_state(room_id, tenant_id)`
- Check game type matches event: Wrong game type returns error
- Verify game state structure matches expected format
- Check server logs for errors

### Debugging Commands

**IEx Helpers:**
```elixir
# Check room state
{:ok, room} = Realtime.Music.SessionManager.get_room(room_id)
IO.inspect(room, label: "Room State")

# Check game state
{:ok, game_state} = Realtime.Music.SessionManager.get_game_state(room_id, tenant_id)
IO.inspect(game_state, label: "Game State")

# Check tempo server
case Registry.lookup(Realtime.Music.Registry, {:tempo_server, tenant_id, room_id}) do
  [{pid, _}] -> IO.puts("✅ Tempo server running: #{inspect(pid)}")
  [] -> IO.puts("❌ Tempo server not found")
end

# Check rate limiter state
:sys.get_state(Realtime.Music.RateLimiter)

# List all rooms for tenant
# (Requires custom function or database query)
```

**Server Logs:**
```bash
# Watch server logs
tail -f log/dev.log

# Filter for music extension
tail -f log/dev.log | grep -i music

# Filter for errors
tail -f log/dev.log | grep -i error
```

**Database Queries:**
```sql
-- Check game sessions
SELECT * FROM _realtime.game_sessions 
WHERE room_id = 'MUSIC-1234' 
ORDER BY started_at DESC;

-- Check participation events
SELECT * FROM _realtime.participation_events 
WHERE room_id = 'MUSIC-1234' 
ORDER BY timestamp DESC 
LIMIT 10;

-- Check student reflections
SELECT * FROM _realtime.student_reflections 
WHERE room_id = 'MUSIC-1234' 
ORDER BY inserted_at DESC;
```

---

## Test Checklist

Use this checklist to ensure comprehensive testing:

### Core Features
- [ ] Room creation
- [ ] Room joining
- [ ] Room cleanup
- [ ] Tempo server start/stop
- [ ] Tempo get/set
- [ ] Beat broadcasting
- [ ] Note broadcasting
- [ ] Rate limiting
- [ ] Teacher controls (mute, beat assignment)
- [ ] SEL data collection
- [ ] Analytics endpoints

### Games
- [ ] Rhythm Circle: Pattern assignment, playback
- [ ] Melody Builder: Turn-based melody building
- [ ] Dynamics Dance: Volume feedback
- [ ] Improvisation Jam: Solo requests and assignment
- [ ] Call and Response: Pattern matching

### Error Handling
- [ ] Invalid game type errors
- [ ] Authorization checks
- [ ] Invalid payload validation
- [ ] Rate limit errors

### Database
- [ ] Game session persistence
- [ ] Pattern storage
- [ ] Participation event logging
- [ ] Student reflection storage

### Edge Cases
- [ ] Multiple rooms
- [ ] Many students (20+)
- [ ] Rapid tempo changes
- [ ] Concurrent note plays

---

**End of Manual Testing Guide**

*For automated tests, see `test/` directory.*  
*For implementation details, see `docs/MUSIC_EXTENSION_SUMMARY.md`.*

