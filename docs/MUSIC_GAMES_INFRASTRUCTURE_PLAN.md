# Music Games Infrastructure Plan

## Overview

This document outlines the infrastructure features needed to support all 5 planned music education games:
1. **Rhythm Circle** - Structured rhythm exercises with beat assignments
2. **Melody Builder** - Collaborative melody construction
3. **Dynamics Dance** - Volume and dynamic expression exercises
4. **Improvisation Jam** - Turn-taking and solo improvisation
5. **Call and Response** - Pattern matching and response exercises

---

## Current Infrastructure Status

### ✅ Already Implemented
- **Basic note playing** - Students can play MIDI notes, broadcast to all
- **Tempo synchronization** - Shared tempo clock with beat broadcasting
- **Beat assignments** - Teachers can assign specific beats to students
- **Rate limiting** - Prevents abuse (10 notes/sec students, 50/sec teachers)
- **Session management** - Room creation, join codes, student tracking
- **SEL data collection** - Participation events, reflections, analytics
- **Teacher controls** - Tempo adjustment, student muting

### ❌ Missing for Full Game Support
- Volume/dynamics control
- Note sequences and patterns
- Turn-taking and solo modes
- Pattern matching and validation
- Game state management
- Role assignment (beyond teacher/student)
- Rhythm pattern storage and playback
- Harmony/chord support

---

## Game-Specific Requirements

### 1. Rhythm Circle

**Game Description**: Students play assigned beats in a structured rhythm pattern. Teacher assigns specific beats to specific students, creating a coordinated rhythm exercise.

**Current Support**: ✅ Beat assignments (implemented)

**Additional Needs**:
- **Rhythm Pattern Storage**: Store predefined rhythm patterns (e.g., "4/4 time, beats 1, 2, 3, 4")
- **Pattern Assignment**: Assign entire patterns to students (not just single beats)
- **Visual Feedback**: Broadcast which beat is currently active
- **Pattern Validation**: Track if students play on their assigned beats correctly

**Infrastructure Changes**:
```elixir
# New channel events
"assign_pattern" - Teacher assigns a rhythm pattern to a student
"pattern_start" - Start a rhythm pattern exercise
"pattern_beat" - Broadcast current beat in pattern (1, 2, 3, 4...)
"pattern_complete" - Pattern finished, show results

# New SessionManager functions
assign_pattern(room_id, student_id, pattern_id)
get_active_pattern(room_id)
validate_beat_timing(room_id, student_id, beat_number, timestamp)
```

---

### 2. Melody Builder

**Game Description**: Students collaboratively build a melody by taking turns adding notes. Each student adds one note at a time, creating a shared melody.

**Current Support**: ✅ Basic note playing

**Additional Needs**:
- **Note Sequence Storage**: Store the growing melody as a sequence of notes
- **Turn Management**: Track whose turn it is to add a note
- **Melody History**: Maintain history of who added which note
- **Melody Playback**: Play back the complete melody
- **Harmony Support**: Allow multiple students to play simultaneously (harmony)

**Infrastructure Changes**:
```elixir
# New channel events
"start_melody" - Begin a new melody building session
"add_note" - Student adds a note to the melody (turn-based)
"request_turn" - Student requests to add next note
"melody_complete" - Melody finished, play it back
"play_melody" - Play back the complete melody

# New SessionManager state
melody_sequence: [%{note: 60, student_id: "s1", timestamp: ...}, ...]
current_turn: "student-2"
melody_state: :building | :complete | :playing

# New functions
add_note_to_melody(room_id, student_id, midi_note)
get_melody(room_id)
play_melody(room_id)
```

---

### 3. Dynamics Dance

**Game Description**: Students practice dynamic expression (volume changes) by playing notes at different volumes. Teacher sets dynamic goals (e.g., "play softly, then loudly").

**Current Support**: ❌ No volume/dynamics support

