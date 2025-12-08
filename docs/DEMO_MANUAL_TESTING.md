# Manual Testing Guide: Music Extension Demo

## 5-Minute Smoke Test

**Goal:** Verify core functionality works end-to-end in under 5 minutes.

### Prerequisites

**Set encryption key (required for tenant operations):**
```bash
export DB_ENC_KEY=1234567890123456
```
> **Note:** This key must match the one used when creating tenants. Add this to your `~/.zshrc` or `~/.bashrc` to make it permanent. If you forget to export it and are using `iex -S mix phx.server`, you can set it in IEx: `Application.put_env(:realtime, :db_enc_key, "1234567890123456")`

**Ensure database is running:**
```bash
# Start database containers (if using Docker)
make dev_db

# Or verify local PostgreSQL is running
psql -h localhost -U postgres -c "SELECT 1;" > /dev/null 2>&1 || echo "Database not running"
```

**Ensure server is running (recommended: use IEx for easier room/token creation):**
```bash
# Start server with IEx console (recommended for testing)
iex -S mix phx.server

# Or start server without IEx
mix phx.server

# Verify server is up
curl http://localhost:4000/healthcheck || echo "Server not running"
```

**Note:** Using `iex -S mix phx.server` is recommended because you can create rooms and generate tokens directly in the same console.

### Automated Setup (Recommended)

**One-command setup:**
```bash
./demo/demo-test-setup.sh
```

This will:
1. ✅ Create a room automatically
2. ✅ Launch 5 browser tabs (1 teacher + 4 students)
3. ✅ Auto-fill room ID and user IDs in each tab

Then just click "Join Room" in each tab and start testing!

### Manual Steps (Alternative)

1. **Create a room:**
   ```bash
   mix run demo/demo-create-room.exs teacher-1 test-tenant 120
   # Copy the room_id (e.g., "MUSIC-1234")
   ```

2. **Launch test users:**
   ```bash
   ./demo/demo-launch-test-users.sh MUSIC-1234
   # Opens 5 tabs with pre-filled values
   ```

3. **Join rooms:**
   - Each tab should have room ID and user ID pre-filled
   - Just click "Join Room" in each tab
   - ✅ Verify: Connection status shows "Connected" in all tabs

4. **Test note playing:**
   - In any student tab, press keyboard key "A" or click note button
   - ✅ Verify: Note plays in all tabs, log shows "Note received"

5. **Test tempo change:**
   - In teacher tab, move tempo slider to 60
   - Click "Set Tempo"
   - ✅ Verify: All tabs show BPM: 60, beat interval changes

**✅ Success Criteria:**
- Both users can join same room
- Notes broadcast in real-time
- Beats are synchronized
- Tempo changes propagate
- No errors in console

---

## Complete Feature Testing

### Connection & Room Management

#### Test 1: Socket Connection
- [ ] Open demo in browser
- [ ] Verify connection status shows "Disconnected" initially
- [ ] Wait 1-2 seconds
- [ ] ✅ Verify: Status changes to "Connected" (green)
- [ ] Check browser console for "Socket connected" message

#### Test 2: Join Room (Valid)
- [ ] Create room in IEx: `{:ok, room_id} = Realtime.Music.SessionManager.create_room("teacher-1", "test-tenant", bpm: 40)`
- [ ] Enter room ID in demo
- [ ] Enter student ID: `student-1`
- [ ] Click "Join Room"
- [ ] ✅ Verify: "Joined room successfully" in log
- [ ] ✅ Verify: Room info displays (Room ID, BPM)
- [ ] ✅ Verify: Join button disabled, Leave button enabled

#### Test 3: Join Room (Invalid)
- [ ] Enter invalid room ID: `INVALID-123`
- [ ] Click "Join Room"
- [ ] ✅ Verify: Error message appears
- [ ] Enter non-existent room: `MUSIC-9999`
- [ ] Click "Join Room"
- [ ] ✅ Verify: "Room not found" error

#### Test 4: Leave Room
- [ ] Join a room
- [ ] Click "Leave Room"
- [ ] ✅ Verify: "Left room" in log
- [ ] ✅ Verify: Room info cleared
- [ ] ✅ Verify: Join button enabled, Leave button disabled

