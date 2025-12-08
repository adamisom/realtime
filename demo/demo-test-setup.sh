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

# Generate JWT tokens
echo "🔑 Generating JWT tokens..."
echo ""
echo "💡 Run this SINGLE command in your IEx console, then paste the output here:"
echo ""
echo "   alias Realtime.Crypto; tenant = case Realtime.Api.get_tenant_by_external_id(\"$TENANT_ID\") do nil -> {:ok, t} = Realtime.Api.create_tenant(%{external_id: \"$TENANT_ID\", name: \"$TENANT_ID\", jwt_secret: \"demo-secret-key-1234567890123456\"}); t -> t end; secret = Crypto.decrypt!(tenant.jwt_secret); signer = Joken.Signer.create(\"HS256\", secret); teacher_claims = %{role: \"teacher\", exp: System.system_time(:second) + 3600, iat: System.system_time(:second)}; {:ok, _} = Joken.generate_claims(%{}, teacher_claims); {:ok, teacher_jwt, _} = Joken.encode_and_sign(teacher_claims, signer); student_claims = %{role: \"student\", exp: System.system_time(:second) + 3600, iat: System.system_time(:second)}; {:ok, _} = Joken.generate_claims(%{}, student_claims); {:ok, student_jwt, _} = Joken.encode_and_sign(student_claims, signer); IO.puts(\"TEACHER_TOKEN=\" <> teacher_jwt); IO.puts(\"STUDENT_TOKEN=\" <> student_jwt)"
echo ""
read -p "Paste the output (both TEACHER_TOKEN= and STUDENT_TOKEN= lines): " TOKEN_OUTPUT

TEACHER_TOKEN=$(echo "$TOKEN_OUTPUT" | grep "TEACHER_TOKEN=" | sed 's/TEACHER_TOKEN=//')
STUDENT_TOKEN=$(echo "$TOKEN_OUTPUT" | grep "STUDENT_TOKEN=" | sed 's/STUDENT_TOKEN=//')

if [ -z "$TEACHER_TOKEN" ] || [ -z "$STUDENT_TOKEN" ]; then
    echo "⚠️  Warning: Could not parse tokens. Tabs will open without tokens."
    echo "   You can add tokens manually to URLs later."
    TEACHER_TOKEN=""
    STUDENT_TOKEN=""
else
    echo "✅ Tokens parsed successfully"
fi

# Launch test users
echo "🚀 Launching test users..."
./demo/demo-launch-test-users.sh "$ROOM_ID" "http://localhost:$HTTP_PORT/index.html" "$TENANT_ID" "$TEACHER_TOKEN" "$STUDENT_TOKEN"

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

