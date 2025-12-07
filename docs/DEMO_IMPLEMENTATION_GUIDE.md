# Demo Implementation Guide: Music Extension Proof-of-Concept

## Overview

This guide provides step-by-step instructions to build a complete demo application that proves the music extension works. The demo is a single HTML file that demonstrates real-time collaborative music-making with synchronized tempo, note broadcasting, and teacher controls.

**Status:** ✅ **COMPLETE** - All phases implemented in `demo/index.html`

**Estimated Time:** 4-7 hours total
- Phase 1 (Minimal): 2-4 hours ✅ **DONE**
- Phase 2 (Enhanced): 2-3 hours ✅ **DONE**

**Implementation:** All features have been implemented in a single file (`demo/index.html`). This guide serves as documentation of what was built and can be used for reference or future enhancements.

## ✅ Completion Status

**All tasks are complete!** The demo application (`demo/index.html`) includes:

### Phase 1: Minimal Viable Demo ✅
- ✅ Subphase 1.1: Project Setup and Basic HTML Structure
- ✅ Subphase 1.2: Phoenix Socket Connection
- ✅ Subphase 1.3: Room Joining UI and Logic
- ✅ Subphase 1.4: Note Playing Interface
- ✅ Subphase 1.5: Audio Synthesis with Tone.js
- ✅ Subphase 1.6: Beat Indicator Visualization
- ✅ Subphase 1.7: Real-Time Note Broadcasting
- ✅ Subphase 1.8: Connection Status and Polish

### Phase 2: Enhanced Demo ✅
- ✅ Subphase 2.1: Teacher Role Detection and UI
- ✅ Subphase 2.2: Tempo Control (Teacher Only)
- ✅ Subphase 2.3: Beat Assignment UI
- ✅ Subphase 2.4: Student List Display
- ✅ Subphase 2.5: Final Polish and Testing

**Ready to test!** See `demo/README.md` for quick start instructions.

---

## Phase 1: Minimal Viable Demo ✅ **COMPLETE**

### Subphase 1.1: Project Setup and Basic HTML Structure ✅ **DONE**

**Goal:** Create the basic HTML file structure with dependencies and layout.

#### Task 1.1.1: Create demo directory and HTML file ✅ **DONE**

**Files to create:**
- `demo/index.html`

**Code sample:**
```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Music Extension Demo</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
        }
        .section {
            margin: 20px 0;
            padding: 15px;
            border: 1px solid #ddd;
            border-radius: 5px;
        }
        button {
            padding: 10px 15px;
            margin: 5px;
            font-size: 16px;
            cursor: pointer;
        }
        input {
            padding: 8px;
            margin: 5px;
            font-size: 14px;
        }
        .status {
            padding: 10px;
            margin: 10px 0;
            border-radius: 5px;
        }
        .connected { background-color: #d4edda; }
        .disconnected { background-color: #f8d7da; }
    </style>
</head>
<body>
    <h1>Music Extension Demo</h1>
    
    <!-- Connection Section -->
    <div class="section">
        <h2>Connection</h2>
        <div id="connection-status" class="status disconnected">Disconnected</div>
        <div>
            <input type="text" id="room-id" placeholder="Room ID (e.g., MUSIC-1234)">
            <input type="text" id="student-id" placeholder="Student ID (e.g., student-1)">
            <button id="join-btn">Join Room</button>
            <button id="leave-btn" disabled>Leave Room</button>
        </div>
        <div id="room-info"></div>
    </div>
    
    <!-- Note Playing Section -->
    <div class="section">
        <h2>Play Notes</h2>
        <div id="note-buttons"></div>
        <p>Or use keyboard: A, S, D, F, G, H, J, K</p>
    </div>
    
    <!-- Beat Indicator Section -->
    <div class="section">
        <h2>Beat Indicator</h2>
        <div id="beat-indicator" style="width: 100px; height: 100px; border-radius: 50%; background-color: #ccc; margin: 20px auto;"></div>
        <div id="beat-count">Beat: 0</div>
        <div id="bpm-display">BPM: --</div>
    </div>
    
    <!-- Log Section -->
    <div class="section">
        <h2>Activity Log</h2>
        <div id="log" style="max-height: 200px; overflow-y: auto; font-family: monospace; font-size: 12px;"></div>
    </div>

    <!-- Dependencies -->
    <script src="https://cdn.jsdelivr.net/npm/phoenix@latest/dist/phoenix.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/tone@latest/build/Tone.min.js"></script>
    
    <script>
        // Application code will go here
        console.log("Demo loaded");
    </script>
</body>
</html>
```

**Manual Testing Checkpoint:**
- [ ] Open `demo/index.html` in browser
- [ ] Verify page loads without errors
- [ ] Verify all UI elements are visible
- [ ] Check browser console for "Demo loaded" message

**Unit Test Focus:** N/A (static HTML)

---

### Subphase 1.2: Phoenix Socket Connection ✅ **DONE**

**Goal:** Establish WebSocket connection to the Realtime server.

