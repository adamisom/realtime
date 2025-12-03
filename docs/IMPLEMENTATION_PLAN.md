# Music Extension & Games Implementation Plan

## Overview

This plan covers remaining work items and new infrastructure for music education games, building on the existing music extension.

**Goal:** 
1. Fix security and production issues (authorization, tempo drift, cleanup)
2. Add infrastructure for 5 music education games:
   - **Rhythm Circle** - Structured rhythm exercises with pattern assignments
   - **Melody Builder** - Collaborative melody construction with turn-taking
   - **Dynamics Dance** - Volume and dynamic expression exercises
   - **Improvisation Jam** - Turn-taking and solo improvisation
   - **Call and Response** - Pattern matching and response exercises

**What You're Building:** Infrastructure components that enable game-specific features. The games themselves will be built in frontend applications, but this backend provides the real-time coordination, state management, and validation needed.

**Note:** 
- High-value unit test examples are in `docs/IMPLEMENTATION_TESTS.md`
- **⚠️ CRITICAL:** See `docs/MUSIC_GAMES_PLAN_REVIEW.md` for code fixes and roadblocks

---

## Phase 0: Foundation Review & Setup (Optional - Before Phase 1)

### Goal
Review existing music extension implementation and understand what's already available before starting new work.

### Subphase 0.1: Review Current Implementation

#### Tasks
- [ ] Review `lib/extensions/music/session_manager.ex` (room state structure)
- [ ] Review `lib/realtime_web/channels/music_room_channel.ex` (channel events)
- [ ] Review `lib/extensions/music/tempo_server.ex` (beat broadcasting)
- [ ] Understand current `play_note` event structure
- [ ] Review rate limiting implementation

#### Key Files to Review
- `lib/extensions/music/session_manager.ex` - Room state management
- `lib/realtime_web/channels/music_room_channel.ex` - Channel event handlers
- `lib/extensions/music/tempo_server.ex` - Beat synchronization
- `lib/extensions/music/rate_limiter.ex` - Rate limiting logic

#### Verification
```elixir
# In IEx console
iex> Realtime.Music.SessionManager
# Should return module

iex> {:ok, room_id} = Realtime.Music.SessionManager.create_room("teacher-1", "test-tenant", bpm: 120)
iex> {:ok, room} = Realtime.Music.SessionManager.get_room(room_id)
# Should return room with: room_id, teacher_id, tenant_id, bpm, students, created_at
```

### Subphase 0.2: Identify Extension Points

#### Current State Documentation

**Current `play_note` event:**
```elixir
# Current payload: %{"midi" => 60}
# Missing: velocity (0-127)
```

**Current room state:**
```elixir
%{
  room_id: "MUSIC-1234",
  teacher_id: "teacher-1",
  tenant_id: "tenant-1",
  bpm: 120,
  created_at: timestamp,
  students: ["student-1", "student-2"],
  beat_assignments: %{1 => "student-1", 3 => "student-2"}
}
# Missing: game_type, game_state
```

---

## Phase 1: Security & Remaining Work Fixes (Day 1-2)

### Goal
Fix critical security issue and production concerns before adding new features.

### Subphase 1.1: Authorization Security Fix ⚠️ **HIGH PRIORITY**

#### Tasks
- [ ] Extract role from JWT claims instead of client params
- [ ] Update channel join handler
- [ ] Add tests for authorization

#### Files to Modify

**`lib/realtime_web/channels/music_room_channel.ex`** - Fix role extraction:

```elixir
def join("music_room:" <> room_id, params, socket) do
  tenant_id = socket.assigns.tenant

  case SessionManager.get_room(room_id) do
    {:ok, room} ->
      student_id = params["student_id"]

      case SessionManager.join_room(room_id, tenant_id, student_id) do
        :ok ->
          # ✅ FIX: Extract role from JWT claims (secure) instead of params (insecure)
          role = socket.assigns.claims["role"] || "student"
          
          socket =
            socket
            |> assign(:room_id, room_id)
            |> assign(:tenant_id, tenant_id)
            |> assign(:student_id, student_id)
            |> assign(:role, role)  # Use JWT role, not client-provided

          # ... rest of join logic ...
```

#### Smoke Test
```elixir
# Test that client-provided role is ignored
# Test that JWT role is used correctly
# Test unauthorized access is blocked
```

#### High-Value Tests
See `docs/IMPLEMENTATION_TESTS.md` → **Phase 1.1**

---

### Subphase 1.2: Tempo Server Timing Drift Fix

#### Tasks
- [ ] Implement proper recalculation from current time
- [ ] Update `schedule_beat` to use `schedule_beat_at`
- [ ] Add tests for timing accuracy

#### Files to Modify

**`lib/extensions/music/tempo_server.ex`** - Fix drift:

```elixir
@impl true
def handle_info(:beat, state) do
  tenant_topic = Tenants.tenant_topic(state.tenant_id, "music_room:#{state.room_id}", true)
  
  Phoenix.PubSub.broadcast(Realtime.PubSub, tenant_topic, {:beat, state.beat})
  
  # ✅ FIX: Recalculate from current time to prevent drift
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

defp schedule_beat(bpm) do
  now = System.monotonic_time(:millisecond)
  ms_per_beat = div(60_000, bpm)
  schedule_beat_at(now + ms_per_beat)
end
```

#### High-Value Tests
See `docs/IMPLEMENTATION_TESTS.md` → **Phase 1.2**

---

### Subphase 1.3: Room Cleanup Mechanism

#### Tasks
- [ ] Add `cleanup_expired_rooms/2` function
- [ ] Add periodic cleanup scheduling
- [ ] Add tests for cleanup

#### Files to Modify

**`lib/extensions/music/session_manager.ex`** - Add cleanup:

```elixir
  @doc """
Cleanup expired rooms (rooms inactive for more than max_age_hours).
"""
def cleanup_expired_rooms(tenant_id, max_age_hours \\ 24) do
  GenServer.call(__MODULE__, {:cleanup_expired_rooms, tenant_id, max_age_hours})
end

@impl true
def handle_call({:cleanup_expired_rooms, tenant_id, max_age_hours}, _from, state) do
  now = System.system_time(:second)
  max_age_seconds = max_age_hours * 3600
  
  expired = Enum.filter(state, fn {_room_id, room} ->
    room.tenant_id == tenant_id and
    (now - room.created_at) > max_age_seconds and
    length(room.students) == 0
  end)
  
  Enum.each(expired, fn {room_id, room} ->
    Supervisor.stop_tempo_server(room_id, room.tenant_id)
  end)
  
  new_state = Map.drop(state, Enum.map(expired, &elem(&1, 0)))
  {:reply, {:ok, length(expired)}, new_state}
end

# Add to init:
def init(_) do
  schedule_cleanup()
  {:ok, %{}}
end

defp schedule_cleanup do
  Process.send_after(self(), :cleanup_rooms, 3_600_000)  # 1 hour
  end

  @impl true
def handle_info(:cleanup_rooms, state) do
  # Cleanup all tenants (simplified - can be improved)
  schedule_cleanup()
  {:noreply, state}
end
```

#### High-Value Tests
See `docs/IMPLEMENTATION_TESTS.md` → **Phase 1.3**

---

## Phase 2: Foundation Infrastructure (Day 3-5)

### Goal
Add core infrastructure needed by all games: volume/dynamics support, game state management, and note sequence storage.

