#!/bin/bash
# Complete test setup: creates room and launches test users
# Usage: ./demo/test-setup.sh [teacher_id] [tenant_id] [bpm]

set -e

TEACHER_ID="${1:-teacher-1}"
TENANT_ID="${2:-test-tenant}"
BPM="${3:-120}"

echo "🎵 Music Extension Demo - Test Setup"
echo "======================================"
echo ""

# Check if server is running
if ! curl -s http://localhost:4000 > /dev/null 2>&1; then
    echo "⚠️  Warning: Server may not be running on localhost:4000"
    echo "   Start it with: mix phx.server"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create room
echo "📝 Creating room..."
ROOM_OUTPUT=$(mix run demo/create-room.exs "$TEACHER_ID" "$TENANT_ID" "$BPM" 2>&1)
ROOM_ID=$(echo "$ROOM_OUTPUT" | grep -E "^MUSIC-" | head -1)

if [ -z "$ROOM_ID" ]; then
    echo "❌ Failed to create room"
    echo "$ROOM_OUTPUT"
    exit 1
fi

echo ""
echo "✅ Room created: $ROOM_ID"
echo ""

# Launch test users
echo "🚀 Launching test users..."
./demo/launch-test-users.sh "$ROOM_ID"

echo ""
echo "✨ Setup complete!"
echo ""
echo "📋 Quick reference:"
echo "   Room ID: $ROOM_ID"
echo "   Teacher: $TEACHER_ID"
echo "   Students: student-1, student-2, student-3, student-4"
echo ""
echo "💡 All browser tabs should auto-fill with room ID and user IDs."
echo "   Just click 'Join Room' in each tab!"