#### Task 1.2.1: Add JWT token generation helper ✅ **DONE**

**Files to update:**
- `demo/index.html` (add token generation function)

**Code sample (add to script section):**
```javascript
// JWT token generation (simplified for demo)
// For production, use proper JWT library or generate server-side
function generateJWT(role = "student") {
    // This is a simplified token generator for demo purposes
    // In production, tokens should be generated server-side with proper signing
    const header = btoa(JSON.stringify({ alg: "HS256", typ: "JWT" }));
    const payload = btoa(JSON.stringify({
        role: role,
        exp: Math.floor(Date.now() / 1000) + 3600, // 1 hour expiration
        iat: Math.floor(Date.now() / 1000)
    }));
    // For demo, we'll use a placeholder signature
    // In real implementation, this would be signed with tenant's JWT secret
    const signature = btoa("demo-signature");
    return `${header}.${payload}.${signature}`;
}
```

**Note:** For actual demo, you may need to generate a real JWT token. See Task 1.2.2 for alternative.

#### Task 1.2.2: Create token generator script (alternative)

**Files to create:**
- `demo/generate-token.js` (Node.js script to generate real JWT)

**Code sample:**
```javascript
// Run with: node demo/generate-token.js
const jwt = require('jsonwebtoken');

const secret = process.env.JWT_SECRET || 'your-tenant-jwt-secret';
const role = process.argv[2] || 'student';

const token = jwt.sign({
    role: role,
    exp: Math.floor(Date.now() / 1000) + 3600,
    iat: Math.floor(Date.now() / 1000)
}, secret);

console.log(token);
```

**Usage:** `JWT_SECRET=your-secret node demo/generate-token.js teacher`

#### Task 1.2.3: Initialize Phoenix Socket connection

**Files to update:**
- `demo/index.html` (add socket initialization)

**Code sample (add to script section):**
```javascript
// Configuration
const WS_URL = "ws://localhost:4000/socket";
let socket = null;
let channel = null;
let currentRole = "student";

// Initialize socket
function initSocket(role = "student") {
    currentRole = role;
    const token = generateJWT(role);
    
    socket = new Phoenix.Socket(WS_URL, {
        params: { token: token },
        logger: (kind, msg, data) => {
            log(`${kind}: ${msg}`, data);
        }
    });
    
    socket.connect();
    
    socket.onOpen(() => {
        log("Socket connected");
        updateConnectionStatus(true);
    });
    
    socket.onClose(() => {
        log("Socket disconnected");
        updateConnectionStatus(false);
    });
    
    socket.onError((error) => {
        log("Socket error", error);
        updateConnectionStatus(false);
    });
}

function updateConnectionStatus(connected) {
    const statusEl = document.getElementById("connection-status");
    if (connected) {
        statusEl.textContent = "Connected";
        statusEl.className = "status connected";
    } else {
        statusEl.textContent = "Disconnected";
        statusEl.className = "status disconnected";
    }
}

function log(message, data = null) {
    const logEl = document.getElementById("log");
    const timestamp = new Date().toLocaleTimeString();
    const entry = document.createElement("div");
    entry.textContent = `[${timestamp}] ${message}${data ? ' ' + JSON.stringify(data) : ''}`;
    logEl.insertBefore(entry, logEl.firstChild);
    console.log(message, data);
}
```

**Manual Testing Checkpoint:**
- [ ] Open browser console
- [ ] Call `initSocket()` in console
- [ ] Verify "Socket connected" message appears
- [ ] Verify connection status updates to "Connected"
- [ ] Check network tab for WebSocket connection to `ws://localhost:4000/socket`

**Unit Test Focus:** Socket connection establishment and error handling

---

### Subphase 1.3: Room Joining UI and Logic ✅ **DONE**

**Goal:** Implement room joining functionality with UI feedback.

#### Task 1.3.1: Add room joining handler ✅ **DONE**

**Files to update:**
- `demo/index.html` (add join room function)

**Code sample (add to script section):**
```javascript
// Room state
let currentRoomId = null;
let currentStudentId = null;

// Join room
function joinRoom(roomId, studentId) {
    if (!socket || socket.connectionState() !== "open") {
        log("Error: Socket not connected. Call initSocket() first.");
        return;
    }
    
    if (channel) {
        channel.leave();
    }
    
    currentRoomId = roomId;
    currentStudentId = studentId;
    
    channel = socket.channel(`music_room:${roomId}`, {
        student_id: studentId
    });
    
    channel.join()
        .receive("ok", (resp) => {
            log("Joined room successfully", resp);
            updateRoomInfo(resp);
            setupChannelHandlers();
        })
        .receive("error", (resp) => {
            log("Failed to join room", resp);
            alert("Failed to join room: " + (resp.reason || "Unknown error"));
        })
        .receive("timeout", () => {
            log("Join timeout");
            alert("Join request timed out");
        });
}

function updateRoomInfo(roomData) {
    const roomInfoEl = document.getElementById("room-info");
    roomInfoEl.innerHTML = `
        <p><strong>Room ID:</strong> ${roomData.room_id}</p>
        <p><strong>BPM:</strong> ${roomData.bpm}</p>
    `;
    document.getElementById("bpm-display").textContent = `BPM: ${roomData.bpm}`;
}

function leaveRoom() {
    if (channel) {
        channel.leave();
        channel = null;
    }
    currentRoomId = null;
    currentStudentId = null;
    document.getElementById("room-info").innerHTML = "";
    log("Left room");
}
```

