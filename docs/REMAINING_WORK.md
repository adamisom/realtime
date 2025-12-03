# Remaining Work & Future Considerations

This document outlines the remaining work items for the music extension, including partially addressed concerns, future enhancements, and testing/architectural considerations.

**Last Updated:** December 2024

---

## Partially Addressed Items

These items have been partially implemented but need improvement for production use.

### 1. Tempo Server Timing Drift ⚠️

**Status:** Partially addressed - comment mentions recalculation, but implementation doesn't actually recalculate from current time.

**Current State:**
- Comment on line 128 in `tempo_server.ex` says "Recalculate schedule to prevent drift"
- However, `schedule_beat/1` (line 136) simply calls `Process.send_after/3` with fixed interval
- Does NOT recalculate from current time - still subject to drift
- For short sessions (< 5 minutes), drift is likely negligible (~50-100ms after 50 seconds)

**Impact:**
- Acceptable for MVP/development
- For production with long sessions (> 5 minutes), tempo will feel "off" over time
- 120 BPM = 500ms per beat, but accumulated drift can cause noticeable timing issues

**Recommended Fix:**

Update `lib/extensions/music/tempo_server.ex`:

```elixir
@impl true
def handle_info(:beat, state) do
  # Use Tenants.tenant_topic/3 to construct correct PubSub topic
  tenant_topic = Tenants.tenant_topic(state.tenant_id, "music_room:#{state.room_id}", true)

  Phoenix.PubSub.broadcast(
    Realtime.PubSub,
    tenant_topic,
    {:beat, state.beat}
  )

  # Recalculate schedule from current time to prevent drift
  now = System.monotonic_time(:millisecond)
  ms_per_beat = div(60_000, state.bpm)
  next_beat_time = now + ms_per_beat
  timer_ref = schedule_beat_at(next_beat_time)

  {:noreply, %{state | beat: state.beat + 1, timer_ref: timer_ref}}
end

## Private Functions

defp schedule_beat_at(target_time) do
  now = System.monotonic_time(:millisecond)
  delay = max(0, target_time - now)
  Process.send_after(self(), :beat, delay)
end

# Remove or update the old schedule_beat/1 function
defp schedule_beat(bpm) do
  # Keep for backward compatibility with set_tempo, but use schedule_beat_at internally
  now = System.monotonic_time(:millisecond)
  ms_per_beat = div(60_000, bpm)
  schedule_beat_at(now + ms_per_beat)
end
```

**Alternative Approach:** Use Erlang's `:timer.send_interval/2` which is more accurate:
```elixir
:timer.send_interval(ms_per_beat, :beat)
```

**Testing:**
- Add test that verifies beats arrive at correct intervals over extended period
- Test that tempo changes don't cause drift accumulation

---

### 2. Memory Usage & Room Cleanup ⚠️

**Status:** Partially addressed - memory usage is minimal, but no cleanup mechanism exists.

**Current State:**
- No automatic cleanup of inactive rooms
- Rooms persist until explicitly closed via `close_room/1`
- Memory usage is minimal (~2MB for 1000 rooms: ~2KB per TempoServer + ~200 bytes per room state)
- No periodic cleanup task

**Impact:**
- Acceptable for MVP/development
- For production, inactive rooms will accumulate over time
- With thousands of rooms, memory usage could become significant

**Recommended Fix:**

Add periodic cleanup task to `SessionManager`:

```elixir
# In lib/extensions/music/session_manager.ex

@doc """
Cleanup expired rooms (rooms inactive for more than max_age_hours).
"""
def cleanup_expired_rooms(tenant_id, max_age_hours \\ 24) do
  GenServer.call(__MODULE__, {:cleanup_expired_rooms, tenant_id, max_age_hours})
end

# Add to handle_call:
@impl true
def handle_call({:cleanup_expired_rooms, tenant_id, max_age_hours}, _from, state) do
  now = System.system_time(:second)
  max_age_seconds = max_age_hours * 3600
  
  {expired_rooms, active_rooms} = Enum.split_with(state, fn {room_id, room} ->
    room.tenant_id == tenant_id and
    (now - room.created_at) > max_age_seconds and
    length(room.students) == 0  # No active students
  end)
  
  # Close expired rooms
  Enum.each(expired_rooms, fn {room_id, room} ->
    Supervisor.stop_tempo_server(room_id, room.tenant_id)
  end)
  
  new_state = Map.drop(state, Enum.map(expired_rooms, &elem(&1, 0)))
  
  Logger.info("Cleaned up #{length(expired_rooms)} expired rooms for tenant #{tenant_id}")
  {:reply, {:ok, length(expired_rooms)}, new_state}
end

# Schedule periodic cleanup (add to init or start a separate task)
def init(_) do
  # Schedule cleanup every hour
  schedule_cleanup()
  {:ok, %{}}
end

defp schedule_cleanup do
  Process.send_after(self(), :cleanup_rooms, 3_600_000)  # 1 hour
end

@impl true
def handle_info(:cleanup_rooms, state) do
  # Cleanup for all tenants (or iterate through active tenants)
  # This is a simplified version - you may want to track tenants separately
  schedule_cleanup()
  {:noreply, state}
end
```