### Subphase 2.1: Add Volume/Dynamics Support

#### Tasks
- [ ] Update `play_note` to accept optional `velocity` field (0-127)
- [ ] Update channel handler to extract and validate velocity
- [ ] Update broadcast payload to include velocity
- [ ] Update `SelTracker` to log velocity
- [ ] Ensure backward compatibility

#### Files to Modify

**`lib/realtime_web/channels/music_room_channel.ex`** - Update `play_note`:

```elixir
def handle_in("play_note", %{"midi" => midi} = payload, socket) do
  room_id = socket.assigns.room_id
  tenant_id = socket.assigns.tenant_id
  student_id = socket.assigns.student_id

  # Extract velocity (default to 64 for backward compatibility)
  velocity = Map.get(payload, "velocity", 64)
  velocity = cond do
    velocity < 0 -> 0
    velocity > 127 -> 127
    true -> velocity
  end

  # ... existing rate limiting code ...
  
  # Broadcast with velocity
  broadcast!(socket, "student_note", %{
    midi: midi,
    velocity: velocity,
    student_id: student_id,
    timestamp: System.system_time(:millisecond)
  })

  # Log with velocity
  SelTracker.log_participation(room_id, tenant_id, student_id, "note_played", %{midi: midi, velocity: velocity})
  
  {:reply, :ok, socket}
end
```

#### High-Value Tests
See `docs/IMPLEMENTATION_TESTS.md` → **Phase 2.1**

---

### Subphase 2.2: Add Game State Management

#### Tasks
- [ ] Add `game_type` and `game_state` fields to room state
- [ ] Implement `set_game_type/3`, `update_game_state/3`, `get_game_state/2`
- [ ] Update `create_room` to initialize game fields

#### Files to Modify

**`lib/extensions/music/session_manager.ex`** - Add game state:

```elixir
  @doc """
Set the game type for a room.
"""
def set_game_type(room_id, tenant_id, game_type) when game_type in [
  :rhythm_circle, :melody_builder, :dynamics_dance, :improvisation_jam, :call_and_response
] do
  GenServer.call(__MODULE__, {:set_game_type, room_id, tenant_id, game_type})
  end

  @doc """
Update game state for a room (merges into existing state).
"""
def update_game_state(room_id, tenant_id, new_state) when is_map(new_state) do
  GenServer.call(__MODULE__, {:update_game_state, room_id, tenant_id, new_state})
end

@doc """
Get current game state for a room.
"""
def get_game_state(room_id, tenant_id) do
  GenServer.call(__MODULE__, {:get_game_state, room_id, tenant_id})
end

# Add to handle_call:
  @impl true
def handle_call({:set_game_type, room_id, tenant_id, game_type}, _from, state) do
  case Map.get(state, room_id) do
    nil -> {:reply, {:error, :not_found}, state}
    room ->
      if room.tenant_id == tenant_id do
        updated_room = %{room | game_type: game_type, game_state: %{}}
        {:reply, :ok, Map.put(state, room_id, updated_room)}
      else
        {:reply, {:error, :unauthorized}, state}
      end
  end
  end

  @impl true
def handle_call({:update_game_state, room_id, tenant_id, new_state}, _from, state) do
  case Map.get(state, room_id) do
    nil -> {:reply, {:error, :not_found}, state}
    room ->
      if room.tenant_id == tenant_id do
        current_game_state = Map.get(room, :game_state, %{})
        updated_game_state = Map.merge(current_game_state, new_state)
        updated_room = %{room | game_state: updated_game_state}
        {:reply, :ok, Map.put(state, room_id, updated_room)}
      else
        {:reply, {:error, :unauthorized}, state}
      end
  end
  end

  @impl true
def handle_call({:get_game_state, room_id, tenant_id}, _from, state) do
  case Map.get(state, room_id) do
    nil -> {:reply, {:error, :not_found}, state}
    room ->
      if room.tenant_id == tenant_id do
        game_type = Map.get(room, :game_type, nil)
        game_state = Map.get(room, :game_state, %{})
        {:reply, {:ok, %{game_type: game_type, game_state: game_state}}, state}
      else
        {:reply, {:error, :unauthorized}, state}
  end
end
end

# Update create_room to initialize game fields:
@impl true
def handle_call({:create_room, teacher_id, tenant_id, opts}, _from, state) do
  room_id = generate_join_code(state)
  bpm = Keyword.get(opts, :bpm, 120)
  
  case Realtime.Music.Supervisor.start_tempo_server(room_id, bpm, tenant_id) do
    {:ok, _pid} ->
      room = %{
        room_id: room_id,
        tenant_id: tenant_id,
        teacher_id: teacher_id,
        bpm: bpm,
        created_at: System.system_time(:second),
        students: [],
        beat_assignments: %{},
        game_type: nil,  # No game active by default
        game_state: %{}  # Empty game state
      }
      {:reply, {:ok, room_id}, Map.put(state, room_id, room)}
    error ->
      {:reply, {:error, error}, state}
  end
end
```

#### High-Value Tests
See `docs/IMPLEMENTATION_TESTS.md` → **Phase 2.2**

---

### Subphase 2.3: Create Pattern Storage Module

#### Tasks
- [ ] Create `lib/extensions/music/pattern.ex` module
- [ ] Define pattern struct with notes, timing, metadata
- [ ] Implement pattern creation, validation, and playback scheduling

#### Files to Create

**`lib/extensions/music/pattern.ex`**:

```elixir
defmodule Realtime.Music.Pattern do
  @moduledoc """
  Stores and manages musical patterns (sequences of notes with timing).
  """
  
  defstruct [:id, :name, :notes, :time_signature, :tempo, :pattern_type, :created_at]

  @doc """
  Create a new pattern.
  Notes format: [%{midi: 60, duration: 500, velocity: 80}, ...]
  """
  def create(name, notes, opts \\ []) do
    pattern_type = Keyword.get(opts, :pattern_type, :melody)
    time_signature = Keyword.get(opts, :time_signature, "4/4")
    tempo = Keyword.get(opts, :tempo, 120)
    
    notes_with_timing = add_timestamps(notes, 0)
    
    %__MODULE__{
      id: generate_id(),
      name: name,
      notes: notes_with_timing,
      time_signature: time_signature,
      tempo: tempo,
      pattern_type: pattern_type,
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Schedule playback - returns list of scheduled broadcasts.
  """
  def schedule_playback(pattern, start_time_ms) do
    Enum.map(pattern.notes, fn note ->
      %{
        midi: note.midi,
        velocity: Map.get(note, :velocity, 64),
        timestamp: start_time_ms + note.timestamp,
        duration: note.duration
      }
    end)
  end

  @doc """
  Validate a pattern.
  """
  def validate(pattern) do
    cond do
      not is_list(pattern.notes) or length(pattern.notes) == 0 ->
        {:error, :empty_pattern}
      not Enum.all?(pattern.notes, &valid_note?/1) ->
        {:error, :invalid_notes}
      true ->
        :ok
    end
  end

  @doc """
  Get pattern duration in milliseconds.
  """
  def duration(pattern) do
    case List.last(pattern.notes) do
      nil -> 0
      last_note -> last_note.timestamp + last_note.duration
    end
  end

  ## Private Functions

  defp add_timestamps(notes, start_time) do
    Enum.reduce(notes, {[], start_time}, fn note, {acc, current_time} ->
      note_with_timing = Map.put(note, :timestamp, current_time)
      {[note_with_timing | acc], current_time + note.duration}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp valid_note?(note) do
    midi = Map.get(note, :midi)
    duration = Map.get(note, :duration, 0)
    velocity = Map.get(note, :velocity, 64)
    
    is_integer(midi) and midi >= 0 and midi <= 127 and
    is_integer(duration) and duration > 0 and
    is_integer(velocity) and velocity >= 0 and velocity <= 127
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
```