#### Task 1.3.2: Wire up join/leave buttons

**Files to update:**
- `demo/index.html` (add event listeners)

**Code sample (add to script section, at end):**
```javascript
// Initialize on page load
document.addEventListener("DOMContentLoaded", () => {
    // Initialize socket
    initSocket();
    
    // Join button
    document.getElementById("join-btn").addEventListener("click", () => {
        const roomId = document.getElementById("room-id").value.trim();
        const studentId = document.getElementById("student-id").value.trim();
        
        if (!roomId || !studentId) {
            alert("Please enter both Room ID and Student ID");
            return;
        }
        
        joinRoom(roomId, studentId);
        
        // Update button states
        document.getElementById("join-btn").disabled = true;
        document.getElementById("leave-btn").disabled = false;
    });
    
    // Leave button
    document.getElementById("leave-btn").addEventListener("click", () => {
        leaveRoom();
        document.getElementById("join-btn").disabled = false;
        document.getElementById("leave-btn").disabled = true;
    });
});
```

**Manual Testing Checkpoint:**
- [ ] Start server: `mix phx.server`
- [ ] Create room in IEx: `{:ok, room_id} = Realtime.Music.SessionManager.create_room("teacher-1", "test-tenant", bpm: 120)`
- [ ] Enter room ID and student ID in UI
- [ ] Click "Join Room"
- [ ] Verify "Joined room successfully" in log
- [ ] Verify room info displays (Room ID, BPM)
- [ ] Click "Leave Room"
- [ ] Verify "Left room" in log

**Unit Test Focus:** Room joining logic, error handling, UI state updates

---

### Subphase 1.4: Note Playing Interface ✅ **DONE**

**Goal:** Create keyboard and button interface for playing notes.

#### Task 1.4.1: Create note button UI ✅ **DONE**

**Files to update:**
- `demo/index.html` (add note buttons generation)

**Code sample (add to script section):**
```javascript
// Note mapping: keyboard key -> MIDI note
const NOTE_MAP = {
    'a': 60, // C4
    's': 62, // D4
    'd': 64, // E4
    'f': 65, // F4
    'g': 67, // G4
    'h': 69, // A4
    'j': 71, // B4
    'k': 72  // C5
};

const NOTE_NAMES = {
    60: 'C4', 62: 'D4', 64: 'E4', 65: 'F4',
    67: 'G4', 69: 'A4', 71: 'B4', 72: 'C5'
};

// Generate note buttons
function createNoteButtons() {
    const container = document.getElementById("note-buttons");
    container.innerHTML = "";
    
    Object.entries(NOTE_MAP).forEach(([key, midi]) => {
        const button = document.createElement("button");
        button.textContent = `${key.toUpperCase()} - ${NOTE_NAMES[midi]}`;
        button.dataset.midi = midi;
        button.dataset.key = key;
        button.addEventListener("click", () => playNote(midi));
        container.appendChild(button);
    });
}

// Call on page load
createNoteButtons();
```

#### Task 1.4.2: Add keyboard event handlers

**Files to update:**
- `demo/index.html` (add keyboard listeners)

**Code sample (add to script section):**
```javascript
// Keyboard event handling
let keysPressed = new Set();

document.addEventListener("keydown", (e) => {
    const key = e.key.toLowerCase();
    if (NOTE_MAP[key] && !keysPressed.has(key)) {
        keysPressed.add(key);
        playNote(NOTE_MAP[key]);
        
        // Visual feedback
        const button = document.querySelector(`button[data-key="${key}"]`);
        if (button) {
            button.style.backgroundColor = "#4CAF50";
        }
    }
});

document.addEventListener("keyup", (e) => {
    const key = e.key.toLowerCase();
    keysPressed.delete(key);
    
    // Remove visual feedback
    const button = document.querySelector(`button[data-key="${key}"]`);
    if (button) {
        button.style.backgroundColor = "";
    }
});
```

#### Task 1.4.3: Implement playNote function

**Files to update:**
- `demo/index.html` (add playNote function)

**Code sample (add to script section):**
```javascript
// Play note function
function playNote(midi, velocity = 80) {
    if (!channel) {
        log("Error: Not connected to a room");
        return;
    }
    
    channel.push("play_note", {
        midi: midi,
        velocity: velocity
    })
    .receive("ok", () => {
        log(`Note played: ${NOTE_NAMES[midi] || midi} (MIDI ${midi})`);
    })
    .receive("error", (resp) => {
        log("Error playing note", resp);
        if (resp.reason === "rate_limit_exceeded") {
            alert("Rate limit exceeded! Slow down.");
        }
    });
}
```