**Additional Needs**:
- **Volume Control**: Each note play includes velocity/volume (0-127)
- **Dynamic Patterns**: Store patterns like "piano → forte → piano"
- **Volume Feedback**: Track and display volume levels
- **Dynamic Goals**: Teacher sets target dynamics for students

**Infrastructure Changes**:
```elixir
# Update existing "play_note" event
"play_note" - Add velocity field: %{midi: 60, velocity: 80}

# New channel events
"set_dynamic_pattern" - Teacher sets a dynamic pattern (p, mp, mf, f)
"dynamic_goal" - Teacher sets target dynamic for next note
"volume_feedback" - Broadcast volume level of played note

# Update SelTracker
log_participation(..., event_data: %{midi: 60, velocity: 80})
```

---

### 4. Improvisation Jam

**Game Description**: Students take turns improvising solos while others provide accompaniment. Rotates leadership, encourages creativity and turn-taking.

**Current Support**: ❌ No turn-taking or solo modes

**Additional Needs**:
- **Turn Management**: Track whose turn it is to solo
- **Solo Mode**: Allow one student to play while others listen/accompany
- **Accompaniment Mode**: Others play background/accompaniment
- **Turn Rotation**: Automatically rotate solo turns
- **Solo Timer**: Limit solo duration (e.g., 30 seconds)

**Infrastructure Changes**:
```elixir
# New channel events
"start_improvisation" - Begin improvisation session
"request_solo" - Student requests solo turn
"assign_solo" - Teacher assigns solo to student
"end_solo" - Current solo ends, rotate to next
"solo_timer" - Broadcast remaining solo time

# New SessionManager state
improvisation_state: :waiting | :solo_active
current_soloist: "student-3"
solo_queue: ["student-1", "student-2", ...]
solo_start_time: timestamp
solo_duration_seconds: 30

# New functions
start_improvisation(room_id, solo_duration_seconds)
assign_solo(room_id, student_id)
end_solo(room_id)
rotate_solo(room_id)
```

---

### 5. Call and Response

**Game Description**: Teacher plays a pattern (call), students respond with the same or similar pattern. Teaches pattern recognition and imitation.

**Current Support**: ❌ No pattern matching or validation

**Additional Needs**:
- **Pattern Storage**: Store the "call" pattern (sequence of notes)
- **Pattern Playback**: Play back the call pattern to all students
- **Response Validation**: Compare student responses to the call pattern
- **Pattern Matching**: Determine if response matches call (exact or approximate)
- **Response Feedback**: Provide feedback on accuracy

**Infrastructure Changes**:
```elixir
# New channel events
"play_call" - Teacher plays the call pattern
"record_response" - Student records their response
"validate_response" - Validate student response against call
"response_feedback" - Broadcast feedback (correct/incorrect, accuracy %)

# New SessionManager state
call_pattern: [%{midi: 60, duration: 500}, %{midi: 62, duration: 500}, ...]
responses: %{"student-1" => [notes...], "student-2" => [notes...]}
response_state: :waiting_call | :recording_responses | :validating

# New functions
set_call_pattern(room_id, pattern)
record_response(room_id, student_id, response_notes)
validate_response(room_id, student_id)
get_response_accuracy(room_id, student_id)
```

---

## Common Infrastructure Needs

### 1. Game State Management

**Problem**: Each game has different state (melody sequence, solo queue, call pattern, etc.). Need a flexible way to store game-specific state.

**Solution**: Add `game_type` and `game_state` to room state in `SessionManager`.

```elixir
# Update room state
%{
  room_id: room_id,
  game_type: :rhythm_circle | :melody_builder | :dynamics_dance | :improvisation_jam | :call_and_response,
  game_state: %{
    # Game-specific state (varies by game_type)
    melody_sequence: [...],
    current_turn: "student-2",
    # etc.
  }
}
```

**Implementation**:
- Add `set_game_type/2` to `SessionManager`
- Add `update_game_state/3` to `SessionManager`
- Add `get_game_state/1` to `SessionManager`

---