**Alternative:** Add cleanup to a separate GenServer task that runs periodically.

**Testing:**
- Test that expired rooms are cleaned up
- Test that active rooms (with students) are not cleaned up
- Test that tempo servers are stopped when rooms are cleaned up

---

### 3. Authorization Security Concern ⚠️ **HIGH PRIORITY**

**Status:** Security concern - role is currently client-provided, not verified from JWT.

**Current State:**
- Role comes from `params["role"]` in channel join (line 46 in `music_room_channel.ex`)
- Role is client-provided, not verified from JWT claims
- `socket.assigns.claims` is available (from JWT verification in `user_socket.ex`)
- But role is not extracted from claims - relies on client honesty

**Security Risk:** **MEDIUM-HIGH**
- Client can send `role: "teacher"` and gain unauthorized access to teacher controls
- Can set tempo, mute students, assign beats, etc.
- This is a security vulnerability that should be fixed before production

**Recommended Fix:**

Update `lib/realtime_web/channels/music_room_channel.ex`:

```elixir
def join("music_room:" <> room_id, params, socket) do
  tenant_id = socket.assigns.tenant

  # Validate room exists
  case SessionManager.get_room(room_id) do
    {:ok, room} ->
      student_id = params["student_id"]

      # Join room (track student)
      case SessionManager.join_room(room_id, tenant_id, student_id) do
        :ok ->
          # Extract role from JWT claims (secure) instead of params (insecure)
          role = socket.assigns.claims["role"] || "student"
          
          socket =
            socket
            |> assign(:room_id, room_id)
            |> assign(:tenant_id, tenant_id)
            |> assign(:student_id, student_id)
            |> assign(:role, role)  # Use JWT role, not client-provided

          # ... rest of join logic ...
```