**Manual Testing Checkpoint:**
- [ ] Join a room
- [ ] Click note buttons - verify log shows "Note played"
- [ ] Press keyboard keys (A, S, D, F, G, H, J, K) - verify notes play
- [ ] Verify buttons highlight when clicked
- [ ] Try spamming notes rapidly - verify rate limit error appears
- [ ] Check server logs for `play_note` events

**Unit Test Focus:** Note playing logic, keyboard mapping, rate limit handling

---

### Subphase 1.5: Audio Synthesis with Tone.js ✅ **DONE**

**Goal:** Add audio playback when notes are received.

#### Task 1.5.1: Initialize Tone.js synthesizer ✅ **DONE**

**Files to update:**
- `demo/index.html` (add Tone.js setup)

**Code sample (add to script section):**
```javascript
// Audio setup
let synth = null;

async function initAudio() {
    // Wait for user interaction (browser autoplay policy)
    await Tone.start();
    
    // Create a simple synth
    synth = new Tone.Synth({
        oscillator: {
            type: "sine"
        },
        envelope: {
            attack: 0.01,
            decay: 0.1,
            sustain: 0.5,
            release: 0.3
        }
    }).toDestination();
    
    log("Audio initialized");
}

// Initialize on first user interaction
document.addEventListener("click", () => {
    if (!synth) {
        initAudio();
    }
}, { once: true });
```

#### Task 1.5.2: Add handler for incoming notes

**Files to update:**
- `demo/index.html` (add channel handler for student_note)

**Code sample (add to setupChannelHandlers function):**
```javascript
function setupChannelHandlers() {
    if (!channel) return;
    
    // Handle incoming notes from other students
    channel.on("student_note", (payload) => {
        log(`Note received from ${payload.student_id}: ${NOTE_NAMES[payload.midi] || payload.midi}`, payload);
        
        // Play the note
        if (synth) {
            const freq = Tone.Frequency(payload.midi, "midi").toFrequency();
            const velocity = payload.velocity || 64;
            const volume = (velocity / 127) * 20 - 20; // Convert velocity to dB
            
            synth.triggerAttackRelease(freq, "8n", undefined, volume);
        }
    });
}
```

**Manual Testing Checkpoint:**
- [ ] Open demo in 2 browser tabs
- [ ] Join same room from both tabs (different student IDs)
- [ ] Play note in tab 1
- [ ] Verify note plays audibly in tab 2
- [ ] Verify log shows "Note received" in tab 2
- [ ] Test with different MIDI notes
- [ ] Test with different velocities

**Unit Test Focus:** Audio synthesis, MIDI to frequency conversion, velocity handling

---

### Subphase 1.6: Beat Indicator Visualization ✅ **DONE**

**Goal:** Create visual metronome that syncs with server beats.

#### Task 1.6.1: Add beat event handler ✅ **DONE**

**Files to update:**
- `demo/index.html` (add beat handler to setupChannelHandlers)

**Code sample (add to setupChannelHandlers function):**
```javascript
function setupChannelHandlers() {
    if (!channel) return;
    
    // ... existing student_note handler ...
    
    // Handle beat events
    channel.on("beat", (payload) => {
        const beatNumber = payload.beat || 0;
        updateBeatIndicator(beatNumber);
        log(`Beat: ${beatNumber}`);
    });
}

let beatAnimationTimeout = null;

function updateBeatIndicator(beatNumber) {
    const indicator = document.getElementById("beat-indicator");
    const beatCount = document.getElementById("beat-count");
    
    // Update beat count
    beatCount.textContent = `Beat: ${beatNumber}`;
    
    // Visual flash
    indicator.style.backgroundColor = "#4CAF50";
    indicator.style.transform = "scale(1.2)";
    indicator.style.transition = "all 0.1s";
    
    // Reset after flash
    if (beatAnimationTimeout) {
        clearTimeout(beatAnimationTimeout);
    }
    beatAnimationTimeout = setTimeout(() => {
        indicator.style.backgroundColor = "#ccc";
        indicator.style.transform = "scale(1)";
    }, 100);
}
```

#### Task 1.6.2: Add CSS transitions for smooth animation

**Files to update:**
- `demo/index.html` (update beat indicator CSS)

**Code sample (update style section):**
```css
#beat-indicator {
    width: 100px;
    height: 100px;
    border-radius: 50%;
    background-color: #ccc;
    margin: 20px auto;
    transition: all 0.1s ease;
    border: 3px solid #333;
}
```

**Manual Testing Checkpoint:**
- [ ] Join a room
- [ ] Verify beat indicator flashes on each beat
- [ ] Verify beat count increments
- [ ] Open 2 browser tabs, join same room
- [ ] Verify both tabs show beats in sync
- [ ] Verify beats arrive at correct interval (e.g., ~500ms for 120 BPM)

**Unit Test Focus:** Beat event handling, visual synchronization, timing accuracy

---

### Subphase 1.7: Real-Time Note Broadcasting ✅ **DONE**

