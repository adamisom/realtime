#!/bin/bash
# Complete test setup: creates room, starts HTTP server, and launches test users
# Usage: ./demo/demo-test-setup.sh [teacher_id] [tenant_id] [bpm] [room_id]
#   If room_id is provided, skips room creation prompt
# The HTTP server will run in the background. To stop it: pkill -f "python3 -m http.server 8080"

set -e

TEACHER_ID="${1:-teacher-1}"
TENANT_ID="${2:-test-tenant}"
BPM="${3:-120}"
ROOM_ID="${4:-}"
HTTP_PORT=8080

echo "🎵 Music Extension Demo - Test Setup"
echo "======================================"
echo ""

# Run diagnostics first
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "🔍 Running quick diagnostics..."
"$SCRIPT_DIR/demo-diagnose.sh" "$TENANT_ID" 2>/dev/null || echo "   (Diagnostics script not found, continuing...)"
echo ""

# Check if Realtime server is running
if ! curl -s http://localhost:4000/healthcheck > /dev/null 2>&1; then
    echo "⚠️  Warning: Realtime server may not be running on localhost:4000"
    echo "   Start it with: iex -S mix phx.server"
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
if [ -z "$ROOM_ID" ]; then
    echo "📝 Creating room..."
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 Create a room in your IEx console:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "   {:ok, room_id} = Realtime.Music.SessionManager.create_room(\"$TEACHER_ID\", \"$TENANT_ID\", bpm: $BPM)"
    echo ""
    echo "   Copy the room_id from the output (e.g., \"MUSIC-1234\")"
    echo ""
    read -p "Paste the room ID here: " ROOM_ID
    echo ""
fi

if [ -z "$ROOM_ID" ]; then
    echo "❌ Room ID is required. Exiting."
    echo ""
    echo "💡 Run this script again and paste the room ID when prompted, or:"
    echo "   ./demo/demo-test-setup.sh $TEACHER_ID $TENANT_ID $BPM <ROOM_ID>"
    echo ""
    exit 1
fi

# Validate room ID format
if [[ ! "$ROOM_ID" =~ ^MUSIC-[0-9]+$ ]]; then
    echo "⚠️  Warning: Room ID format looks incorrect (expected MUSIC-####)"
    echo "   Your room ID: $ROOM_ID"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""
echo "✅ Using room: $ROOM_ID"
echo ""

# Generate JWT tokens
echo "🔑 Generating JWT tokens..."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Copy this command to your IEx console (where server is running):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Application.put_env(:realtime, :db_enc_key, \"1234567890123456\"); alias Realtime.Crypto; tenant = case Realtime.Api.get_tenant_by_external_id(\"$TENANT_ID\") do nil -> case Realtime.Api.create_tenant(%{external_id: \"$TENANT_ID\", name: \"$TENANT_ID\", jwt_secret: \"demo-secret-key-1234567890123456\"}) do {:ok, t} -> t; error -> raise \"Failed to create tenant: #{inspect(error)}\" end; t -> t end; secret = Crypto.decrypt!(tenant.jwt_secret); signer = Joken.Signer.create(\"HS256\", secret); teacher_claims = %{role: \"teacher\", exp: System.system_time(:second) + 3600, iat: System.system_time(:second)}; {:ok, _} = Joken.generate_claims(%{}, teacher_claims); {:ok, teacher_jwt, _} = Joken.encode_and_sign(teacher_claims, signer); IO.puts(teacher_jwt)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -p "Paste the TEACHER token (just the token, no prefix): " TEACHER_TOKEN
TEACHER_TOKEN=$(echo "$TEACHER_TOKEN" | sed 's/^TEACHER_TOKEN=//' | tr -d '\r\n ')

echo ""
echo "Now run this in IEx:"
echo "student_claims = %{role: \"student\", exp: System.system_time(:second) + 3600, iat: System.system_time(:second)}; {:ok, _} = Joken.generate_claims(%{}, student_claims); {:ok, student_jwt, _} = Joken.encode_and_sign(student_claims, signer); IO.puts(student_jwt)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -p "Paste the STUDENT token (just the token, no prefix): " STUDENT_TOKEN
STUDENT_TOKEN=$(echo "$STUDENT_TOKEN" | sed 's/^STUDENT_TOKEN=//' | tr -d '\r\n ')

if [ -z "$TEACHER_TOKEN" ] || [ -z "$STUDENT_TOKEN" ]; then
    echo ""
    echo "❌ Tokens cannot be empty."
    echo ""
    echo "   Debug info:"
    echo "   - TEACHER_TOKEN length: ${#TEACHER_TOKEN}"
    echo "   - STUDENT_TOKEN length: ${#STUDENT_TOKEN}"
    echo ""
    read -p "Continue without tokens? (tabs will open but connection will fail) (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    TEACHER_TOKEN=""
    STUDENT_TOKEN=""
else
    echo ""
    echo "✅ Tokens received!"
    echo "   Teacher token: ${#TEACHER_TOKEN} characters"
    echo "   Student token: ${#STUDENT_TOKEN} characters"
fi

# Launch test users
echo "🚀 Launching test users..."
./demo/demo-launch-test-users.sh "$ROOM_ID" "http://localhost:$HTTP_PORT/index.html" "$TENANT_ID" "$TEACHER_TOKEN" "$STUDENT_TOKEN"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Setup complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Quick reference:"
echo "   Room ID: $ROOM_ID"
echo "   Teacher: $TEACHER_ID"
echo "   Demo URL: http://localhost:$HTTP_PORT/index.html"
echo ""
echo "💡 Browser tab should open automatically with the teacher view."
echo "   Click 'Join Room' to connect!"
echo ""
if [ -n "$HTTP_SERVER_PID" ]; then
    echo "🛑 To stop HTTP server: pkill -f 'python3 -m http.server $HTTP_PORT'"
fi
echo ""
echo "🔍 If connection fails, run diagnostics:"
echo "   ./demo/demo-diagnose.sh $TENANT_ID"
echo ""