### 2. Volume/Dynamics Support

**Problem**: Current `play_note` only includes MIDI note, no volume/velocity.

**Solution**: Add `velocity` field to note events (0-127, standard MIDI velocity).

**Implementation**:
- Update `handle_in("play_note")` in `MusicRoomChannel` to accept `velocity`
- Update `SelTracker.log_participation` to include velocity
- Update analytics to track dynamic expression

---

### 3. Note Sequence Storage

**Problem**: Need to store sequences of notes (melodies, patterns, calls) with timing information.

**Solution**: Create `Realtime.Music.Pattern` module for pattern storage and playback.

```elixir
defmodule Realtime.Music.Pattern do
  @moduledoc """
  Stores and manages musical patterns (sequences of notes with timing).
  """

  defstruct [
    :id,
    :name,
    :notes,  # [%{midi: 60, duration: 500, velocity: 80}, ...]
    :time_signature,  # "4/4"
    :tempo,  # BPM
    :created_at
  ]

  def create(name, notes, opts \\ []) do
    %__MODULE__{
      id: generate_id(),
      name: name,
      notes: notes,
      time_signature: Keyword.get(opts, :time_signature, "4/4"),
      tempo: Keyword.get(opts, :tempo, 120),
      created_at: DateTime.utc_now()
    }
  end

  def play(pattern, tempo_server) do
    # Schedule each note according to pattern timing
    # Broadcast notes at correct intervals
  end
end
```

---

### 4. Turn Management

**Problem**: Multiple games need turn-taking (Melody Builder, Improvisation Jam).

**Solution**: Create `Realtime.Music.TurnManager` module.

```elixir
defmodule Realtime.Music.TurnManager do
  @moduledoc """
  Manages turn-taking for games that require sequential actions.
  """

  defstruct [
    :current_turn,
    :queue,
    :turn_duration_seconds,
    :turn_start_time,
    :turn_state  # :waiting | :active | :completed
  ]

  def start_turn_rotation(student_ids, turn_duration_seconds \\ 30) do
    %__MODULE__{
      current_turn: List.first(student_ids),
      queue: List.delete(student_ids, List.first(student_ids)),
      turn_duration_seconds: turn_duration_seconds,
      turn_start_time: nil,
      turn_state: :waiting
    }
  end

  def next_turn(turn_manager) do
    # Rotate to next student
  end

  def get_current_turn(turn_manager) do
    turn_manager.current_turn
  end

  def time_remaining(turn_manager) do
    # Calculate remaining time for current turn
  end
end
```

---

### 5. Pattern Matching/Validation

**Problem**: Call and Response needs to compare student responses to teacher's call pattern.

**Solution**: Create `Realtime.Music.PatternMatcher` module.

```elixir
defmodule Realtime.Music.PatternMatcher do
  @moduledoc """
  Compares musical patterns for similarity/accuracy.
  """

  def match?(call_pattern, response_pattern, tolerance \\ 2) do
    # Compare note sequences
    # Allow for timing variations (tolerance in milliseconds)
    # Allow for slight pitch variations (tolerance in semitones)
    # Return accuracy percentage
  end

  def accuracy(call_pattern, response_pattern) do
    # Calculate accuracy percentage (0-100)
    # Consider: note matching, timing accuracy, rhythm matching
  end
end
```

---

## Implementation Priority

### Phase 1: Foundation (High Priority)
1. **Volume/Dynamics Support** - Required for Dynamics Dance
2. **Game State Management** - Required for all games
3. **Note Sequence Storage** - Required for Melody Builder, Call and Response

### Phase 2: Turn Management (Medium Priority)
4. **Turn Management Module** - Required for Melody Builder, Improvisation Jam
5. **Solo Mode Support** - Required for Improvisation Jam

### Phase 3: Pattern Matching (Lower Priority)
6. **Pattern Matching** - Required for Call and Response
7. **Rhythm Pattern Storage** - Enhancement for Rhythm Circle