**Goal:** Ensure notes broadcast correctly to all participants.

#### Task 1.7.1: Add additional channel event handlers ✅ **DONE**

**Files to update:**
- `demo/index.html` (complete setupChannelHandlers)

**Code sample (complete setupChannelHandlers function):**
```javascript
function setupChannelHandlers() {
    if (!channel) return;
    
    // Handle incoming notes from other students
    channel.on("student_note", (payload) => {
        log(`Note received from ${payload.student_id}: ${NOTE_NAMES[payload.midi] || payload.midi}`, payload);
        
        if (synth) {
            const freq = Tone.Frequency(payload.midi, "midi").toFrequency();
            const velocity = payload.velocity || 64;
            const volume = (velocity / 127) * 20 - 20;
            synth.triggerAttackRelease(freq, "8n", undefined, volume);
        }
    });
    
    // Handle beat events
    channel.on("beat", (payload) => {
        const beatNumber = payload.beat || 0;
        updateBeatIndicator(beatNumber);
        log(`Beat: ${beatNumber}`);
    });
    
    // Handle tempo changes
    channel.on("tempo_changed", (payload) => {
        const bpm = payload.bpm;
        document.getElementById("bpm-display").textContent = `BPM: ${bpm}`;
        log(`Tempo changed to ${bpm} BPM`);
    });
    
    // Handle beat assignments (received on join)
    channel.on("beat_assignments", (payload) => {
        log("Beat assignments received", payload);
        // Will be used in Phase 2
    });
}
```

#### Task 1.7.2: Add visual feedback for own notes

**Files to update:**
- `demo/index.html` (update playNote to show visual feedback)

**Code sample (update playNote function):**
```javascript
function playNote(midi, velocity = 80) {
    if (!channel) {
        log("Error: Not connected to a room");
        return;
    }
    
    // Visual feedback
    const noteName = NOTE_NAMES[midi] || `MIDI ${midi}`;
    log(`Playing: ${noteName} (MIDI ${midi})`);
    
    channel.push("play_note", {
        midi: midi,
        velocity: velocity
    })
    .receive("ok", () => {
        // Note will be broadcast and we'll receive it via student_note
    })
    .receive("error", (resp) => {
        log("Error playing note", resp);
        if (resp.reason === "rate_limit_exceeded") {
            alert("Rate limit exceeded! Slow down.");
        }
    });
}
```

**Manual Testing Checkpoint:**
- [ ] Open 3 browser tabs
- [ ] Join same room from all 3 tabs (different student IDs)
- [ ] Play note in tab 1
- [ ] Verify note plays in tabs 2 and 3
- [ ] Verify all tabs show beats in sync
- [ ] Verify log shows correct student IDs for each note
- [ ] Test with multiple simultaneous notes

**Unit Test Focus:** Multi-user synchronization, event broadcasting, state consistency

---

### Subphase 1.8: Connection Status and Polish ✅ **DONE**

**Goal:** Add final polish and error handling.

#### Task 1.8.1: Improve connection status display ✅ **DONE**

**Files to update:**
- `demo/index.html` (enhance connection status)

**Code sample (update updateConnectionStatus function):**
```javascript
function updateConnectionStatus(connected) {
    const statusEl = document.getElementById("connection-status");
    const joinBtn = document.getElementById("join-btn");
    const leaveBtn = document.getElementById("leave-btn");
    
    if (connected) {
        statusEl.textContent = "Connected";
        statusEl.className = "status connected";
        joinBtn.disabled = false;
    } else {
        statusEl.textContent = "Disconnected";
        statusEl.className = "status disconnected";
        joinBtn.disabled = true;
        leaveBtn.disabled = true;
        if (channel) {
            channel = null;
        }
    }
}
```

#### Task 1.8.2: Add reconnection handling

**Files to update:**
- `demo/index.html` (add reconnection logic)

**Code sample (add to socket initialization):**
```javascript
socket.onClose(() => {
    log("Socket disconnected");
    updateConnectionStatus(false);
    
    // Attempt reconnection after delay
    setTimeout(() => {
        if (!socket.isConnected()) {
            log("Attempting to reconnect...");
            socket.connect();
        }
    }, 3000);
});
```

#### Task 1.8.3: Add error messages and validation

**Files to update:**
- `demo/index.html` (add validation to join function)

**Code sample (update joinRoom function):**
```javascript
function joinRoom(roomId, studentId) {
    // Validation
    if (!roomId || !studentId) {
        alert("Please enter both Room ID and Student ID");
        return;
    }
    
    if (!roomId.match(/^MUSIC-\d+$/)) {
        alert("Invalid room ID format. Should be MUSIC-####");
        return;
    }
    
    if (!socket || socket.connectionState() !== "open") {
        alert("Socket not connected. Please wait for connection.");
        return;
    }
    
    // ... rest of join logic ...
}
```

**Manual Testing Checkpoint:**
- [ ] Test with invalid room ID format
- [ ] Test joining non-existent room (should show error)
- [ ] Disconnect network, verify reconnection attempt
- [ ] Test all UI states (connected/disconnected, joined/not joined)
- [ ] Verify all error messages are user-friendly
- [ ] Test on different browsers (Chrome, Firefox, Safari)

