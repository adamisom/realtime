#!/bin/bash
# Complete test setup: creates room, starts HTTP server, and launches test users
# Usage: ./demo/demo-test-setup.sh [teacher_id] [tenant_id] [bpm]
# The HTTP server will run in the background. To stop it: pkill -f "python3 -m http.server 8080"

set -e

TEACHER_ID="${1:-teacher-1}"
TENANT_ID="${2:-test-tenant}"
BPM="${3:-120}"
HTTP_PORT=8080

echo "🎵 Music Extension Demo - Test Setup"
echo "======================================"
echo ""

# Check if Realtime server is running
if ! curl -s http://localhost:4000 > /dev/null 2>&1; then
    echo "⚠️  Warning: Realtime server may not be running on localhost:4000"
    echo "   Start it with: mix phx.server"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Start HTTP server for demo files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$SCRIPT_DIR"

# Check if HTTP server is already running
if curl -s http://localhost:$HTTP_PORT > /dev/null 2>&1; then
    echo "✅ HTTP server already running on port $HTTP_PORT"
    HTTP_SERVER_PID=""
else
    echo "🚀 Starting HTTP server on port $HTTP_PORT..."
    cd "$DEMO_DIR"
    python3 -m http.server $HTTP_PORT > /dev/null 2>&1 &
    HTTP_SERVER_PID=$!
    sleep 1  # Give server a moment to start
    
    if ! curl -s http://localhost:$HTTP_PORT > /dev/null 2>&1; then
        echo "❌ Failed to start HTTP server"
        exit 1
    fi
    echo "✅ HTTP server started (PID: $HTTP_SERVER_PID)"
    echo "   To stop: pkill -f 'python3 -m http.server $HTTP_PORT'"
fi

# Create room
echo "📝 Creating room..."
echo ""
echo "💡 Since the server is running, create the room in your IEx console:"
echo ""
echo "   {:ok, room_id} = Realtime.Music.SessionManager.create_room(\"$TEACHER_ID\", \"$TENANT_ID\", bpm: $BPM)"
echo ""
read -p "Enter the room ID (or press Enter to skip and create manually): " ROOM_ID
echo ""

if [ -z "$ROOM_ID" ]; then
    echo "⏭️  Skipping room creation."
    echo ""
    echo "Create the room in IEx, then run:"
    echo "  ./demo/demo-launch-test-users.sh <ROOM_ID> http://localhost:$HTTP_PORT/index.html $TENANT_ID"
    exit 0
fi

# Validate room ID format
if [[ ! "$ROOM_ID" =~ ^MUSIC-[0-9]+$ ]]; then
    echo "⚠️  Warning: Room ID format looks incorrect (expected MUSIC-####)"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

echo ""
echo "✅ Room created: $ROOM_ID"
echo ""

# Launch test users
echo "🚀 Launching test users..."
./demo/demo-launch-test-users.sh "$ROOM_ID" "http://localhost:$HTTP_PORT/index.html" "$TENANT_ID"

echo ""
echo "✨ Setup complete!"
echo ""
echo "📋 Quick reference:"
echo "   Room ID: $ROOM_ID"
echo "   Teacher: $TEACHER_ID"
echo "   Students: student-1, student-2, student-3, student-4"
echo "   Demo URL: http://localhost:$HTTP_PORT/index.html"
echo ""
echo "💡 All browser tabs should auto-fill with room ID and user IDs."
echo "   Just click 'Join Room' in each tab!"
echo ""
if [ -n "$HTTP_SERVER_PID" ]; then
    echo "🛑 To stop HTTP server: pkill -f 'python3 -m http.server $HTTP_PORT'"
fi