### Note Playing

#### Test 5: Button Note Playing
- [ ] Join room
- [ ] Click note button (e.g., "A - C4")
- [ ] ✅ Verify: Button highlights briefly
- [ ] ✅ Verify: Log shows "Playing: C4"
- [ ] ✅ Verify: Note plays audibly (if audio initialized)

#### Test 6: Keyboard Note Playing
- [ ] Join room
- [ ] Press keyboard key "A" (C4)
- [ ] ✅ Verify: Note button highlights
- [ ] ✅ Verify: Note plays
- [ ] Test all keys: A, S, D, F, G, H, J, K
- [ ] ✅ Verify: Each key plays correct note

#### Test 7: Multi-User Note Broadcasting
- [ ] Open demo in 2 browser tabs
- [ ] Join same room (different student IDs)
- [ ] Play note in tab 1
- [ ] ✅ Verify: Tab 2 receives note (log shows "Note received from student-1")
- [ ] ✅ Verify: Note plays audibly in tab 2
- [ ] Play note in tab 2
- [ ] ✅ Verify: Tab 1 receives note

#### Test 8: Rate Limiting
- [ ] Join room as student
- [ ] Rapidly press keyboard keys (spam notes)
- [ ] ✅ Verify: After ~10 notes/second, error appears: "Rate limit exceeded"
- [ ] Wait 1 second
- [ ] ✅ Verify: Can play notes again

### Beat Synchronization

#### Test 9: Beat Indicator
- [ ] Join room
- [ ] ✅ Verify: Beat indicator circle visible
- [ ] ✅ Verify: Beat count starts at 0
- [ ] Wait for beat events
- [ ] ✅ Verify: Indicator flashes green on each beat
- [ ] ✅ Verify: Beat count increments
- [ ] ✅ Verify: Indicator returns to gray after flash

#### Test 10: Multi-User Beat Sync
- [ ] Open demo in 2 browser tabs
- [ ] Join same room
- [ ] ✅ Verify: Both tabs show same beat number
- [ ] ✅ Verify: Both indicators flash simultaneously
- [ ] ✅ Verify: Beat intervals match (e.g., ~1500ms for 40 BPM)

### Audio Synthesis

#### Test 11: Audio Initialization
- [ ] Open demo
- [ ] Click anywhere on page (triggers audio init)
- [ ] ✅ Verify: Log shows "Audio initialized"
- [ ] ✅ Verify: No console errors

#### Test 12: Audio Playback
- [ ] Join room
- [ ] Initialize audio (click page)
- [ ] Play note
- [ ] ✅ Verify: Note plays audibly
- [ ] Receive note from other user
- [ ] ✅ Verify: Note plays audibly
- [ ] Test different MIDI notes
- [ ] ✅ Verify: Each note has correct pitch

### Teacher Controls

#### Test 13: Role Selection
- [ ] Select "Teacher" role
- [ ] Join room
- [ ] ✅ Verify: Teacher Controls section appears
- [ ] Select "Student" role
- [ ] Join room
- [ ] ✅ Verify: Teacher Controls section hidden

#### Test 14: Tempo Control (Teacher)
- [ ] Join as teacher
- [ ] Move tempo slider to 60
- [ ] ✅ Verify: Tempo value updates to 60
- [ ] Click "Set Tempo"
- [ ] ✅ Verify: Log shows "Tempo set to 60 BPM"
- [ ] ✅ Verify: BPM display updates to 60
- [ ] ✅ Verify: Beat interval changes (faster)

#### Test 15: Tempo Control (Student - Should Fail)
- [ ] Join as student
- [ ] Try to change tempo (if UI visible)
- [ ] ✅ Verify: Error message: "Only teachers can change tempo"
- [ ] Or verify: Tempo controls not visible

#### Test 16: Tempo Propagation
- [ ] Open 2 tabs: teacher and student
- [ ] Join same room
- [ ] Teacher changes tempo to 60
- [ ] ✅ Verify: Student tab receives tempo_changed event
- [ ] ✅ Verify: Student BPM display updates
- [ ] ✅ Verify: Both tabs' beat intervals match new tempo

