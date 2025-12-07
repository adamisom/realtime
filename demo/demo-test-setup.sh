#!/bin/bash
# Complete test setup: creates room and launches test users
# Usage: ./demo/demo-test-setup.sh [teacher_id] [tenant_id] [bpm]

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
echo ""
echo "⚠️  Note: If server is already running, run this in IEx instead:"
echo "   {:ok, room_id} = Realtime.Music.SessionManager.create_room(\"$TEACHER_ID\", \"$TENANT_ID\", bpm: $BPM)"
echo ""
read -p "Continue with mix run? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Please create room manually in IEx, then run:"
    echo "  ./demo/demo-launch-test-users.sh <ROOM_ID>"
    exit 0
fi

ROOM_OUTPUT=$(mix run --no-start -e "
  Application.ensure_all_started(:realtime)
  alias Realtime.Music.SessionManager
  case SessionManager.create_room(\"$TEACHER_ID\", \"$TENANT_ID\", bpm: $BPM) do
    {:ok, room_id} -> IO.puts(room_id)
    {:error, reason} -> IO.puts(\"ERROR: #{inspect(reason)}\"); System.halt(1)
  end
" 2>&1)
ROOM_ID=$(echo "$ROOM_OUTPUT" | grep -E "^MUSIC-" | head -1)

if [ -z "$ROOM_ID" ]; then
    echo "❌ Failed to create room"
    echo "$ROOM_OUTPUT"
    echo ""
    echo "💡 Try running in IEx console instead:"
    echo "   {:ok, room_id} = Realtime.Music.SessionManager.create_room(\"$TEACHER_ID\", \"$TENANT_ID\", bpm: $BPM)"
    exit 1
fi

echo ""
echo "✅ Room created: $ROOM_ID"
echo ""

# Launch test users
echo "🚀 Launching test users..."
./demo/demo-launch-test-users.sh "$ROOM_ID"

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