#### Critical Logic: Pattern Timing

**Key Points:**
- Notes have cumulative timestamps (relative to pattern start)
- Duration is per-note (how long the note should play)
- Pattern duration = last note timestamp + last note duration
- Timestamps are in milliseconds

#### Smoke Test
```elixir
# Create a simple pattern
pattern = Realtime.Music.Pattern.create("Test Melody", [
  %{midi: 60, duration: 500, velocity: 80},
  %{midi: 62, duration: 500, velocity: 80},
  %{midi: 64, duration: 1000, velocity: 80}
])

# Validate
:ok = Realtime.Music.Pattern.validate(pattern)

# Get duration
duration = Realtime.Music.Pattern.duration(pattern)
# Should return: 2000 (500 + 500 + 1000)

# Schedule playback
scheduled = Realtime.Music.Pattern.schedule_playback(pattern, 0)
# Should return list with timestamps: 0, 500, 1000
```

#### High-Value Tests
See `docs/IMPLEMENTATION_TESTS.md` → **Phase 2.3**

---

## Phase 3: Turn Management (Day 6-7)

### Goal
Implement turn-taking infrastructure needed for Melody Builder and Improvisation Jam.

### Subphase 3.1: Create TurnManager Module

#### Tasks
- [ ] Create `lib/extensions/music/turn_manager.ex` module
- [ ] Implement turn rotation, timing, and state management
- [ ] Add serialization/deserialization for game_state storage

#### Files to Create

**`lib/extensions/music/turn_manager.ex`**:

```elixir
defmodule Realtime.Music.TurnManager do
  @moduledoc """
  Manages turn-taking for games that require sequential actions.
  """
  
  defstruct [:current_turn, :queue, :turn_duration_seconds, :turn_start_time, 
             :turn_state, :student_ids]

  @doc """
  Start turn rotation with a list of student IDs.
  """
  def start_turn_rotation(student_ids, turn_duration_seconds \\ 30) 
      when is_list(student_ids) and length(student_ids) > 0 do
    %__MODULE__{
      current_turn: List.first(student_ids),
      queue: tl(student_ids),
      turn_duration_seconds: turn_duration_seconds,
      turn_start_time: nil,
      turn_state: :waiting,
      student_ids: student_ids
    }
  end

  @doc """
  Start the current turn (begin timing).
  """
  def start_turn(turn_manager) do
    %{turn_manager | 
      turn_start_time: System.system_time(:second),
      turn_state: :active
    }
  end

  @doc """
  Advance to the next turn (rotate queue).
  """
  def next_turn(turn_manager) do
    new_queue = turn_manager.queue ++ [turn_manager.current_turn]
    {new_current, remaining_queue} = case new_queue do
      [next | rest] -> {next, rest}
      [] -> {nil, []}
    end
    
    %{turn_manager |
      current_turn: new_current,
      queue: remaining_queue,
      turn_start_time: nil,
      turn_state: if(new_current, do: :waiting, else: :completed)
    }
  end

  @doc """
  Get the current turn student ID.
  """
  def get_current_turn(turn_manager) do
    turn_manager.current_turn
  end

  @doc """
  Calculate remaining time for current turn (in seconds).
  """
  def time_remaining(turn_manager) do
    case turn_manager.turn_state do
      :active ->
        elapsed = System.system_time(:second) - turn_manager.turn_start_time
        remaining = turn_manager.turn_duration_seconds - elapsed
        max(0, remaining)
      _ ->
        nil
    end
  end

  @doc """
  Check if a specific student can act (is it their turn?).
  """
  def can_act?(turn_manager, student_id) do
    turn_manager.current_turn == student_id and 
    turn_manager.turn_state == :active
  end

  @doc """
  Check if turn has expired.
  """
  def turn_expired?(turn_manager) do
    case time_remaining(turn_manager) do
      nil -> false
      0 -> true
      _ -> false
    end
  end

  @doc """
  Reset turn rotation (start over from beginning).
  """
  def reset(turn_manager) do
    start_turn_rotation(turn_manager.student_ids, turn_manager.turn_duration_seconds)
  end

  @doc """
  Convert turn manager to map (for storage in game_state).
  """
  def to_map(turn_manager) do
    %{
      current_turn: turn_manager.current_turn,
      queue: turn_manager.queue,
      turn_duration_seconds: turn_manager.turn_duration_seconds,
      turn_start_time: turn_manager.turn_start_time,
      turn_state: turn_manager.turn_state,
      student_ids: turn_manager.student_ids
    }
  end

  @doc """
  Reconstruct turn manager from map.
  """
  def from_map(map) do
    %__MODULE__{
      current_turn: map.current_turn,
      queue: map.queue,
      turn_duration_seconds: map.turn_duration_seconds,
      turn_start_time: map.turn_start_time,
      turn_state: map.turn_state,
      student_ids: map.student_ids
    }
  end
end
```

#### Critical Logic: Turn Rotation

**Key Points:**
- Circular queue: current turn moves to end after completion
- Turn states: `:waiting` → `:active` → (next turn `:waiting`)
- Timing tracked in seconds (Unix timestamp)
- Can serialize/deserialize for storage in game_state

#### Smoke Test
```elixir
# Start turn rotation
students = ["student-1", "student-2", "student-3"]
tm = Realtime.Music.TurnManager.start_turn_rotation(students, 30)

# Check current turn
Realtime.Music.TurnManager.get_current_turn(tm)
# Should return: "student-1"

# Start turn
tm = Realtime.Music.TurnManager.start_turn(tm)
Realtime.Music.TurnManager.time_remaining(tm)
# Should return: 30 (or close to it)

# Check if student can act
Realtime.Music.TurnManager.can_act?(tm, "student-1")
# Should return: true
Realtime.Music.TurnManager.can_act?(tm, "student-2")
# Should return: false

# Advance to next turn
tm = Realtime.Music.TurnManager.next_turn(tm)
Realtime.Music.TurnManager.get_current_turn(tm)
# Should return: "student-2"
```

#### High-Value Tests
See `docs/IMPLEMENTATION_TESTS.md` → **Phase 3.1**

---

### Subphase 3.2: Integrate TurnManager into SessionManager

#### Tasks
- [ ] Add turn management functions to SessionManager
- [ ] Store turn manager in game_state
- [ ] Add functions to start/advance turns

#### Files to Modify

**`lib/extensions/music/session_manager.ex`** - Add turn management:

```elixir
alias Realtime.Music.TurnManager

@doc """
Start turn rotation for a game.
"""
def start_turn_rotation(room_id, tenant_id, student_ids, turn_duration_seconds \\ 30) do
  GenServer.call(__MODULE__, {:start_turn_rotation, room_id, tenant_id, student_ids, turn_duration_seconds})
  end

  @doc """
Start the current turn (begin timing).
  """
def start_current_turn(room_id, tenant_id) do
  GenServer.call(__MODULE__, {:start_current_turn, room_id, tenant_id})
  end

  @doc """
Advance to the next turn.
"""
def advance_turn(room_id, tenant_id) do
  GenServer.call(__MODULE__, {:advance_turn, room_id, tenant_id})
end

@doc """
Get current turn information.
"""
def get_current_turn(room_id, tenant_id) do
  GenServer.call(__MODULE__, {:get_current_turn, room_id, tenant_id})
end

# Add to handle_call:

@impl true
def handle_call({:start_turn_rotation, room_id, tenant_id, student_ids, turn_duration_seconds}, _from, state) do
  case Map.get(state, room_id) do
    nil ->
      {:reply, {:error, :not_found}, state}
    
    room ->
      if room.tenant_id == tenant_id do
        turn_manager = TurnManager.start_turn_rotation(student_ids, turn_duration_seconds)
        
        updated_game_state = Map.put(room.game_state, :turn_manager, TurnManager.to_map(turn_manager))
        updated_room = %{room | game_state: updated_game_state}
        
        {:reply, :ok, Map.put(state, room_id, updated_room)}
      else
        {:reply, {:error, :unauthorized}, state}
      end
  end
end

@impl true
def handle_call({:start_current_turn, room_id, tenant_id}, _from, state) do
  case Map.get(state, room_id) do
    nil ->
      {:reply, {:error, :not_found}, state}
    
    room ->
      if room.tenant_id == tenant_id do
        turn_manager_map = Map.get(room.game_state, :turn_manager)
        if turn_manager_map do
          turn_manager = TurnManager.from_map(turn_manager_map)
          updated_turn_manager = TurnManager.start_turn(turn_manager)
          
          updated_game_state = Map.put(room.game_state, :turn_manager, TurnManager.to_map(updated_turn_manager))
          updated_room = %{room | game_state: updated_game_state}
          
          {:reply, :ok, Map.put(state, room_id, updated_room)}
        else
          {:reply, {:error, :no_turn_rotation}, state}
        end
      else
        {:reply, {:error, :unauthorized}, state}
      end
  end
end

@impl true
def handle_call({:advance_turn, room_id, tenant_id}, _from, state) do
  case Map.get(state, room_id) do
    nil ->
      {:reply, {:error, :not_found}, state}
    
    room ->
      if room.tenant_id == tenant_id do
        turn_manager_map = Map.get(room.game_state, :turn_manager)
        if turn_manager_map do
          turn_manager = TurnManager.from_map(turn_manager_map)
          updated_turn_manager = TurnManager.next_turn(turn_manager)
          
          updated_game_state = Map.put(room.game_state, :turn_manager, TurnManager.to_map(updated_turn_manager))
          updated_room = %{room | game_state: updated_game_state}
          
          {:reply, :ok, Map.put(state, room_id, updated_room)}
        else
          {:reply, {:error, :no_turn_rotation}, state}
        end
      else
        {:reply, {:error, :unauthorized}, state}
      end
  end
end

@impl true
def handle_call({:get_current_turn, room_id, tenant_id}, _from, state) do
  case Map.get(state, room_id) do
    nil ->
      {:reply, {:error, :not_found}, state}
    
    room ->
      if room.tenant_id == tenant_id do
        turn_manager_map = Map.get(room.game_state, :turn_manager)
        if turn_manager_map do
          turn_manager = TurnManager.from_map(turn_manager_map)
          time_remaining = TurnManager.time_remaining(turn_manager)
          
          {:reply, {:ok, %{
            current_turn: turn_manager.current_turn,
            turn_state: turn_manager.turn_state,
            time_remaining: time_remaining,
            queue: turn_manager.queue
          }}, state}
        else
          {:reply, {:error, :no_turn_rotation}, state}
        end
      else
        {:reply, {:error, :unauthorized}, state}
      end
  end
end
```

#### High-Value Tests
See `docs/IMPLEMENTATION_TESTS.md` → **Phase 3.2**

---

### Subphase 3.3: Add Channel Events for Turn Management

#### Tasks
- [ ] Add `start_turn_rotation`, `start_turn`, `advance_turn`, `request_turn` events
- [ ] Broadcast turn updates to all clients

#### Files to Modify

**`lib/realtime_web/channels/music_room_channel.ex`** - Add turn handlers:

```elixir
def handle_in("start_turn_rotation", %{"student_ids" => student_ids, "duration_seconds" => duration}, socket) do
  if is_teacher?(socket) do
    room_id = socket.assigns.room_id
    tenant_id = socket.assigns.tenant_id
    
    case SessionManager.start_turn_rotation(room_id, tenant_id, student_ids, duration) do
      :ok ->
        broadcast!(socket, "turn_rotation_started", %{student_ids: student_ids, duration_seconds: duration})
        {:reply, :ok, socket}
      error ->
        {:reply, {:error, %{reason: inspect(error)}}, socket}
    end
  else
    {:reply, {:error, %{reason: "unauthorized"}}, socket}
  end
end

def handle_in("start_turn", _payload, socket) do
  if is_teacher?(socket) do
    room_id = socket.assigns.room_id
    tenant_id = socket.assigns.tenant_id
    
    case SessionManager.start_current_turn(room_id, tenant_id) do
      :ok ->
        {:ok, turn_info} = SessionManager.get_current_turn(room_id, tenant_id)
        broadcast!(socket, "turn_started", turn_info)
        {:reply, :ok, socket}
      error ->
        {:reply, {:error, %{reason: inspect(error)}}, socket}
    end
  else
    {:reply, {:error, %{reason: "unauthorized"}}, socket}
  end
end

def handle_in("advance_turn", _payload, socket) do
  if is_teacher?(socket) do
    room_id = socket.assigns.room_id
    tenant_id = socket.assigns.tenant_id
    
    case SessionManager.advance_turn(room_id, tenant_id) do
      :ok ->
        {:ok, turn_info} = SessionManager.get_current_turn(room_id, tenant_id)
        broadcast!(socket, "turn_advanced", turn_info)
        {:reply, :ok, socket}
      error ->
        {:reply, {:error, %{reason: inspect(error)}}, socket}
    end
  else
    {:reply, {:error, %{reason: "unauthorized"}}, socket}
  end
end

def handle_in("request_turn", _payload, socket) do
  room_id = socket.assigns.room_id
  tenant_id = socket.assigns.tenant_id
  student_id = socket.assigns.student_id
  
  {:ok, turn_info} = SessionManager.get_current_turn(room_id, tenant_id)
  
  if turn_info.current_turn == student_id do
    push(socket, "turn_granted", turn_info)
    {:reply, :ok, socket}
  else
    {:reply, {:error, %{reason: "not_your_turn", current_turn: turn_info.current_turn}}, socket}
  end
end
```

#### High-Value Tests
See `docs/IMPLEMENTATION_TESTS.md` → **Phase 3.3**

---

## Phase 4: Pattern Matching (Day 8-9)

### Goal
Implement pattern matching and validation for Call and Response game.

### Subphase 4.1: Create PatternMatcher Module

#### Tasks
- [ ] Create `lib/extensions/music/pattern_matcher.ex` module
- [ ] Implement note sequence comparison with tolerance
- [ ] Calculate accuracy percentage
- [ ] ✅ FIX: Remove invalid `return` statement, add division by zero protection

#### Files to Create

**`lib/extensions/music/pattern_matcher.ex`**:

```elixir
defmodule Realtime.Music.PatternMatcher do
  @moduledoc """
  Compares musical patterns for similarity/accuracy.
  """

  @doc """
  Check if response pattern matches call pattern.
  """
  def match?(call_pattern, response_pattern, opts \\ []) do
    accuracy = accuracy(call_pattern, response_pattern, opts)
    min_accuracy = Keyword.get(opts, :min_accuracy, 80.0)
    accuracy >= min_accuracy
  end

  @doc """
  Calculate accuracy percentage (0-100) between call and response patterns.
  ✅ FIX: Fixed invalid return statement and division by zero
  """
  def accuracy(call_pattern, response_pattern, opts \\ []) do
    timing_tolerance = Keyword.get(opts, :timing_tolerance_ms, 200)
    pitch_tolerance = Keyword.get(opts, :pitch_tolerance_semitones, 0)
    
    call_notes = normalize_pattern(call_pattern)
    response_notes = normalize_pattern(response_pattern)
    
    # ✅ FIX: Calculate length_ratio safely
    max_len = max(length(call_notes), length(response_notes))
    length_ratio = if max_len > 0 do
      min(length(call_notes), length(response_notes)) / max_len
    else
      0.0
    end
    
    # ✅ FIX: Early return using if expression (not return statement)
    if length_ratio < 0.5 do
      0.0
    else
      pairs = Enum.zip(call_notes, response_notes)
      
      scores = Enum.map(pairs, fn {call_note, response_note} ->
        note_score(call_note, response_note, timing_tolerance, pitch_tolerance)
      end)
      
      # ✅ FIX: Division by zero protection
      avg_score = if length(scores) > 0 do
        Enum.sum(scores) / length(scores)
      else
        0.0
      end
      
      avg_score * length_ratio
  end
end

  @doc """
  Get detailed feedback on pattern match.
  """
  def feedback(call_pattern, response_pattern, opts \\ []) do
    accuracy_score = accuracy(call_pattern, response_pattern, opts)
    is_match = match?(call_pattern, response_pattern, opts)
    
    call_notes = normalize_pattern(call_pattern)
    response_notes = normalize_pattern(response_pattern)
    
    %{
      match: is_match,
      accuracy: accuracy_score,
      call_length: length(call_notes),
      response_length: length(response_notes),
      notes_matched: count_matched_notes(call_notes, response_notes, opts),
      total_notes: max(length(call_notes), length(response_notes))
    }
  end

  ## Private Functions

  defp normalize_pattern(pattern) when is_list(pattern) do
    Enum.map(pattern, fn note ->
      %{
        midi: Map.get(note, :midi) || Map.get(note, "midi"),
        timestamp: Map.get(note, :timestamp) || Map.get(note, "timestamp") || 0,
        duration: Map.get(note, :duration) || Map.get(note, "duration") || 500,
        velocity: Map.get(note, :velocity) || Map.get(note, "velocity") || 64
      }
    end)
  end

  defp note_score(call_note, response_note, timing_tolerance, pitch_tolerance) do
    pitch_diff = abs(call_note.midi - response_note.midi)
    pitch_score = if pitch_diff <= pitch_tolerance do
      1.0
    else
      max(0.0, 1.0 - (pitch_diff - pitch_tolerance) / 12.0)
    end
    
    timing_diff = abs(call_note.timestamp - response_note.timestamp)
    timing_score = if timing_diff <= timing_tolerance do
      1.0
    else
      max(0.0, 1.0 - (timing_diff - timing_tolerance) / 1000.0)
    end
    
    duration_diff = abs(call_note.duration - response_note.duration)
    duration_score = if duration_diff <= timing_tolerance do
      1.0
    else
      max(0.0, 1.0 - duration_diff / 1000.0)
    end
    
    (pitch_score * 0.5) + (timing_score * 0.3) + (duration_score * 0.2)
  end

  defp count_matched_notes(call_notes, response_notes, opts) do
    timing_tolerance = Keyword.get(opts, :timing_tolerance_ms, 200)
    pitch_tolerance = Keyword.get(opts, :pitch_tolerance_semitones, 0)
    
    pairs = Enum.zip(call_notes, response_notes)
    
    Enum.count(pairs, fn {call_note, response_note} ->
      pitch_diff = abs(call_note.midi - response_note.midi)
      timing_diff = abs(call_note.timestamp - response_note.timestamp)
      pitch_diff <= pitch_tolerance and timing_diff <= timing_tolerance
    end)
  end
end
```

#### High-Value Tests
See `docs/IMPLEMENTATION_TESTS.md` → **Phase 4.1**

---

### Subphase 4.2: Integrate Pattern Matching into SessionManager

#### Tasks
- [ ] Add functions to store call patterns
- [ ] Add functions to record student responses
- [ ] Add functions to validate responses

#### Files to Modify

**`lib/extensions/music/session_manager.ex`** - Add pattern matching:

```elixir
alias Realtime.Music.PatternMatcher

@doc """
Set call pattern for Call and Response game.
"""
def set_call_pattern(room_id, tenant_id, pattern) when is_list(pattern) do
  GenServer.call(__MODULE__, {:set_call_pattern, room_id, tenant_id, pattern})
end

@doc """
Record student response to call pattern.
"""
def record_response(room_id, tenant_id, student_id, response_pattern) when is_list(response_pattern) do
  GenServer.call(__MODULE__, {:record_response, room_id, tenant_id, student_id, response_pattern})
end

@doc """
Validate student response against call pattern.
"""
def validate_response(room_id, tenant_id, student_id, opts \\ []) do
  GenServer.call(__MODULE__, {:validate_response, room_id, tenant_id, student_id, opts})
end

@doc """
Get all response validations for a room.
"""
def get_response_validations(room_id, tenant_id) do
  GenServer.call(__MODULE__, {:get_response_validations, room_id, tenant_id})
end

# Add to handle_call:

@impl true
def handle_call({:set_call_pattern, room_id, tenant_id, pattern}, _from, state) do
  case Map.get(state, room_id) do
    nil ->
      {:reply, {:error, :not_found}, state}
    
    room ->
      if room.tenant_id == tenant_id do
        updated_game_state = Map.put(room.game_state, :call_pattern, pattern)
        updated_game_state = Map.put(updated_game_state, :responses, %{})
        updated_room = %{room | game_state: updated_game_state}
        
        {:reply, :ok, Map.put(state, room_id, updated_room)}
      else
        {:reply, {:error, :unauthorized}, state}
      end
  end
end

@impl true
def handle_call({:record_response, room_id, tenant_id, student_id, response_pattern}, _from, state) do
  case Map.get(state, room_id) do
    nil ->
      {:reply, {:error, :not_found}, state}
    
    room ->
      if room.tenant_id == tenant_id do
        responses = Map.get(room.game_state, :responses, %{})
        updated_responses = Map.put(responses, student_id, response_pattern)
        
        updated_game_state = Map.put(room.game_state, :responses, updated_responses)
        updated_room = %{room | game_state: updated_game_state}
        
        {:reply, :ok, Map.put(state, room_id, updated_room)}
      else
        {:reply, {:error, :unauthorized}, state}
      end
  end
end

@impl true
def handle_call({:validate_response, room_id, tenant_id, student_id, opts}, _from, state) do
  case Map.get(state, room_id) do
    nil ->
      {:reply, {:error, :not_found}, state}
    
    room ->
      if room.tenant_id == tenant_id do
        call_pattern = Map.get(room.game_state, :call_pattern)
        responses = Map.get(room.game_state, :responses, %{})
        response_pattern = Map.get(responses, student_id)
        
        cond do
          is_nil(call_pattern) ->
            {:reply, {:error, :no_call_pattern}, state}
          
          is_nil(response_pattern) ->
            {:reply, {:error, :no_response}, state}
          
          true ->
            feedback = PatternMatcher.feedback(call_pattern, response_pattern, opts)
            
            # Store validation result
            validations = Map.get(room.game_state, :validations, %{})
            updated_validations = Map.put(validations, student_id, feedback)
            
            updated_game_state = Map.put(room.game_state, :validations, updated_validations)
            updated_room = %{room | game_state: updated_game_state}
            
            {:reply, {:ok, feedback}, Map.put(state, room_id, updated_room)}
        end
      else
        {:reply, {:error, :unauthorized}, state}
      end
  end
end

@impl true
def handle_call({:get_response_validations, room_id, tenant_id}, _from, state) do
  case Map.get(state, room_id) do
    nil ->
      {:reply, {:error, :not_found}, state}
    
    room ->
      if room.tenant_id == tenant_id do
        validations = Map.get(room.game_state, :validations, %{})
        {:reply, {:ok, validations}, state}
      else
        {:reply, {:error, :unauthorized}, state}
      end
  end
end
```