**Additional Security Considerations:**
- Verify that the user has permission to join the room (check if they're a student in the tenant)
- Consider checking database for teacher role if JWT doesn't include it
- Add logging for authorization failures

**Testing:**
- Test that client-provided role is ignored
- Test that JWT role is used correctly
- Test that unauthorized users cannot access teacher controls
- Test edge cases (missing role in JWT, invalid JWT, etc.)

---

## Not Addressed Items (Future Work)

These items are not currently implemented but should be considered for production use.

### 1. Database Persistence for Room State

**Status:** Not addressed - still using in-memory GenServer state only.

**Current State:**
- `SessionManager` state is in-memory only (line 90: `{:ok, %{}}`)
- No database persistence
- No recovery mechanism on restart
- Rooms are ephemeral - lost on server restart

**Impact:**
- Acceptable for MVP/development
- For production, server restarts will disconnect all active sessions
- Cannot query room history or analytics across restarts
- Limits scalability (state tied to single GenServer process)

**Future Implementation Guidelines:**

**Step 1: Create Database Schema**

Create migration:
```elixir
# priv/repo/migrations/YYYYMMDDHHMMSS_create_music_rooms_table.exs
defmodule Realtime.Repo.Migrations.CreateMusicRoomsTable do
  use Ecto.Migration

  def change do
    create table(:music_rooms, prefix: "_realtime") do
      add :room_id, :string, null: false
      add :tenant_id, :string, null: false
      add :teacher_id, :string, null: false
      add :bpm, :integer, default: 120
      add :students, {:array, :string}, default: []
      add :beat_assignments, :map, default: %{}
      add :game_type, :string
      add :game_state, :map, default: %{}
      add :active, :boolean, default: true
      add :created_at, :utc_datetime
      add :last_activity_at, :utc_datetime
      
      timestamps()
    end

    create unique_index(:music_rooms, [:room_id, :tenant_id], prefix: "_realtime")
    create index(:music_rooms, [:tenant_id, :active], prefix: "_realtime")
  end
end
```

**Step 2: Create Ecto Schema**

```elixir
# lib/extensions/music/schemas/music_room.ex
defmodule Realtime.Music.Schemas.MusicRoom do
  use Ecto.Schema

  @primary_key false
  schema "music_rooms", prefix: "_realtime" do
    field :room_id, :string, primary_key: true
    field :tenant_id, :string
    field :teacher_id, :string
    field :bpm, :integer
    field :students, {:array, :string}
    field :beat_assignments, :map
    field :game_type, :string
    field :game_state, :map
    field :active, :boolean
    field :created_at, :utc_datetime
    field :last_activity_at, :utc_datetime
    
    timestamps()
  end

  def changeset(room, attrs) do
    room
    |> cast(attrs, [:room_id, :tenant_id, :teacher_id, :bpm, :students, :beat_assignments, 
                    :game_type, :game_state, :active, :created_at, :last_activity_at])
    |> validate_required([:room_id, :tenant_id, :teacher_id])
  end
end
```

**Step 3: Update SessionManager to Use Database**

```elixir
# Hybrid approach: Keep hot data in memory, persist to DB
def create_room(teacher_id, tenant_id, opts \\ []) do
  # Create in memory
  # Also persist to database
  %MusicRoom{}
  |> MusicRoom.changeset(%{
    room_id: room_id,
    tenant_id: tenant_id,
    teacher_id: teacher_id,
    bpm: bpm,
    students: [],
    beat_assignments: %{},
    active: true,
    created_at: DateTime.utc_now()
  })
  |> Repo.insert()
  
  # Then update in-memory state
end

# On startup, load active rooms from database
def init(_) do
  rooms = Repo.all(
    from r in MusicRoom,
    where: r.active == true,
    select: {r.room_id, r}
  )
  
  state = Enum.reduce(rooms, %{}, fn {room_id, room}, acc ->
    # Convert Ecto struct to map for in-memory state
    room_map = %{
      room_id: room.room_id,
      tenant_id: room.tenant_id,
      teacher_id: room.teacher_id,
      bpm: room.bpm,
      students: room.students || [],
      beat_assignments: room.beat_assignments || %{},
      game_type: if(room.game_type, do: String.to_existing_atom(room.game_type)),
      game_state: room.game_state || %{},
      created_at: DateTime.to_unix(room.created_at)
    }
    Map.put(acc, room_id, room_map)
  end)
  
  {:ok, state}
end
```

**Considerations:**
- Use hybrid approach: hot data in memory, persist to DB for recovery
- Persist on room creation, updates, and periodically
- Load active rooms on startup
- Consider using database for analytics queries

**Testing:**
- Test that rooms persist across restarts
- Test that active rooms are loaded on startup
- Test that room updates are persisted
- Test recovery scenarios

---

### 2. Game State Persistence

**Status:** Not addressed - game state is stored in-memory only.

**Future Work:**
- When implementing game state management (see `MUSIC_GAMES_IMPLEMENTATION_PLAN.md`), consider persistence
- Store game sessions in database for analytics and recovery
- See Phase 5 in `MUSIC_GAMES_IMPLEMENTATION_PLAN.md` for database schema

---

## Testing Considerations

### 1. Testing Async Processes and Timing

**Challenge:** Testing tempo server beats requires waiting for async messages, which can be flaky.

**Guidelines:**
- Use `ExUnit.Case, async: false` for timing-sensitive tests
- Test timing logic separately (e.g., `ms_per_beat` calculation)
- Use generous timeouts in `assert_receive` (e.g., 1000ms for 500ms intervals)
- Consider mocking time for deterministic tests
- Focus integration tests on actual timing, unit tests on logic

**Example:**
```elixir
test "schedules beats at correct interval", %{test: test_name} do
  use ExUnit.Case, async: false
  
  # Test timing logic
  assert TempoServer.ms_per_beat(120) == 500
  
  # Test actual timing in integration test
  # Use generous timeout
  assert_receive {:beat, _}, 1000
end
```

---

### 2. Testing PubSub Broadcasts

**Challenge:** Testing that beats are broadcast correctly requires PubSub setup and timing.

**Guidelines:**
- Test PubSub directly in integration tests
- Subscribe to topic before starting tempo server
- Use `assert_receive` with appropriate timeouts
- Consider mocking PubSub for unit tests (verify calls, not actual broadcasts)

**Example:**
```elixir
test "broadcasts beats to PubSub" do
  tenant_id = "test-tenant"
  room_id = "test-room"
  topic = Tenants.tenant_topic(tenant_id, "music_room:#{room_id}", true)
  
  Phoenix.PubSub.subscribe(Realtime.PubSub, topic)
  
  {:ok, _pid} = Supervisor.start_tempo_server(room_id, 120, tenant_id)
  TempoServer.start_clock(room_id, tenant_id)
  
  assert_receive {:beat, 0}, 600
  assert_receive {:beat, 1}, 600
end
```

---

### 3. Testing Multi-Tenant Scenarios

**Challenge:** Ensuring tenant isolation works correctly.

**Guidelines:**
- Create multiple test tenants
- Verify rooms from different tenants don't interfere
- Test registry key collisions (same room_id, different tenants)
- Test PubSub topic isolation
- Test that tenant_id is verified in all operations

**Example:**
```elixir
test "tenant isolation" do
  tenant_a = "tenant-a"
  tenant_b = "tenant-b"
  room_id = "MUSIC-1234"
  
  # Create rooms with same ID but different tenants
  {:ok, _} = SessionManager.create_room("teacher-1", tenant_a, bpm: 120)
  {:ok, _} = SessionManager.create_room("teacher-2", tenant_b, bpm: 140)
  
  # Verify they don't interfere
  {:ok, room_a} = SessionManager.get_room(room_id)
  assert room_a.tenant_id == tenant_a
  assert room_a.bpm == 120
end
```

---

## Architectural Considerations

### 1. Performance Under Load

**Considerations:**
- Tempo server accuracy may degrade under high load
- Use `System.monotonic_time/1` for accurate timing (already done)
- Monitor tempo accuracy in production
- Consider using Erlang's `:timer` module for more accurate timing

**Monitoring:**
- Track tempo drift over time
- Monitor beat delivery latency
- Alert if drift exceeds threshold (e.g., > 50ms)

---

### 2. PubSub Message Overhead

**Current State:**
- Each beat creates a PubSub message
- With 100 rooms × 2 beats/second = 200 messages/second
- Phoenix PubSub handles this easily (tested to 250k connections)

**Considerations:**
- Monitor message rates in production
- Consider batching if needed (unlikely for current scale)
- PubSub is efficient, but monitor for bottlenecks

---

### 3. Scalability

**Current Architecture:**
- Single `SessionManager` GenServer holds all room state
- Single `RateLimiter` GenServer for all rate limiting
- Tempo servers are distributed (one per room)

**Considerations:**
- `SessionManager` could become a bottleneck with thousands of rooms
- Consider sharding by tenant_id or room_id
- Consider using database for room state (see "Database Persistence" above)
- Rate limiter uses ETS (fast, but single node)

**Future Enhancements:**
- Shard `SessionManager` by tenant
- Use distributed ETS for rate limiting across nodes
- Consider Redis for distributed rate limiting

---

### 4. Deployment Considerations

**Environment Variables:**
- Music extension config in `config/config.exs`:
  ```elixir
  config :realtime, :extensions,
    music: %{
      rate_limit: %{
        notes_per_second: 10,
        teacher_notes_per_second: 50
      }
    }
  ```

**Database Migrations:**
- If implementing database persistence, create migrations
- Consider migration strategy for existing in-memory state

**Monitoring:**
- Add metrics for room creation/closure
- Track tempo server count
- Monitor rate limiting rejections
- Track authorization failures

---

## Priority Summary

### High Priority (Fix Before Production)
1. **Authorization Security** (#3) - Extract role from JWT, not client params
2. **Tempo Timing Drift** (#1) - Implement proper recalculation

### Medium Priority (Should Fix for Production)
3. **Room Cleanup** (#2) - Add periodic cleanup of inactive rooms

### Low Priority (Future Enhancements)
4. **Database Persistence** - For production scalability and recovery
5. **Game State Persistence** - When implementing games infrastructure
6. **Performance Monitoring** - Add metrics and alerts

---

**Remember:** Focus on security and correctness first (authorization, timing), then scalability (cleanup, persistence), then enhancements (monitoring, analytics).

