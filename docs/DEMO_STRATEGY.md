# Demo Strategy: Simplest Proof-of-Concept

## Goal
Build the fastest, lowest-risk demo that proves the music extension works and demonstrates core capabilities.

## Recommended Approach: Single HTML File Demo

### Why This Approach?
- ✅ **Fastest to build** - Single file, no build step, no framework
- ✅ **Lowest risk** - Minimal dependencies, works in any browser
- ✅ **Easy to demo** - Open 2 browser tabs, works immediately
- ✅ **Proves core functionality** - Shows real-time sync, note broadcasting, tempo coordination

### What to Demo

**Option 1: Free-Form Collaborative Playing (Simplest)**
- Multiple users join a room
- Play notes in real-time (keyboard or buttons)
- Hear each other's notes synchronized
- See synchronized beat indicator
- **Proves:** Real-time note broadcasting, tempo synchronization, multi-user coordination

**Option 2: Rhythm Circle Game (Structured Demo)**
- Teacher assigns beats to students
- Students see visual beat indicator
- Students play only on their assigned beats
- **Proves:** Game infrastructure, beat assignment, structured gameplay

**Recommendation:** Start with Option 1, then add Option 2 if time permits.

## Implementation Plan

### Phase 1: Minimal Viable Demo (2-4 hours)

**Single HTML file with:**
1. **Room joining UI**
   - Input field for room ID (create via IEx: `Realtime.Music.SessionManager.create_room("teacher-1", "test-tenant", bpm: 120)`)
   - Input field for student ID
   - Join button

2. **Note playing interface**
   - Keyboard keys (A, S, D, F, G, H, J, K) mapped to MIDI notes (C4-C5)
   - OR simple buttons for each note
   - Visual feedback when note is played

3. **Beat indicator**
   - Visual metronome (flashing circle or bar)
   - Updates on `beat` events from server

4. **Audio synthesis**
   - Tone.js CDN for simple synth
   - Play notes when received via `student_note` events

5. **Connection status**
   - Show connected/disconnected state
   - Show current BPM

**Dependencies (all CDN):**
- Phoenix Socket client: `https://cdn.jsdelivr.net/npm/phoenix@latest/dist/phoenix.min.js`
- Tone.js: `https://cdn.jsdelivr.net/npm/tone@latest/build/Tone.min.js`

**File structure:**
```
demo/
  index.html  (single file, ~200-300 lines)
```

### Phase 2: Enhanced Demo (Optional, +2-3 hours)

Add teacher controls:
- Tempo slider (teacher only)
- Beat assignment UI (teacher only)
- Show all connected students
- Show beat assignments

## Technical Details

### WebSocket Connection
```javascript
const socket = new Phoenix.Socket("ws://localhost:4000/socket", {
  params: {token: generateJWT()}
})
socket.connect()

const channel = socket.channel("music_room:MUSIC-1234", {
  student_id: "student-1"
})
channel.join()
```

### JWT Token Generation
For demo, can use a simple token generator or hardcode a test token. The backend expects:
- `role` claim (for teacher/student authorization)
- `exp` claim (expiration)
- Signed with tenant's JWT secret

**Simplest approach:** Use IEx to generate a test token or create a simple token generator endpoint.

### Room Creation
**Via IEx (simplest for demo):**
```elixir
iex> {:ok, room_id} = Realtime.Music.SessionManager.create_room("teacher-1", "test-tenant", bpm: 120)
{:ok, "MUSIC-1234"}
```

**Via API (if time permits):**
Create a simple endpoint or use existing tenant API.

### Events to Handle

**Incoming events:**
- `beat` - Synchronized beat from tempo server
- `student_note` - Note played by another student
- `tempo_changed` - Tempo was changed by teacher
- `beat_assignments` - Beat assignments (on join)

**Outgoing events:**
- `play_note` - Play a note: `{midi: 60, velocity: 80}`

## Risk Assessment

### Low Risk ✅
- Single HTML file (no build complexity)
- CDN dependencies (no package management)
- Works in any modern browser
- Can test with 2 browser tabs (no network complexity)
- Backend already tested (139+ unit tests)

### Medium Risk ⚠️
- JWT token generation (may need simple helper)
- Tenant setup (may need to use existing test tenant)
- WebSocket connection (standard Phoenix Socket, well-documented)

### Mitigation
- Use existing test tenant from docker-compose setup
- Create simple JWT token generator script or hardcode test token
- Test WebSocket connection in browser console first

## Alternative: Browser Console Demo

**Even simpler approach (no HTML file needed):**
1. Open browser console on any page
2. Load Phoenix Socket via CDN
3. Connect and test manually
4. **Pro:** Zero setup time
5. **Con:** Less visual, harder to demo

**Use case:** Quick verification that backend works, before building UI.

## Success Criteria

**Minimum viable demo proves:**
- ✅ Multiple users can join same room
- ✅ Notes broadcast in real-time to all users
- ✅ Beats are synchronized across all clients
- ✅ Audio plays when notes are received
- ✅ Visual beat indicator updates in sync

**Enhanced demo additionally proves:**
- ✅ Teacher can change tempo (affects all clients)
- ✅ Teacher can assign beats to students
- ✅ Students see their assigned beats
- ✅ Rate limiting works (try spamming notes)

## Estimated Time

- **Phase 1 (Minimal):** 2-4 hours
  - HTML structure: 30 min
  - Phoenix Socket integration: 1 hour
  - Tone.js audio: 30 min
  - Beat indicator: 30 min
  - Testing/polish: 1-2 hours

- **Phase 2 (Enhanced):** +2-3 hours
  - Teacher controls: 1 hour
  - Beat assignment UI: 1 hour
  - Polish/testing: 1 hour

**Total: 4-7 hours for complete demo**

## Next Steps

1. **Create demo/index.html** with basic structure
2. **Test WebSocket connection** in browser console first
3. **Add note playing** (keyboard → MIDI → Tone.js)
4. **Add beat indicator** (visual metronome)
5. **Test with 2 browser tabs** to verify multi-user sync
6. **Add teacher controls** (if time permits)

## Files to Create

```
demo/
  index.html          # Single-file demo application
  README.md           # Quick start instructions
  (optional) token.js # Simple JWT token generator helper
```