#### High-Value Tests
See `docs/IMPLEMENTATION_TESTS.md` → **Phase 4.2**

---

## Phase 5: Game-Specific Features (Day 10-13)

### Goal
Implement game-specific channel events and state management for each of the 5 games.

### Subphase 5.1: Rhythm Circle Enhancements

#### Tasks
- [ ] Add `assign_pattern`, `pattern_start` channel events
- [ ] Add `pattern_beat` broadcast
- [ ] Update beat handler to broadcast pattern beats

#### Files to Modify

**`lib/realtime_web/channels/music_room_channel.ex`** - Add Rhythm Circle handlers:

```elixir
def handle_in("assign_pattern", %{"student_id" => student_id, "pattern" => pattern}, socket) do
  if is_teacher?(socket) do
    room_id = socket.assigns.room_id
    tenant_id = socket.assigns.tenant_id
    
    :ok = SessionManager.update_game_state(room_id, tenant_id, %{
      pattern_assignments: %{student_id => pattern}
    })
    
    broadcast!(socket, "pattern_assigned", %{student_id: student_id, pattern: pattern})
    {:reply, :ok, socket}
  else
    {:reply, {:error, %{reason: "unauthorized"}}, socket}
  end
end

# Update beat handler
def handle_info({:beat, beat_number}, socket) do
  room_id = socket.assigns.room_id
  tenant_id = socket.assigns.tenant_id
  
  {:ok, game_state} = SessionManager.get_game_state(room_id, tenant_id)
  
  if game_state.game_type == :rhythm_circle and 
     Map.get(game_state.game_state, :pattern_state) == :active do
    :ok = SessionManager.update_game_state(room_id, tenant_id, %{
      pattern_current_beat: beat_number
    })
    push(socket, "pattern_beat", %{beat: beat_number})
  end
  
  push(socket, "beat", %{beat: beat_number})
  {:noreply, socket}
end
```

#### High-Value Tests
See `docs/IMPLEMENTATION_TESTS.md` → **Phase 5.1**

---

### Subphase 5.2: Melody Builder Implementation

#### Tasks
- [ ] Add `start_melody`, `add_note`, `play_melody` channel events
- [ ] Store melody sequence in game_state
- [ ] Enforce turn-taking for note additions
- [ ] ✅ FIX: Use dedicated GenServer for pattern playback instead of channel process

#### Files to Modify

**`lib/realtime_web/channels/music_room_channel.ex`** - Add Melody Builder handlers:

```elixir
def handle_in("start_melody", _payload, socket) do
  if is_teacher?(socket) do
    room_id = socket.assigns.room_id
    tenant_id = socket.assigns.tenant_id
    {:ok, room} = SessionManager.get_room(room_id)
    
    :ok = SessionManager.start_turn_rotation(room_id, tenant_id, room.students, 60)
    :ok = SessionManager.update_game_state(room_id, tenant_id, %{
      melody_sequence: [],
      melody_state: :building
    })
    
    broadcast!(socket, "melody_started", %{})
    {:reply, :ok, socket}
  else
    {:reply, {:error, %{reason: "unauthorized"}}, socket}
  end
end

def handle_in("add_note", %{"midi" => midi, "velocity" => velocity}, socket) do
  room_id = socket.assigns.room_id
  tenant_id = socket.assigns.tenant_id
  student_id = socket.assigns.student_id
  
  {:ok, turn_info} = SessionManager.get_current_turn(room_id, tenant_id)
  
  if turn_info.current_turn == student_id do
    {:ok, game_state} = SessionManager.get_game_state(room_id, tenant_id)
    melody_sequence = Map.get(game_state.game_state, :melody_sequence, [])
    
    new_note = %{
      midi: midi,
      velocity: velocity,
      student_id: student_id,
      timestamp: System.system_time(:millisecond),
      position: length(melody_sequence)
    }
    
    updated_melody = melody_sequence ++ [new_note]
    :ok = SessionManager.update_game_state(room_id, tenant_id, %{melody_sequence: updated_melody})
    
    broadcast!(socket, "note_added", %{note: new_note, melody_length: length(updated_melody)})
    
    {:ok, _} = SessionManager.advance_turn(room_id, tenant_id)
    :ok = SessionManager.start_current_turn(room_id, tenant_id)
    {:ok, next_turn_info} = SessionManager.get_current_turn(room_id, tenant_id)
    
    broadcast!(socket, "turn_advanced", next_turn_info)
    {:reply, :ok, socket}
  else
    {:reply, {:error, %{reason: "not_your_turn", current_turn: turn_info.current_turn}}, socket}
  end
end

# ✅ FIX: Use tempo server beats or dedicated GenServer for playback
# See MUSIC_GAMES_PLAN_REVIEW.md issue #3 for better approach
def handle_in("play_melody", _payload, socket) do
  if is_teacher?(socket) do
    # Implementation: Use PatternPlayer GenServer or tempo server beats
    # (See review document for recommended approach)
  end
end
```

#### High-Value Tests
See `docs/IMPLEMENTATION_TESTS.md` → **Phase 5.2**

---

### Subphase 5.3: Dynamics Dance Implementation

#### Tasks
- [ ] Add `set_dynamic_pattern`, `set_dynamic_goal` channel events
- [ ] Update `play_note` to track volume feedback
- [ ] Store dynamic goals in game_state

#### Files to Modify

**`lib/realtime_web/channels/music_room_channel.ex`** - Add Dynamics Dance handlers:

```elixir
def handle_in("set_dynamic_pattern", %{"pattern" => pattern}, socket) do
  if is_teacher?(socket) do
    room_id = socket.assigns.room_id
    tenant_id = socket.assigns.tenant_id
    
    valid_dynamics = ["p", "mp", "mf", "f", "pp", "ff"]
    if Enum.all?(pattern, &(&1 in valid_dynamics)) do
      :ok = SessionManager.update_game_state(room_id, tenant_id, %{
        dynamic_pattern: pattern,
        dynamic_current_index: 0
      })
      broadcast!(socket, "dynamic_pattern_set", %{pattern: pattern})
    {:reply, :ok, socket}
    else
      {:reply, {:error, %{reason: "invalid_dynamic_pattern"}}, socket}
    end
  else
    {:reply, {:error, %{reason: "unauthorized"}}, socket}
  end
end

def handle_in("set_dynamic_goal", %{"dynamic" => dynamic}, socket) do
  if is_teacher?(socket) do
    room_id = socket.assigns.room_id
    tenant_id = socket.assigns.tenant_id
    
    velocity_range = case dynamic do
      "pp" -> {20, 30}
      "p" -> {40, 50}
      "mp" -> {60, 70}
      "mf" -> {80, 90}
      "f" -> {100, 110}
      "ff" -> {120, 127}
      _ -> {64, 64}
    end
    
    :ok = SessionManager.update_game_state(room_id, tenant_id, %{
      dynamic_goal: dynamic,
      dynamic_velocity_range: velocity_range
    })
    
    broadcast!(socket, "dynamic_goal_set", %{dynamic: dynamic, velocity_range: velocity_range})
    {:reply, :ok, socket}
  else
    {:reply, {:error, %{reason: "unauthorized"}}, socket}
  end
end

# Update play_note to provide volume feedback
# (Add after existing play_note handler - check if Dynamics Dance is active)
```

#### High-Value Tests
See `docs/IMPLEMENTATION_TESTS.md` → **Phase 5.3**

---

### Subphase 5.4: Improvisation Jam Implementation

#### Tasks
- [ ] Add `start_improvisation`, `request_solo`, `assign_solo`, `end_solo` events
- [ ] Add solo timer tracking
- [ ] Implement solo mode (only soloist can play)

#### Files to Modify

**`lib/realtime_web/channels/music_room_channel.ex`** - Add Improvisation Jam handlers:

```elixir
def handle_in("start_improvisation", %{"solo_duration_seconds" => duration}, socket) do
  if is_teacher?(socket) do
    room_id = socket.assigns.room_id
    tenant_id = socket.assigns.tenant_id
    {:ok, room} = SessionManager.get_room(room_id)
    
    :ok = SessionManager.start_turn_rotation(room_id, tenant_id, room.students, duration)
    :ok = SessionManager.update_game_state(room_id, tenant_id, %{
      improvisation_state: :waiting,
      current_soloist: nil,
      solo_queue: room.students
    })
    
    broadcast!(socket, "improvisation_started", %{solo_duration: duration})
    {:reply, :ok, socket}
  else
    {:reply, {:error, %{reason: "unauthorized"}}, socket}
  end
end

# Add handlers for request_solo, assign_solo, end_solo
# Update play_note to enforce solo mode
# (See MUSIC_GAMES_IMPLEMENTATION_PLAN.md Phase 4 Subphase 4.4 for full code)
```

#### High-Value Tests
See `docs/IMPLEMENTATION_TESTS.md` → **Phase 5.4**

---

### Subphase 5.5: Call and Response Implementation

#### Tasks
- [ ] Add `play_call`, `record_response`, `validate_response` events
- [ ] Add `response_feedback` broadcast
- [ ] Integrate with PatternMatcher

#### Files to Modify

**`lib/realtime_web/channels/music_room_channel.ex`** - Add Call and Response handlers:

```elixir
def handle_in("play_call", %{"pattern" => pattern}, socket) do
  if is_teacher?(socket) do
    room_id = socket.assigns.room_id
    tenant_id = socket.assigns.tenant_id
    
    :ok = SessionManager.set_call_pattern(room_id, tenant_id, pattern)
    
    # ✅ FIX: Use dedicated GenServer for pattern playback
    # Create PatternPlayer or use tempo server beats
    pattern_obj = Realtime.Music.Pattern.create("Call", pattern)
    # Schedule playback via GenServer, not channel process
    
    :ok = SessionManager.update_game_state(room_id, tenant_id, %{
      response_state: :recording_responses
    })
    
    broadcast!(socket, "call_playing", %{pattern: pattern})
    {:reply, :ok, socket}
  else
    {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

def handle_in("record_response", %{"response" => response_pattern}, socket) do
  room_id = socket.assigns.room_id
  tenant_id = socket.assigns.tenant_id
  student_id = socket.assigns.student_id
  
  :ok = SessionManager.record_response(room_id, tenant_id, student_id, response_pattern)
  broadcast!(socket, "response_recorded", %{student_id: student_id})
  {:reply, :ok, socket}
end

def handle_in("validate_response", %{"student_id" => student_id}, socket) do
  if is_teacher?(socket) do
    room_id = socket.assigns.room_id
    tenant_id = socket.assigns.tenant_id
    
    case SessionManager.validate_response(room_id, tenant_id, student_id) do
      {:ok, feedback} ->
        broadcast!(socket, "response_feedback", %{student_id: student_id, feedback: feedback})
        {:reply, {:ok, feedback}, socket}
      error ->
        {:reply, {:error, %{reason: inspect(error)}}, socket}
    end
  else
    {:reply, {:error, %{reason: "unauthorized"}}, socket}
  end
end
```

#### High-Value Tests
See `docs/IMPLEMENTATION_TESTS.md` → **Phase 5.5**

---

## Phase 6: Database Schema & Persistence (Day 14-15)

### Goal
Add database tables for pattern storage and game session persistence.

### Subphase 6.1: Create Music Patterns Table

#### Tasks
- [ ] Create migration for `music_patterns` table
- [ ] Add Ecto schema for `MusicPattern`
- [ ] Add pattern serialization/deserialization to Pattern module

#### Files to Create

**`priv/repo/migrations/YYYYMMDDHHMMSS_create_music_patterns_table.exs`**:

```elixir
defmodule Realtime.Repo.Migrations.CreateMusicPatternsTable do
  use Ecto.Migration

  def change do
    create table(:music_patterns, prefix: "_realtime") do
      add :id, :binary_id, primary_key: true
      add :room_id, :string
      add :tenant_id, :string, null: false
      add :pattern_type, :string, null: false
      add :pattern_data, :map, null: false
      add :name, :string
      add :time_signature, :string
      add :tempo, :integer
      add :created_by, :string
      timestamps()
    end

    create index(:music_patterns, [:room_id, :tenant_id], prefix: "_realtime")
    create index(:music_patterns, [:tenant_id, :pattern_type], prefix: "_realtime")
  end
end
```

**`lib/extensions/music/schemas/music_pattern.ex`**:

```elixir
defmodule Realtime.Music.Schemas.MusicPattern do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "music_patterns", prefix: "_realtime" do
    field :room_id, :string
    field :tenant_id, :string
    field :pattern_type, :string
    field :pattern_data, :map
    field :name, :string
    field :time_signature, :string
    field :tempo, :integer
    field :created_by, :string
    timestamps()
  end

  def changeset(pattern, attrs) do
    pattern
    |> cast(attrs, [:room_id, :tenant_id, :pattern_type, :pattern_data, :name, :time_signature, :tempo, :created_by])
    |> validate_required([:tenant_id, :pattern_type, :pattern_data])
    |> validate_inclusion(:pattern_type, ["rhythm", "melody", "call"])
  end
end
```

**Update `lib/extensions/music/pattern.ex`** - Add serialization:

```elixir
# Add to Pattern module:
@doc """
Convert pattern to map for database storage.
"""
def to_map(pattern) do
  %{
    id: pattern.id,
    name: pattern.name,
    notes: pattern.notes,
    time_signature: pattern.time_signature,
    tempo: pattern.tempo,
    pattern_type: Atom.to_string(pattern.pattern_type),
    created_at: pattern.created_at
  }
end

@doc """
Reconstruct pattern from map.
"""
def from_map(map) do
  %__MODULE__{
    id: map.id,
    name: map.name,
    notes: map.notes,
    time_signature: map.time_signature,
    tempo: map.tempo,
    pattern_type: String.to_existing_atom(map.pattern_type),
    created_at: map.created_at
  }
end
```

#### High-Value Tests
See `docs/IMPLEMENTATION_TESTS.md` → **Phase 6.1**

---

### Subphase 6.2: Create Game Sessions Table

#### Tasks
- [ ] Create migration for `game_sessions` table
- [ ] Add Ecto schema for `GameSession`
- [ ] Implement session persistence functions

#### Files to Create

**`priv/repo/migrations/YYYYMMDDHHMMSS_create_game_sessions_table.exs`**:

```elixir
defmodule Realtime.Repo.Migrations.CreateGameSessionsTable do
  use Ecto.Migration

  def change do
    create table(:game_sessions, prefix: "_realtime") do
      add :id, :binary_id, primary_key: true
      add :room_id, :string, null: false
      add :tenant_id, :string, null: false
      add :game_type, :string, null: false
      add :game_state, :map, null: false
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      timestamps()
    end

    create index(:game_sessions, [:room_id, :tenant_id], prefix: "_realtime")
    create index(:game_sessions, [:tenant_id, :game_type], prefix: "_realtime")
    create index(:game_sessions, [:started_at], prefix: "_realtime")
  end
end
```

**`lib/extensions/music/schemas/game_session.ex`**:

```elixir
defmodule Realtime.Music.Schemas.GameSession do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "game_sessions", prefix: "_realtime" do
    field :room_id, :string
    field :tenant_id, :string
    field :game_type, :string
    field :game_state, :map
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    timestamps()
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:room_id, :tenant_id, :game_type, :game_state, :started_at, :completed_at])
    |> validate_required([:room_id, :tenant_id, :game_type, :game_state])
    |> validate_inclusion(:game_type, ["rhythm_circle", "melody_builder", "dynamics_dance", "improvisation_jam", "call_and_response"])
  end
end
```

#### Files to Modify

**`lib/extensions/music/session_manager.ex`** - Add persistence:

```elixir
alias Realtime.Music.Schemas.GameSession
alias Realtime.Repo

@doc """
Save current game session to database (async, non-blocking).
"""
def save_game_session(room_id, tenant_id) do
  Task.start(fn ->
    case get_room(room_id) do
      {:ok, room} ->
        if room.tenant_id == tenant_id and not is_nil(room.game_type) do
          changeset = GameSession.changeset(%GameSession{}, %{
            room_id: room_id,
            tenant_id: tenant_id,
            game_type: Atom.to_string(room.game_type),
            game_state: room.game_state,
            started_at: DateTime.utc_now()
          })
          case Repo.insert(changeset) do
            {:ok, _session} -> :ok
            {:error, _changeset} -> :error
  end
end
      _ -> :error
    end
  end)
  :ok
end

@doc """
Load game sessions for a room.
"""
def get_game_sessions(room_id, tenant_id) do
  import Ecto.Query
  query = from gs in GameSession,
    where: gs.room_id == ^room_id and gs.tenant_id == ^tenant_id,
    order_by: [desc: gs.started_at]
  Repo.all(query)
end
```

#### High-Value Tests
See `docs/IMPLEMENTATION_TESTS.md` → **Phase 6.2**

---

## Phase 7: Integration & Polish (Day 16-17)

### Goal
Integrate all components, add error handling, documentation, and comprehensive testing.

### Subphase 7.1: Error Handling & Validation

#### Tasks
- [ ] Add validation for all channel events
- [ ] Add error handling for edge cases
- [ ] Add rate limiting for new events
- [ ] Add authorization checks for all teacher-only events

#### Files to Modify

**`lib/realtime_web/channels/music_room_channel.ex`** - Add error handling:

```elixir
# Add helper function for validation
defp validate_game_active(socket, required_game_type) do
  room_id = socket.assigns.room_id
  tenant_id = socket.assigns.tenant_id
  
  case SessionManager.get_game_state(room_id, tenant_id) do
    {:ok, %{game_type: game_type}} when game_type == required_game_type -> :ok
    {:ok, %{game_type: nil}} -> {:error, :no_game_active}
    {:ok, %{game_type: other}} -> {:error, {:wrong_game_type, other}}
    error -> error
  end
end

# Use in handlers:
def handle_in("add_note", %{"midi" => midi, "velocity" => velocity}, socket) do
  case validate_game_active(socket, :melody_builder) do
    :ok -> # ... existing logic ...
    {:error, :no_game_active} ->
      {:reply, {:error, %{reason: "no_game_active"}}, socket}
    {:error, {:wrong_game_type, _}} ->
      {:reply, {:error, %{reason: "wrong_game_type"}}, socket}
  end
end
```

#### High-Value Tests
See `docs/IMPLEMENTATION_TESTS.md` → **Phase 7.1**

---

### Subphase 7.2: Documentation

#### Tasks
- [ ] Add module docs to all new modules
- [ ] Add function docs with examples
- [ ] Document all new channel events
- [ ] Update API documentation

### Subphase 7.3: Comprehensive Testing

#### Tasks
- [ ] Create unit tests for all new modules
- [ ] Create integration tests for each game
- [ ] Test error cases and edge cases
- [ ] Test backward compatibility

#### High-Value Tests
See `docs/IMPLEMENTATION_TESTS.md` → **Phase 7**

---

## Success Criteria

### Must Have (MVP)
- ✅ Authorization security fix (JWT role extraction)
- ✅ Tempo timing drift fix
- ✅ Room cleanup mechanism
- ✅ Volume/dynamics support (velocity in play_note)
- ✅ Game state management (game_type, game_state)
- ✅ Pattern storage module (Pattern)
- ✅ Turn management (TurnManager)
- ✅ Pattern matching (PatternMatcher)
- ✅ Channel events for all 5 games
- ✅ Database persistence (patterns, game sessions)
- ✅ All tests passing

### Nice to Have
- ✅ Comprehensive error handling
- ✅ Performance optimization
- ✅ Full documentation
- ✅ Async game session persistence

---

## Estimated Timeline

- **Phase 1**: 2 days (security & remaining work fixes)
- **Phase 2**: 3 days (foundation infrastructure)
- **Phase 3**: 2 days (turn management)
- **Phase 4**: 2 days (pattern matching)
- **Phase 5**: 4 days (game-specific features)
- **Phase 6**: 2 days (database schema)
- **Phase 7**: 2 days (integration & polish)

**Total: 17 days**

---

## Notes

- **Backward Compatibility**: All changes maintain backward compatibility with existing music extension
- **Multi-tenant**: All new features properly isolate by `tenant_id`
- **Rate Limiting**: Existing rate limiting applies to all note-playing events
- **Security**: Role now extracted from JWT claims (fixed in Phase 1)
- **Fixes Applied**: All fixes from `MUSIC_GAMES_PLAN_REVIEW.md` are incorporated

---

**Remember:** Reference `docs/IMPLEMENTATION_TESTS.md` for detailed test examples and patterns.
