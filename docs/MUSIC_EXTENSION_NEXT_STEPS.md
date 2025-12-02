# Music Extension - Next Steps Implementation Plan

## Overview

This document provides detailed implementation plans for optional enhancements to the music extension. These are post-MVP features that add security, visualization, and analytics capabilities.

**Note:** 
- High-value test examples are in `docs/IMPLEMENTATION_TESTS.md` - reference them as you implement.
- **⚠️ CRITICAL:** All implementations must maintain multi-tenant isolation using `tenant_id`.

---

## Next Step #1: Rate Limiting for Note Plays

### Goal
Prevent abuse and ensure fair participation in collaborative sessions. Without rate limiting, a single student could spam notes and overwhelm the system or disrupt the session.

### High-Level Overview
Rate limiting ensures that no single student can dominate a collaborative music session by playing notes too rapidly. This protects the learning experience for all participants and prevents system abuse. When a student tries to play notes faster than the allowed rate, their requests are rejected, encouraging thoughtful participation rather than rapid-fire spamming. This feature is essential for maintaining fair, educational, and enjoyable collaborative sessions where all students have equal opportunity to contribute.

### Substep 1.1: Create Rate Limiter Module

#### Tasks
- [ ] Create `lib/extensions/music/rate_limiter.ex`
- [ ] Implement sliding window or token bucket algorithm
- [ ] Support per-student, per-room rate limiting
- [ ] Make tenant-aware (rate limits can vary by tenant)

#### Files to Create

**File: `lib/extensions/music/rate_limiter.ex`**
```elixir
defmodule Realtime.Music.RateLimiter do
  @moduledoc """
  Rate limiter for music room note plays.
  
  Uses a sliding window algorithm to track note plays per student per room.
  """
  use GenServer

  ## Client API
  
  @doc """
  Check if a note play is allowed for a student in a room.
  Returns: {:ok, :allowed} or {:error, :rate_limit_exceeded}
  """
  def check_rate_limit(room_id, tenant_id, student_id, max_per_second \\ 10) do
    # Implementation: sliding window or token bucket
  end

  @doc """
  Record a note play event for rate limiting purposes.
  """
  def record_note_play(room_id, tenant_id, student_id) do
    # Implementation: store timestamp
  end
end
```

#### Technical Considerations
- Use ETS table or GenServer state to track timestamps
- Sliding window: keep last N timestamps, check if count exceeds limit
- Token bucket: refill tokens at fixed rate, consume on note play
- Consider using `:timer.send_interval/3` for token refills if using token bucket

#### Smoke Test
```elixir
# In IEx
iex> Realtime.Music.RateLimiter.check_rate_limit("MUSIC-1234", "tenant-1", "student-1", 10)
{:ok, :allowed}

# Play 11 notes rapidly
iex> Enum.each(1..11, fn _ -> 
  Realtime.Music.RateLimiter.record_note_play("MUSIC-1234", "tenant-1", "student-1")
  Realtime.Music.RateLimiter.check_rate_limit("MUSIC-1234", "tenant-1", "student-1", 10)
end)
# 11th should return {:error, :rate_limit_exceeded}
```

#### High-Value Tests
See `docs/IMPLEMENTATION_TESTS.md` → **Next Step #1**

---

### Substep 1.2: Integrate Rate Limiter into Channel

#### Tasks
- [ ] Update `MusicRoomChannel.handle_in("play_note")` to check rate limit
- [ ] Return error response when rate limit exceeded
- [ ] Optionally broadcast rate limit warning to student

#### Files to Modify

**File: `lib/realtime_web/channels/music_room_channel.ex`**
```elixir
def handle_in("play_note", %{"midi" => midi}, socket) do
  room_id = socket.assigns.room_id
  tenant_id = socket.assigns.tenant_id
  student_id = socket.assigns.student_id

  # Check rate limit
  case Realtime.Music.RateLimiter.check_rate_limit(room_id, tenant_id, student_id) do
    {:ok, :allowed} ->
      # Record note play
      Realtime.Music.RateLimiter.record_note_play(room_id, tenant_id, student_id)
      
      # Existing note play logic...
      SelTracker.log_participation(...)
      broadcast!(socket, "student_note", ...)
      {:noreply, socket}
    
    {:error, :rate_limit_exceeded} ->
      {:reply, {:error, %{reason: "rate_limit_exceeded"}}, socket}
  end
end
```