**Unit Test Focus:** Error handling, validation, reconnection logic, edge cases

---

## Phase 2: Enhanced Demo ✅ **COMPLETE**

### Subphase 2.1: Teacher Role Detection and UI ✅ **DONE**

**Goal:** Add teacher role support and role-specific UI.

#### Task 2.1.1: Add role selection UI ✅ **DONE**

**Files to update:**
- `demo/index.html` (add role selector)

**Code sample (add to connection section HTML):**
```html
<div>
    <label>
        <input type="radio" name="role" value="student" checked> Student
    </label>
    <label>
        <input type="radio" name="role" value="teacher"> Teacher
    </label>
</div>
```

#### Task 2.1.2: Update socket initialization to use role

**Files to update:**
- `demo/index.html` (update initSocket and join handlers)

**Code sample (update join button handler):**
```javascript
document.getElementById("join-btn").addEventListener("click", () => {
    const roomId = document.getElementById("room-id").value.trim();
    const studentId = document.getElementById("student-id").value.trim();
    const role = document.querySelector('input[name="role"]:checked').value;
    
    if (!roomId || !studentId) {
        alert("Please enter both Room ID and Student ID");
        return;
    }
    
    // Reinitialize socket with correct role if needed
    if (currentRole !== role) {
        if (socket) {
            socket.disconnect();
        }
        initSocket(role);
        // Wait for connection before joining
        setTimeout(() => {
            joinRoom(roomId, studentId);
        }, 500);
    } else {
        joinRoom(roomId, studentId);
    }
    
    document.getElementById("join-btn").disabled = true;
    document.getElementById("leave-btn").disabled = false;
});
```

#### Task 2.1.3: Show/hide teacher controls based on role

**Files to update:**
- `demo/index.html` (add teacher controls section, update visibility)

**Code sample (add to HTML, after note playing section):**
```html
<!-- Teacher Controls Section -->
<div class="section" id="teacher-controls" style="display: none;">
    <h2>Teacher Controls</h2>
    <div>
        <label>Tempo (BPM):</label>
        <input type="range" id="tempo-slider" min="60" max="180" value="120">
        <span id="tempo-value">120</span>
        <button id="set-tempo-btn">Set Tempo</button>
    </div>
    <div id="beat-assignment-section">
        <h3>Beat Assignment</h3>
        <div id="student-list"></div>
    </div>
</div>
```

**Code sample (add to script, update joinRoom success handler):**
```javascript
channel.join()
    .receive("ok", (resp) => {
        log("Joined room successfully", resp);
        updateRoomInfo(resp);
        setupChannelHandlers();
        
        // Show teacher controls if teacher
        if (currentRole === "teacher") {
            document.getElementById("teacher-controls").style.display = "block";
        } else {
            document.getElementById("teacher-controls").style.display = "none";
        }
    })
    // ... rest of handlers ...
```

**Manual Testing Checkpoint:**
- [ ] Select "Teacher" role, join room
- [ ] Verify teacher controls section appears
- [ ] Select "Student" role, join room
- [ ] Verify teacher controls section is hidden
- [ ] Verify JWT token includes correct role claim
- [ ] Check server logs for role-based authorization

**Unit Test Focus:** Role detection, UI state management, authorization

---

### Subphase 2.2: Tempo Control (Teacher Only) ✅ **DONE**

**Goal:** Allow teachers to change tempo in real-time.

#### Task 2.2.1: Add tempo slider handler ✅ **DONE**

**Files to update:**
- `demo/index.html` (add tempo control logic)

**Code sample (add to script section):**
```javascript
// Tempo control
document.getElementById("tempo-slider").addEventListener("input", (e) => {
    document.getElementById("tempo-value").textContent = e.target.value;
});

document.getElementById("set-tempo-btn").addEventListener("click", () => {
    if (!channel || currentRole !== "teacher") {
        alert("Only teachers can change tempo");
        return;
    }
    
    const bpm = parseInt(document.getElementById("tempo-slider").value);
    setTempo(bpm);
});

function setTempo(bpm) {
    if (!channel) {
        log("Error: Not connected to a room");
        return;
    }
    
    channel.push("set_tempo", { bpm: bpm })
        .receive("ok", () => {
            log(`Tempo set to ${bpm} BPM`);
        })
        .receive("error", (resp) => {
            log("Error setting tempo", resp);
            alert("Failed to set tempo: " + (resp.reason || "Unknown error"));
        });
}
```

#### Task 2.2.2: Update tempo display on change

**Files to update:**
- `demo/index.html` (tempo_changed handler already added in 1.7.1)

**Note:** The tempo_changed handler from Subphase 1.7.1 should already update the BPM display. Verify it works.