### Beat Assignment

#### Test 17: Student Tracking
- [ ] Join as teacher
- [ ] Open 2 student tabs, join same room
- [ ] Students play notes
- [ ] ✅ Verify: Teacher sees both students in student list
- [ ] ✅ Verify: Student count shows "2"

#### Test 18: Assign Beat
- [ ] Join as teacher
- [ ] Join as student in another tab
- [ ] Teacher assigns beat 1 to student
- [ ] ✅ Verify: Log shows "Assigned beat 1 to student-1"
- [ ] ✅ Verify: Student receives beat_assignment_updated event
- [ ] ✅ Verify: Student log shows assigned beat

#### Test 19: Clear Beat Assignment
- [ ] Teacher has assigned beat to student
- [ ] Teacher selects "No assignment" for student
- [ ] Teacher clicks "Assign"
- [ ] ✅ Verify: Beat assignment cleared
- [ ] ✅ Verify: Student receives update

### Error Handling

#### Test 20: Network Disconnection
- [ ] Join room
- [ ] Stop server: `Ctrl+C` in server terminal
- [ ] ✅ Verify: Connection status changes to "Disconnected"
- [ ] ✅ Verify: Log shows "Socket disconnected"
- [ ] Restart server: `mix phx.server`
- [ ] ✅ Verify: Reconnection attempt (check log)

#### Test 21: Invalid Inputs
- [ ] Try to join with empty room ID
- [ ] ✅ Verify: Alert: "Please enter both Room ID and Student ID"
- [ ] Try to join with invalid format: `INVALID`
- [ ] ✅ Verify: Alert: "Invalid room ID format"
- [ ] Try to play note without joining
- [ ] ✅ Verify: Error in log: "Not connected to a room"

### Edge Cases

#### Test 22: Multiple Simultaneous Users
- [ ] Use automated setup: `./demo/demo-test-setup.sh` (launches 5 users)
- [ ] Or manually: Open 3+ browser tabs, join same room with different student IDs
- [ ] All users play notes simultaneously
- [ ] ✅ Verify: All notes broadcast to all users
- [ ] ✅ Verify: Beats stay synchronized
- [ ] ✅ Verify: No performance degradation

#### Test 23: Rapid Tempo Changes
- [ ] Join as teacher
- [ ] Rapidly change tempo: 40 → 60 → 50 → 70
- [ ] ✅ Verify: Each change propagates correctly
- [ ] ✅ Verify: Beat intervals update smoothly
- [ ] ✅ Verify: No errors or crashes

#### Test 24: Long-Running Session
- [ ] Join room
- [ ] Let session run for 2-3 minutes
- [ ] ✅ Verify: Beats stay synchronized (no drift)
- [ ] ✅ Verify: Connection remains stable
- [ ] ✅ Verify: No memory leaks (check browser dev tools)

---

## Browser Compatibility Testing

Test on multiple browsers:
- [ ] Chrome/Edge
- [ ] Firefox
- [ ] Safari
- [ ] Mobile browser (optional)

For each browser:
- [ ] Verify WebSocket connection works
- [ ] Verify audio plays
- [ ] Verify all UI elements render correctly
- [ ] Check console for errors

---

## Performance Testing

- [ ] Test with 5+ simultaneous users
- [ ] Monitor browser memory usage (should be stable)
- [ ] Check server logs for errors
- [ ] Verify beat timing accuracy over 5+ minutes
- [ ] Test rate limiting with rapid note playing

---

## Troubleshooting Quick Reference

**Connection issues:**
- Check server is running: `mix phx.server`
- Verify WebSocket URL: `ws://localhost:4000/socket`
- Check browser console for errors
- Verify JWT token (if using real auth)

**No audio:**
- Click page to initialize audio (browser autoplay policy)
- Check browser audio permissions
- Verify Tone.js loaded (check console)
- Test in different browser

**Beats not syncing:**
- Verify all clients joined same room
- Check server logs for tempo server errors
- Verify room BPM matches displayed BPM
- Check network latency

**Notes not broadcasting:**
- Verify room exists (check IEx)
- Check rate limiting (may be throttled)
- Verify channel is joined (check log)
- Check server logs for errors