#### Technical Considerations
- Rate limit check should be fast (use ETS for O(1) lookups)
- Consider different limits for teachers vs students
- May want configurable limits per tenant (store in tenant settings)

#### Smoke Test
```elixir
# In IEx, connect to channel and rapidly send play_note events
# After 10 notes in 1 second, should receive rate_limit_exceeded error
```

#### High-Value Tests
- Test rate limit enforcement (10 notes/second)
- Test rate limit resets after time window
- Test different limits for teachers vs students
- Test tenant isolation (rate limits don't cross tenants)

---

### Substep 1.3: Add Configuration and Tests

#### Tasks
- [ ] Add rate limit configuration to extension config
- [ ] Write comprehensive tests for rate limiter
- [ ] Add integration tests in channel

#### Files to Modify

**File: `config/config.exs`**
```elixir
config :realtime, :extensions,
  music: %{
    supervisor: Realtime.Music.Supervisor,
    key: "music",
    rate_limit: %{
      notes_per_second: 10,
      teacher_notes_per_second: 50  # Higher limit for teachers
    }
  }
```

#### High-Value Tests
- Test sliding window algorithm correctness
- Test rate limit per student (student A can play while student B is limited)
- Test rate limit per room (same student in different rooms has separate limits)
- Test tenant isolation

---

## Next Step #2: Beat Assignment Visualization

### Goal
Help teachers and students see which beats are assigned to which students, making collaborative rhythm exercises more structured and educational.

### High-Level Overview
Beat assignment visualization makes it clear to everyone in the room which student is responsible for playing on which beat. This transforms unstructured free-for-all sessions into organized, educational exercises where teachers can assign specific beats to specific students, creating structured rhythm patterns. Students can see their assigned beats in real-time, helping them understand their role in the collaborative piece and reducing confusion about when they should play. This feature enhances the educational value of the music extension by enabling structured learning activities.

### Substep 2.1: Update SessionManager to Store Beat Assignments

#### Tasks
- [ ] Add `beat_assignments` field to room state in SessionManager
- [ ] Update `handle_call({:assign_beat, ...})` to store assignments
- [ ] Add `get_beat_assignments/2` function

#### Files to Modify

**File: `lib/extensions/music/session_manager.ex`**

Update room state structure:
```elixir
room = %{
  room_id: room_id,
  tenant_id: tenant_id,
  teacher_id: teacher_id,
  bpm: bpm,
  created_at: System.system_time(:second),
  students: [],
  beat_assignments: %{}  # %{beat_number => student_id}
}
```

Add function:
```elixir
@doc """
Get beat assignments for a room.
"""
def get_beat_assignments(room_id) do
  GenServer.call(__MODULE__, {:get_beat_assignments, room_id})
end
```

Update `handle_call` for `assign_beat`:
```elixir
def handle_call({:assign_beat, room_id, beat, student_id}, _from, state) do
  case Map.get(state, room_id) do
    nil ->
      {:reply, {:error, :not_found}, state}
    
    room ->
      beat_assignments = Map.put(room.beat_assignments, beat, student_id)
      updated_room = %{room | beat_assignments: beat_assignments}
      {:reply, :ok, Map.put(state, room_id, updated_room)}
  end
end
```

#### Technical Considerations
- Beat assignments should persist across channel joins/disconnects
- Consider supporting multiple students per beat (polyrhythms) - would need `%{beat => [student_id]}` instead
- May want to support beat ranges (assign beats 1-4 to student A)

#### Smoke Test
```elixir
# In IEx
iex> {:ok, room_id} = SessionManager.create_room("teacher-1", "tenant-1")
iex> SessionManager.assign_beat(room_id, 1, "student-1")
:ok
iex> {:ok, assignments} = SessionManager.get_beat_assignments(room_id)
{:ok, %{1 => "student-1"}}
```

#### High-Value Tests
- Test beat assignment storage and retrieval
- Test multiple beat assignments
- Test assignment updates (reassign beat to different student)
- Test tenant isolation

---

### Substep 2.2: Update Channel to Broadcast Assignments

#### Tasks
- [ ] Update `MusicRoomChannel.join/3` to send current assignments on join
- [ ] Update `handle_in("assign_beat")` to broadcast assignment updates
- [ ] Add `"beat_assignment_updated"` event

#### Files to Modify

**File: `lib/realtime_web/channels/music_room_channel.ex`**

In `join/3`, after successful join:
```elixir
# Get current beat assignments
{:ok, assignments} = SessionManager.get_beat_assignments(room_id)

# Send assignments to joining client
socket = push(socket, "beat_assignments", %{assignments: assignments})

{:ok, %{room_id: room_id, bpm: room.bpm, assignments: assignments}, socket}
```

Update `handle_in("assign_beat")`:
```elixir
def handle_in("assign_beat", %{"student_id" => student_id, "beat" => beat}, socket) do
  if is_teacher?(socket) do
    room_id = socket.assigns.room_id
    
    # Store assignment in SessionManager
    case SessionManager.assign_beat(room_id, beat, student_id) do
      :ok ->
        # Broadcast to all clients
        broadcast!(socket, "beat_assignment_updated", %{
          beat: beat,
          student_id: student_id,
          assignments: SessionManager.get_beat_assignments(room_id)
        })
        {:reply, :ok, socket}
      
      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  else
    {:reply, {:error, %{reason: "unauthorized"}}, socket}
  end
end
```

#### Technical Considerations
- Broadcast full assignments map so frontend can update visualization
- Consider sending incremental updates (just the changed beat) vs full map
- May want to support clearing assignments (assign beat to nil)

#### Smoke Test
```elixir
# In IEx, connect teacher and student to channel
# Teacher assigns beat 1 to student-1
# Both teacher and student should receive "beat_assignment_updated" event
```

#### High-Value Tests
- Test assignment broadcast on join
- Test assignment update broadcast
- Test multiple students receive updates
- Test tenant isolation

---

### Substep 2.3: Add Assignment Management Functions

#### Tasks
- [ ] Add `clear_beat_assignment/2` function
- [ ] Add `clear_all_assignments/1` function
- [ ] Add tests for assignment management

#### Files to Modify

**File: `lib/extensions/music/session_manager.ex`**

Add functions:
```elixir
@doc """
Clear a beat assignment.
"""
def clear_beat_assignment(room_id, beat) do
  GenServer.call(__MODULE__, {:clear_beat_assignment, room_id, beat})
end

@doc """
Clear all beat assignments for a room.
"""
def clear_all_assignments(room_id) do
  GenServer.call(__MODULE__, {:clear_all_assignments, room_id})
end
```

#### High-Value Tests
- Test clearing single assignment
- Test clearing all assignments
- Test clearing non-existent assignment (should not error)

---

## Next Step #3: Room Analytics Dashboard

### Goal
Provide teachers with insights into session participation, engagement levels, and student activity patterns. Useful for assessment and improving teaching strategies.

### High-Level Overview
The analytics dashboard gives teachers visibility into how their music sessions are going, both during and after the session. Teachers can see metrics like total notes played, participation rates per student, tempo changes, and session duration. This data helps teachers understand which students are actively engaged, identify students who may need more support, and assess the overall effectiveness of their teaching approach. The analytics enable data-driven improvements to music education sessions and help teachers tailor their instruction to better meet student needs.

### Substep 3.1: Create Analytics Module

#### Tasks
- [ ] Create `lib/extensions/music/analytics.ex`
- [ ] Implement query functions for participation statistics
- [ ] Calculate metrics: notes per student, notes per minute, tempo changes, session duration

#### Files to Create

**File: `lib/extensions/music/analytics.ex`**
```elixir
defmodule Realtime.Music.Analytics do
  @moduledoc """
  Analytics module for music room sessions.
  
  Provides functions to query and aggregate participation data.
  """
  import Ecto.Query
  alias Realtime.Music.Schemas.ParticipationEvent
  alias Realtime.Repo

  @doc """
  Get room statistics.
  
  Returns:
  - Total notes played
  - Notes per student
  - Notes per minute
  - Tempo change count
  - Session duration
  """
  def get_room_statistics(room_id, tenant_id) do
    # Query participation_events table
    # Calculate aggregations
  end

  @doc """
  Get participation breakdown per student.
  """
  def get_participation_breakdown(room_id, tenant_id) do
    # Group by student_id, count events
  end

  @doc """
  Get activity over time (for charts).
  """
  def get_activity_over_time(room_id, tenant_id, interval_minutes \\ 1) do
    # Group by time intervals, count events per interval
  end
end
```

#### Technical Considerations
- Use Ecto queries with `group_by`, `count`, `sum` aggregations
- Consider using database functions for time-based grouping
- May want to cache results for frequently accessed analytics
- Should filter by tenant_id for security

#### Smoke Test
```elixir
# In IEx, after some note plays
iex> Realtime.Music.Analytics.get_room_statistics("MUSIC-1234", "tenant-1")
%{
  total_notes: 150,
  notes_per_minute: 25,
  tempo_changes: 3,
  session_duration_minutes: 6
}
```

#### High-Value Tests
- Test statistics calculation accuracy
- Test participation breakdown per student
- Test activity over time grouping
- Test tenant isolation

---

### Substep 3.2: Create HTTP API Endpoints

#### Tasks
- [ ] Create `MusicAnalyticsController`
- [ ] Add routes for analytics endpoints
- [ ] Add authorization (teachers only)
- [ ] Return JSON responses

#### Files to Create

**File: `lib/realtime_web/controllers/music_analytics_controller.ex`**
```elixir
defmodule RealtimeWeb.MusicAnalyticsController do
  use RealtimeWeb, :controller

  alias Realtime.Music.Analytics

  action_fallback(RealtimeWeb.FallbackController)

  def show(conn, %{"room_id" => room_id}) do
    tenant_id = conn.assigns.tenant
    
    # Verify user is teacher (authorization check)
    # Get analytics
    statistics = Analytics.get_room_statistics(room_id, tenant_id)
    
    render(conn, "show.json", statistics: statistics)
  end

  def participation(conn, %{"room_id" => room_id}) do
    tenant_id = conn.assigns.tenant
    
    breakdown = Analytics.get_participation_breakdown(room_id, tenant_id)
    
    render(conn, "participation.json", breakdown: breakdown)
  end
end
```

#### Files to Modify

**File: `lib/realtime_web/router.ex`**
```elixir
scope "/api", RealtimeWeb do
  pipe_through([:open_cors, :tenant_api, :secure_tenant_api])

  get("/music/rooms/:room_id/analytics", MusicAnalyticsController, :show)
  get("/music/rooms/:room_id/participation", MusicAnalyticsController, :participation)
end
```

#### Technical Considerations
- Authorization: verify user is teacher for the room
- Should verify room belongs to tenant (tenant_id check)
- Consider rate limiting on analytics endpoints
- May want pagination for large datasets

#### Smoke Test
```bash
# Using curl
curl -H "Authorization: Bearer <teacher_jwt>" \
  http://localhost:4000/api/music/rooms/MUSIC-1234/analytics

# Expected: JSON with statistics
```

#### High-Value Tests
- Test analytics endpoint returns correct data
- Test authorization (students cannot access)
- Test tenant isolation
- Test error handling (room not found, etc.)

---

### Substep 3.3: Add Advanced Analytics Queries

#### Tasks
- [ ] Implement peak activity time calculation
- [ ] Add student engagement scoring
- [ ] Add tempo change analysis
- [ ] Add time-series data for charts

#### Files to Modify

**File: `lib/extensions/music/analytics.ex`**

Add functions:
```elixir
@doc """
Get peak activity times (when most notes were played).
"""
def get_peak_activity_times(room_id, tenant_id) do
  # Group by hour/minute, find peaks
end

@doc """
Calculate student engagement score.
"""
def calculate_engagement_score(room_id, tenant_id, student_id) do
  # Based on: participation consistency, response time, etc.
end

@doc """
Get tempo change history.
"""
def get_tempo_changes(room_id, tenant_id) do
  # Query tempo_changed events, return timeline
end
```

#### Technical Considerations
- Engagement scoring algorithm needs definition
- May want to pre-calculate scores vs on-demand
- Consider using database views for complex queries
- Time-series data should be optimized for charting libraries

#### High-Value Tests
- Test peak activity calculation
- Test engagement score calculation
- Test tempo change timeline
- Test performance with large datasets

---

### Substep 3.4: Add Caching and Performance Optimization

#### Tasks
- [ ] Add caching layer for frequently accessed analytics
- [ ] Optimize database queries (add indexes if needed)
- [ ] Consider background job for pre-calculating analytics

#### Technical Considerations
- Use Cachex or similar for caching
- Cache key: `{:analytics, tenant_id, room_id}`
- Cache TTL: 1-5 minutes (analytics don't need to be real-time)
- May want to invalidate cache on new participation events

#### High-Value Tests
- Test cache hit/miss behavior
- Test cache invalidation
- Test query performance with indexes

---

## Priority Recommendation

**If implementing one item:** Start with **Next Step #1 (Rate Limiting)** - it's a security/performance concern that should be addressed before production use.

**If implementing multiple:** Rate Limiting → Beat Assignment Visualization → Room Analytics (in that order of priority).

---

## Next Step #4: Expand SEL Data Collection

> **⚠️ NOTE: This step is NOT being implemented.** The detailed breakdown below is provided for future reference only.

### Goal
Capture richer data about student engagement, emotional responses, and learning outcomes to support research and improve educational effectiveness.

### High-Level Overview
Expanded SEL data collection captures detailed information about how students interact with the music system, including the timing of their note plays relative to beats, their rhythm accuracy, and patterns of collaboration with other students. This richer dataset enables deeper analysis of student learning outcomes, emotional engagement, and social interaction patterns. The data can be used for educational research, personalized learning recommendations, and understanding how collaborative music-making affects student development. This feature transforms the music extension from a simple collaboration tool into a research-grade platform for studying music education and social-emotional learning.

### Substep 4.1: Database Schema Updates

#### Tasks
- [ ] Create migration to add new fields to `participation_events` table
- [ ] Add `note_timing_ms` field (milliseconds from beat)
- [ ] Add `note_velocity` field (MIDI velocity if available)
- [ ] Add `collaboration_context` field (JSONB with related student IDs)
- [ ] Add indexes for new query patterns

#### Files to Create

**File: `priv/repo/migrations/YYYYMMDDHHMMSS_add_sel_metrics_to_participation_events.exs`**
```elixir
defmodule Realtime.Repo.Migrations.AddSelMetricsToParticipationEvents do
  use Ecto.Migration

  def change do
    alter table(:participation_events, prefix: "_realtime") do
      add(:note_timing_ms, :integer)  # milliseconds from beat (can be negative)
      add(:note_velocity, :integer)   # MIDI velocity (0-127)
      add(:collaboration_context, :map)  # JSONB: %{related_students: [student_id], sequence_position: integer}
    end

    create(index(:participation_events, [:note_timing_ms], prefix: "_realtime"))
    create(index(:participation_events, [:student_id, :note_timing_ms], prefix: "_realtime"))
  end
end
```

#### Technical Considerations
- `note_timing_ms` can be negative (note played before beat) or positive (after beat)
- `note_velocity` is optional (not all MIDI events include velocity)
- `collaboration_context` allows tracking note sequences and student interactions
- Consider data retention: detailed timing data may grow large over time

#### Smoke Test
```elixir
# After migration, verify schema
iex> Realtime.Repo.query!("SELECT column_name FROM information_schema.columns WHERE table_name = 'participation_events' AND table_schema = '_realtime'")
# Should include: note_timing_ms, note_velocity, collaboration_context
```

#### High-Value Tests
- Test migration applies successfully
- Test new fields can be inserted
- Test indexes improve query performance

---

### Substep 4.2: Update SelTracker with New Event Types

#### Tasks
- [ ] Add `log_note_timing/6` function to track note timing relative to beats
- [ ] Add `log_tempo_preference/4` function for tempo change requests
- [ ] Add `log_collaboration_pattern/5` function for note sequences
- [ ] Update existing `log_participation/5` to support new fields

#### Files to Modify

**File: `lib/extensions/music/sel_tracker.ex`**

Add functions:
```elixir
@doc """
Log note timing relative to beat.
"""
def log_note_timing(room_id, tenant_id, student_id, beat_number, timing_ms, midi) do
  attrs = %{
    room_id: room_id,
    tenant_id: tenant_id,
    student_id: student_id,
    event_type: "note_timing",
    event_data: %{midi: midi, beat_number: beat_number},
    note_timing_ms: timing_ms,
    timestamp: DateTime.utc_now()
  }

  %Realtime.Music.Schemas.ParticipationEvent{}
  |> Realtime.Music.Schemas.ParticipationEvent.changeset(attrs)
  |> Repo.insert()
  |> case do
    {:ok, _event} -> :ok
    {:error, changeset} ->
      Logger.error("Failed to log note timing: #{inspect(changeset.errors)}")
      :error
  end
end

@doc """
Log tempo preference (when student requests tempo change).
"""
def log_tempo_preference(room_id, tenant_id, student_id, requested_bpm) do
  log_participation(
    room_id, tenant_id, student_id,
    "tempo_preference",
    %{requested_bpm: requested_bpm}
  )
end

@doc """
Log collaboration pattern (note sequence between students).
"""
def log_collaboration_pattern(room_id, tenant_id, student_id, related_students, sequence_position) do
  attrs = %{
    room_id: room_id,
    tenant_id: tenant_id,
    student_id: student_id,
    event_type: "collaboration_pattern",
    event_data: %{sequence_position: sequence_position},
    collaboration_context: %{related_students: related_students},
    timestamp: DateTime.utc_now()
  }

  %Realtime.Music.Schemas.ParticipationEvent{}
  |> Realtime.Music.Schemas.ParticipationEvent.changeset(attrs)
  |> Repo.insert()
  |> case do
    {:ok, _event} -> :ok
    {:error, changeset} ->
      Logger.error("Failed to log collaboration pattern: #{inspect(changeset.errors)}")
      :error
  end
end
```

#### Technical Considerations
- Note timing calculation requires knowing when the beat occurred
- May need to track last beat timestamp in channel state
- Collaboration patterns require tracking recent note plays from other students
- Consider performance: logging every note with timing could be expensive

#### Smoke Test
```elixir
# In IEx
iex> SelTracker.log_note_timing("MUSIC-1234", "tenant-1", "student-1", 5, -50, 60)
:ok
# Note played 50ms before beat 5

iex> SelTracker.log_tempo_preference("MUSIC-1234", "tenant-1", "student-1", 140)
:ok
```

#### High-Value Tests
- Test note timing logging with positive and negative values
- Test tempo preference logging
- Test collaboration pattern logging
- Test error handling for invalid data

---

### Substep 4.3: Add Timing Calculation Logic to Channel

#### Tasks
- [ ] Track last beat timestamp in channel state
- [ ] Calculate note timing relative to beat when note is played
- [ ] Update `handle_in("play_note")` to log timing
- [ ] Track collaboration patterns (recent notes from other students)

#### Files to Modify

**File: `lib/realtime_web/channels/music_room_channel.ex`**

Update socket assigns to track timing:
```elixir
def join("music_room:" <> room_id, params, socket) do
  # ... existing join logic ...
  
  socket =
    socket
    |> assign(:room_id, room_id)
    |> assign(:tenant_id, tenant_id)
    |> assign(:student_id, student_id)
    |> assign(:role, params["role"] || "student")
    |> assign(:last_beat_timestamp, nil)  # Track when last beat occurred
    |> assign(:last_beat_number, nil)    # Track last beat number
    |> assign(:recent_notes, [])         # Track recent notes for collaboration

  # ... rest of join logic ...
end
```

Update `handle_info({:beat, beat_number}, socket)`:
```elixir
def handle_info({:beat, beat_number}, socket) do
  # Push beat to WebSocket client
  push(socket, "beat", %{beat: beat_number})
  
  # Update last beat tracking
  socket = socket
    |> assign(:last_beat_timestamp, System.system_time(:millisecond))
    |> assign(:last_beat_number, beat_number)
  
  {:noreply, socket}
end
```

Update `handle_in("play_note")`:
```elixir
def handle_in("play_note", %{"midi" => midi}, socket) do
  room_id = socket.assigns.room_id
  tenant_id = socket.assigns.tenant_id
  student_id = socket.assigns.student_id
  last_beat_ts = socket.assigns.last_beat_timestamp
  last_beat_num = socket.assigns.last_beat_number
  current_time = System.system_time(:millisecond)
  
  # Calculate timing relative to beat
  timing_ms = if last_beat_ts do
    current_time - last_beat_ts
  else
    nil  # No beat yet
  end
  
  # Log note timing if we have beat context
  if timing_ms && last_beat_num do
    SelTracker.log_note_timing(room_id, tenant_id, student_id, last_beat_num, timing_ms, midi)
  end
  
  # Track collaboration: check recent notes from other students
  recent_notes = socket.assigns.recent_notes
  related_students = recent_notes
    |> Enum.filter(fn note -> note.student_id != student_id end)
    |> Enum.map(& &1.student_id)
    |> Enum.uniq()
  
  if length(related_students) > 0 do
    sequence_position = length(recent_notes) + 1
    SelTracker.log_collaboration_pattern(room_id, tenant_id, student_id, related_students, sequence_position)
  end
  
  # Update recent notes (keep last 10)
  recent_notes = [%{student_id: student_id, midi: midi, timestamp: current_time} | recent_notes]
    |> Enum.take(10)
  
  socket = assign(socket, :recent_notes, recent_notes)
  
  # Existing note play logic...
  SelTracker.log_participation(...)
  broadcast!(socket, "student_note", ...)
  
  {:noreply, socket}
end
```

#### Technical Considerations
- Timing calculation assumes beats are on schedule (may have drift)
- Collaboration tracking uses a sliding window of recent notes
- Consider memory: tracking recent notes in channel state is fine for small windows
- May want to track note velocity if MIDI payload includes it

#### Smoke Test
```elixir
# In IEx, connect to channel, wait for beat, then play note
# Should log note timing relative to beat
# Should track collaboration if other students have played recently
```

#### High-Value Tests
- Test timing calculation accuracy
- Test collaboration pattern detection
- Test timing when no beat has occurred yet
- Test recent notes window management

---

### Substep 4.4: Create Analysis Functions

#### Tasks
- [ ] Create `Realtime.Music.SelAnalysis` module
- [ ] Implement engagement score calculation
- [ ] Implement rhythm accuracy calculation
- [ ] Implement improvement tracking over time

#### Files to Create

**File: `lib/extensions/music/sel_analysis.ex`**
```elixir
defmodule Realtime.Music.SelAnalysis do
  @moduledoc """
  Analysis functions for SEL data.
  
  Calculates engagement scores, rhythm accuracy, and learning outcomes.
  """
  import Ecto.Query
  alias Realtime.Music.Schemas.ParticipationEvent
  alias Realtime.Repo

  @doc """
  Calculate engagement score for a student.
  
  Based on:
  - Participation consistency (did student play throughout session)
  - Response time to beats (how quickly student responds)
  - Collaboration (does student play in response to others)
  """
  def calculate_engagement_score(room_id, tenant_id, student_id) do
    # Query participation events for student
    # Calculate metrics
    # Return score (0-100)
  end

  @doc """
  Calculate rhythm accuracy for a student.
  
  Compares note timing to assigned beats.
  Returns accuracy percentage.
  """
  def calculate_rhythm_accuracy(room_id, tenant_id, student_id, assigned_beats) do
    # Query note_timing events
    # Compare to assigned beats
    # Calculate accuracy (notes within X ms of beat)
  end

  @doc """
  Track improvement over time.
  
  Compares accuracy/engagement across multiple sessions.
  """
  def track_improvement(student_id, tenant_id, metric \\ :rhythm_accuracy) do
    # Query historical data
    # Calculate trend (improving, stable, declining)
  end
end
```

#### Technical Considerations
- Engagement scoring algorithm needs definition (weighting factors)
- Rhythm accuracy threshold: what's "close enough" to the beat? (e.g., ±100ms)
- Improvement tracking requires session identification (may need session_id field)
- Consider caching analysis results for frequently accessed data

#### Smoke Test
```elixir
# In IEx, after some note plays
iex> SelAnalysis.calculate_engagement_score("MUSIC-1234", "tenant-1", "student-1")
%{score: 85, metrics: %{consistency: 0.9, response_time: 120, collaboration: 0.7}}

iex> SelAnalysis.calculate_rhythm_accuracy("MUSIC-1234", "tenant-1", "student-1", [1, 2, 3, 4])
%{accuracy: 0.75, notes_on_beat: 3, total_notes: 4}
```

#### High-Value Tests
- Test engagement score calculation
- Test rhythm accuracy calculation
- Test improvement tracking
- Test edge cases (no data, single event, etc.)

---

### Substep 4.5: Update Schema and Add Batch Processing

#### Tasks
- [ ] Update `ParticipationEvent` schema to include new fields
- [ ] Add validation for new fields
- [ ] Create batch processing function for historical analysis
- [ ] Add data retention policy considerations

#### Files to Modify

**File: `lib/extensions/music/schemas/participation_event.ex`**

Update schema:
```elixir
schema "participation_events" do
  field(:room_id, :string)
  field(:tenant_id, :string)
  field(:student_id, :string)
  field(:event_type, :string)
  field(:event_data, :map)
  field(:timestamp, :utc_datetime)
  field(:note_timing_ms, :integer)  # New
  field(:note_velocity, :integer)   # New
  field(:collaboration_context, :map)  # New

  timestamps()
end

def changeset(event, attrs) do
  event
  |> cast(attrs, [
    :room_id, :tenant_id, :student_id, :event_type, :event_data, :timestamp,
    :note_timing_ms, :note_velocity, :collaboration_context  # New fields
  ])
  |> validate_required([:room_id, :tenant_id, :student_id, :event_type, :timestamp])
  |> validate_number(:note_timing_ms, greater_than: -1000, less_than: 1000)  # ±1 second
  |> validate_number(:note_velocity, greater_than_or_equal_to: 0, less_than_or_equal_to: 127)
end
```

#### Technical Considerations
- Data retention: detailed timing data can grow large
- Consider archiving old events (>90 days) to separate table
- Batch processing may need to run as background job
- Privacy: ensure SEL data is properly secured

#### High-Value Tests
- Test schema validation for new fields
- Test batch processing performance
- Test data retention policies

---

### Priority Recommendation

**If implementing one item:** Start with **Next Step #1 (Rate Limiting)** - it's a security/performance concern that should be addressed before production use.

**If implementing multiple:** Rate Limiting → Beat Assignment Visualization → Room Analytics → Expand SEL Data Collection (in that order of priority).