**Manual Testing Checkpoint:**
- [ ] Join as teacher
- [ ] Move tempo slider, verify value updates
- [ ] Click "Set Tempo" button
- [ ] Verify log shows "Tempo set to X BPM"
- [ ] Open 2nd browser tab as student
- [ ] Change tempo in teacher tab
- [ ] Verify student tab receives tempo_changed event
- [ ] Verify beat interval changes in both tabs
- [ ] Try setting tempo as student (should fail)

**Unit Test Focus:** Tempo change propagation, authorization checks, beat recalculation

---

### Subphase 2.3: Beat Assignment UI ✅ **DONE**

**Goal:** Allow teachers to assign beats to students.

#### Task 2.3.1: Display connected students ✅ **DONE**

**Files to update:**
- `demo/index.html` (add student list display)

**Code sample (add to script section):**
```javascript
// Track connected students (simplified - in production, use presence)
let connectedStudents = [];

function updateStudentList(students) {
    const listEl = document.getElementById("student-list");
    listEl.innerHTML = "";
    
    students.forEach(studentId => {
        const studentDiv = document.createElement("div");
        studentDiv.style.margin = "10px 0";
        studentDiv.innerHTML = `
            <strong>${studentId}</strong>
            <select id="beat-${studentId}">
                <option value="">No assignment</option>
                <option value="1">Beat 1</option>
                <option value="2">Beat 2</option>
                <option value="3">Beat 3</option>
                <option value="4">Beat 4</option>
            </select>
            <button onclick="assignBeat('${studentId}')">Assign</button>
        `;
        listEl.appendChild(studentDiv);
    });
}

// For demo, we'll manually track students
// In production, use Phoenix Presence
function addStudent(studentId) {
    if (!connectedStudents.includes(studentId)) {
        connectedStudents.push(studentId);
        if (currentRole === "teacher") {
            updateStudentList(connectedStudents);
        }
    }
}
```

#### Task 2.3.2: Implement beat assignment

**Files to update:**
- `demo/index.html` (add assignBeat function)

**Code sample (add to script section):**
```javascript
function assignBeat(studentId) {
    if (!channel || currentRole !== "teacher") {
        alert("Only teachers can assign beats");
        return;
    }
    
    const beatSelect = document.getElementById(`beat-${studentId}`);
    const beat = parseInt(beatSelect.value);
    
    if (!beat) {
        // Clear assignment
        channel.push("assign_beat", {
            student_id: studentId,
            beat: null
        });
        log(`Cleared beat assignment for ${studentId}`);
    } else {
        channel.push("assign_beat", {
            student_id: studentId,
            beat: beat
        })
        .receive("ok", () => {
            log(`Assigned beat ${beat} to ${studentId}`);
        })
        .receive("error", (resp) => {
            log("Error assigning beat", resp);
        });
    }
}

// Make assignBeat available globally for onclick
window.assignBeat = assignBeat;
```

#### Task 2.3.3: Handle beat assignment updates

**Files to update:**
- `demo/index.html` (add beat_assignment_updated handler)

**Code sample (add to setupChannelHandlers):**
```javascript
// Handle beat assignment updates
channel.on("beat_assignment_updated", (payload) => {
    log("Beat assignment updated", payload);
    // Update UI if needed
});

// On join, receive initial beat assignments
channel.on("beat_assignments", (payload) => {
    log("Beat assignments", payload);
    // Display assignments if student
    if (currentRole === "student") {
        const myAssignment = payload[currentStudentId];
        if (myAssignment) {
            log(`Your assigned beat: ${myAssignment}`);
        }
    }
});
```

**Manual Testing Checkpoint:**
- [ ] Join as teacher
- [ ] Join as student in another tab
- [ ] Teacher assigns beat to student
- [ ] Verify student receives beat_assignment_updated event
- [ ] Verify student sees their assigned beat
- [ ] Teacher changes beat assignment
- [ ] Verify update propagates to student
- [ ] Teacher clears assignment
- [ ] Verify student sees assignment cleared

**Unit Test Focus:** Beat assignment logic, event propagation, UI updates

---

### Subphase 2.4: Student List Display ✅ **DONE**

**Goal:** Show all connected students (using Presence or manual tracking).

#### Task 2.4.1: Track students via note events (simplified approach) ✅ **DONE**

**Files to update:**
- `demo/index.html` (update student_note handler)

**Code sample (update student_note handler):**
```javascript
channel.on("student_note", (payload) => {
    // Track student
    if (currentRole === "teacher") {
        addStudent(payload.student_id);
    }
    
    log(`Note received from ${payload.student_id}: ${NOTE_NAMES[payload.midi] || payload.midi}`, payload);
    
    if (synth) {
        const freq = Tone.Frequency(payload.midi, "midi").toFrequency();
        const velocity = payload.velocity || 64;
        const volume = (velocity / 127) * 20 - 20;
        synth.triggerAttackRelease(freq, "8n", undefined, volume);
    }
});
```

**Note:** For a more robust solution, use Phoenix Presence. This simplified approach tracks students as they play notes.

#### Task 2.4.2: Display student count

**Files to update:**
- `demo/index.html` (add student count display)