---

## Database Schema Updates

### New Tables

**`music_patterns`** (for storing predefined patterns):
```elixir
create table(:music_patterns, prefix: "_realtime") do
  add :id, :binary_id, primary_key: true
  add :room_id, :string
  add :tenant_id, :string
  add :pattern_type, :string  # "rhythm", "melody", "call"
  add :pattern_data, :map  # JSONB: {notes: [...], timing: [...]}
  add :name, :string
  timestamps()
end
```

**`game_sessions`** (for tracking game-specific state):
```elixir
create table(:game_sessions, prefix: "_realtime") do
  add :id, :binary_id, primary_key: true
  add :room_id, :string
  add :tenant_id, :string
  add :game_type, :string
  add :game_state, :map  # JSONB: flexible game state
  add :started_at, :utc_datetime
  add :completed_at, :utc_datetime
  timestamps()
end
```

---

## API Changes

### Channel Events (New/Updated)

**Updated Events**:
- `play_note` - Add `velocity` field (0-127)

**New Events**:
- `set_game_type` - Teacher sets current game type
- `start_melody` - Begin melody building
- `add_note` - Add note to melody (turn-based)
- `request_solo` - Request solo turn
- `assign_solo` - Teacher assigns solo
- `play_call` - Play call pattern
- `record_response` - Record response to call
- `set_dynamic_pattern` - Set dynamic pattern
- `assign_pattern` - Assign rhythm pattern to student

### HTTP API Endpoints (New)

- `POST /api/music/rooms/:room_id/games/start` - Start a game
- `GET /api/music/rooms/:room_id/games/state` - Get current game state
- `POST /api/music/rooms/:room_id/patterns` - Create a pattern
- `GET /api/music/rooms/:room_id/patterns` - List patterns for room

---

## Testing Strategy

### Unit Tests
- `Realtime.Music.Pattern` - Pattern creation, playback
- `Realtime.Music.TurnManager` - Turn rotation, timing
- `Realtime.Music.PatternMatcher` - Pattern comparison, accuracy

### Integration Tests
- Full game flows for each game type
- Turn-taking scenarios
- Pattern matching scenarios
- Volume/dynamics scenarios

---

## Migration Path

### Step 1: Add Volume Support (Backward Compatible)
- Add optional `velocity` field to `play_note` (defaults to 64 if not provided)
- Update analytics to track velocity
- No breaking changes

### Step 2: Add Game State Management
- Add `game_type` and `game_state` to `SessionManager` room state
- Default to `nil` (no game active) for backward compatibility
- Existing rooms continue to work

### Step 3: Add Pattern Storage
- Create `music_patterns` table
- Create `Realtime.Music.Pattern` module
- Add pattern management to `SessionManager`

### Step 4: Add Turn Management
- Create `Realtime.Music.TurnManager` module
- Integrate into `SessionManager` for games that need it
- Add channel events for turn-taking

### Step 5: Add Pattern Matching
- Create `Realtime.Music.PatternMatcher` module
- Add validation to Call and Response game
- Add feedback events

---

## Open Questions

1. **Pattern Storage**: Should patterns be stored per-room, per-tenant, or globally (shared across all tenants)?
2. **Turn Duration**: Should turn duration be configurable per game, or fixed?
3. **Pattern Matching Tolerance**: What level of accuracy is "correct" for Call and Response? (exact match vs. approximate)
4. **Game State Persistence**: Should game state persist across disconnects, or reset when room is recreated?
5. **Volume Limits**: Should there be rate limiting on volume changes, or just on note plays?
6. **Solo Queue**: Should solo queue be automatic rotation, or teacher-controlled?

---

## Next Steps

1. **Review and prioritize** - Which games are highest priority?
2. **Design patterns** - Finalize pattern storage format
3. **Implement Phase 1** - Volume support, game state management
4. **Test with one game** - Implement full support for one game (e.g., Melody Builder)
5. **Iterate** - Add support for remaining games