**Code sample (add to teacher controls section HTML):**
```html
<div>
    <strong>Connected Students:</strong> <span id="student-count">0</span>
</div>
```

**Code sample (update updateStudentList function):**
```javascript
function updateStudentList(students) {
    document.getElementById("student-count").textContent = students.length;
    // ... rest of function ...
}
```

**Manual Testing Checkpoint:**
- [ ] Join as teacher
- [ ] Join as 2 students in separate tabs
- [ ] Students play notes
- [ ] Verify teacher sees both students in list
- [ ] Verify student count is correct
- [ ] Student leaves room
- [ ] Verify student count updates (if implementing leave tracking)

**Unit Test Focus:** Student tracking, list management, count accuracy

---

### Subphase 2.5: Final Polish and Testing ✅ **DONE**

**Goal:** Add final touches and comprehensive testing.

#### Task 2.5.1: Add loading states ✅ **DONE**

**Files to update:**
- `demo/index.html` (add loading indicators)

**Code sample (update join button handler):**
```javascript
document.getElementById("join-btn").addEventListener("click", () => {
    // ... validation ...
    
    const joinBtn = document.getElementById("join-btn");
    joinBtn.disabled = true;
    joinBtn.textContent = "Joining...";
    
    // ... join logic ...
    
    channel.join()
        .receive("ok", (resp) => {
            joinBtn.textContent = "Join Room";
            joinBtn.disabled = true;
            document.getElementById("leave-btn").disabled = false;
            // ... rest of handler ...
        })
        .receive("error", (resp) => {
            joinBtn.textContent = "Join Room";
            joinBtn.disabled = false;
            // ... error handling ...
        });
});
```

#### Task 2.5.2: Add keyboard shortcuts help

**Files to update:**
- `demo/index.html` (add help section)

**Code sample (add to HTML):**
```html
<div class="section">
    <h2>Keyboard Shortcuts</h2>
    <ul>
        <li><strong>A, S, D, F, G, H, J, K:</strong> Play notes (C4 to C5)</li>
        <li><strong>Space:</strong> (Optional) Play current assigned beat</li>
    </ul>
</div>
```

#### Task 2.5.3: Add room creation helper (optional)

**Files to create:**
- `demo/create-room.html` (simple page to create rooms via API)

**Or add to main demo:**
```javascript
// Helper function to create room (requires API endpoint)
async function createRoom(teacherId, tenantId, bpm = 120) {
    // This would call your API endpoint
    // For demo, use IEx: Realtime.Music.SessionManager.create_room(...)
    log("To create a room, use IEx: Realtime.Music.SessionManager.create_room('teacher-1', 'test-tenant', bpm: 120)");
}
```

**Manual Testing Checkpoint:**
- [ ] Test complete flow: create room → join as teacher → join as students → play notes → change tempo → assign beats
- [ ] Test error scenarios: invalid room, network disconnect, rate limiting
- [ ] Test with 3+ simultaneous users
- [ ] Verify all UI states work correctly
- [ ] Test on different browsers
- [ ] Verify audio works on all browsers
- [ ] Check for console errors
- [ ] Verify all features work together

**Unit Test Focus:** End-to-end integration, error handling, multi-user scenarios

---

## Testing Checklist

### Phase 1 Testing
- [ ] Socket connects successfully
- [ ] Can join room with valid room ID
- [ ] Cannot join non-existent room
- [ ] Notes play when buttons clicked
- [ ] Notes play when keyboard pressed
- [ ] Notes broadcast to other users
- [ ] Audio plays when receiving notes
- [ ] Beat indicator flashes on beats
- [ ] Beats are synchronized across tabs
- [ ] Rate limiting works (spam protection)

### Phase 2 Testing
- [ ] Teacher role can change tempo
- [ ] Student role cannot change tempo
- [ ] Tempo changes propagate to all users
- [ ] Beat assignments work
- [ ] Students see their assigned beats
- [ ] Student list displays correctly
- [ ] All UI states work correctly
- [ ] Error messages are user-friendly

---

## Troubleshooting

### Common Issues

**Socket won't connect:**
- Verify server is running: `mix phx.server`
- Check WebSocket URL is correct
- Verify JWT token is valid
- Check browser console for errors

**Can't join room:**
- Verify room exists (create in IEx)
- Check room ID format (MUSIC-####)
- Verify tenant ID matches
- Check server logs for errors

**No audio:**
- Verify Tone.js loaded (check console)
- Check browser autoplay policy (may need user interaction)
- Verify audio context started: `Tone.start()`
- Check browser audio permissions

**Beats not syncing:**
- Verify tempo server started (check server logs)
- Check beat events are received (check log)
- Verify all clients joined same room
- Check network latency

---

## Next Steps After Demo

1. **Add Phoenix Presence** for proper student tracking
2. **Add room creation API** endpoint
3. **Improve JWT handling** (server-side generation)
4. **Add game modes** (Rhythm Circle, Melody Builder, etc.)
5. **Add visual piano keyboard** for better UX
6. **Add recording/playback** functionality
7. **Deploy to staging** environment

