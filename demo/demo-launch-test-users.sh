#!/bin/bash
# Launch multiple browser tabs for testing with different users
# Usage: ./demo/demo-launch-test-users.sh [room_id] [demo_url] [tenant_id] [teacher_token] [student_token]
# Example: ./demo/demo-launch-test-users.sh MUSIC-1234 http://localhost:8080/index.html test-tenant teacher_token student_token

set -e

ROOM_ID="${1:-}"
DEMO_URL="${2:-}"
TENANT_ID="${3:-test-tenant}"
TEACHER_TOKEN="${4:-}"
STUDENT_TOKEN="${5:-}"

# Get demo URL - use provided URL or default to HTTP server
if [ -z "$DEMO_URL" ]; then
    # Default to HTTP server if running, otherwise file://
    if curl -s http://localhost:8080 > /dev/null 2>&1; then
        DEMO_URL="http://localhost:8080/index.html"
    else
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        DEMO_FILE="$SCRIPT_DIR/index.html"
        if [ -f "$DEMO_FILE" ]; then
            DEMO_URL="file://$DEMO_FILE"
            echo "⚠️  Using file:// protocol (CDN may be blocked)"
            echo "💡 Tip: Start HTTP server for better compatibility:"
            echo "   cd demo && python3 -m http.server 8080"
        else
            echo "❌ Error: demo/index.html not found at $DEMO_FILE"
            echo "Usage: $0 [room_id] [demo_url] [tenant_id] [teacher_token] [student_token]"
            exit 1
        fi
    fi
fi

# If no room ID provided, try to create one
if [ -z "$ROOM_ID" ]; then
    echo "📝 No room ID provided. Creating a new room..."
    ROOM_ID=$(mix run demo/demo-create-room.exs teacher-1 test-tenant 120 2>&1 | grep -E "^MUSIC-" | head -1)
    if [ -z "$ROOM_ID" ]; then
        echo "❌ Failed to create room. Please create one manually:"
        echo "   mix run demo/demo-create-room.exs teacher-1 test-tenant 120"
        exit 1
    fi
    echo "✅ Created room: $ROOM_ID"
fi

echo ""
echo "🚀 Launching test users for room: $ROOM_ID"
echo ""

# Detect OS and browser
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    OPEN_CMD="open -a"
    if command -v "Google Chrome" &> /dev/null; then
        BROWSER="Google Chrome"
    elif command -v "Google Chrome Canary" &> /dev/null; then
        BROWSER="Google Chrome Canary"
    elif command -v "Firefox" &> /dev/null; then
        BROWSER="Firefox"
    else
        BROWSER="Safari"
    fi
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    if command -v google-chrome &> /dev/null; then
        OPEN_CMD="google-chrome"
        BROWSER=""
    elif command -v firefox &> /dev/null; then
        OPEN_CMD="firefox"
        BROWSER=""
    else
        echo "❌ Error: No supported browser found (Chrome or Firefox)"
        exit 1
    fi
else
    echo "❌ Error: Unsupported OS: $OSTYPE"
    exit 1
fi

# Function to open a browser tab with URL params
open_tab() {
    local role=$1
    local user_id=$2
    local tenant_id="${3:-test-tenant}"
    local token=""
    
    # Use appropriate token based on role
    if [ "$role" = "teacher" ] && [ -n "$TEACHER_TOKEN" ]; then
        token="&token=${TEACHER_TOKEN}"
    elif [ "$role" = "student" ] && [ -n "$STUDENT_TOKEN" ]; then
        token="&token=${STUDENT_TOKEN}"
    fi
    
    local url="${DEMO_URL}?room_id=${ROOM_ID}&user_id=${user_id}&role=${role}&tenant_id=${tenant_id}${token}"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        "$OPEN_CMD" "$BROWSER" "$url" 2>/dev/null || open "$url"
    else
        "$OPEN_CMD" "$url" 2>/dev/null &
    fi
    
    sleep 0.5  # Small delay between opens
}

# Launch users
echo "👨‍🏫 Opening teacher..."
open_tab "teacher" "teacher-1" "$TENANT_ID"

echo "👨‍🎓 Opening student 1..."
open_tab "student" "student-1" "$TENANT_ID"

echo "👨‍🎓 Opening student 2..."
open_tab "student" "student-2" "$TENANT_ID"

echo "👨‍🎓 Opening student 3..."
open_tab "student" "student-3" "$TENANT_ID"

echo "👨‍🎓 Opening student 4..."
open_tab "student" "student-4" "$TENANT_ID"

echo ""
echo "✅ Launched 5 browser tabs:"
echo "   - 1 teacher (teacher-1)"
echo "   - 4 students (student-1 through student-4)"
echo ""
echo "📋 Room ID: $ROOM_ID"
if [ -n "$TEACHER_TOKEN" ] && [ -n "$STUDENT_TOKEN" ]; then
    echo "   ✅ JWT tokens included in URLs"
else
    echo "   ⚠️  No JWT tokens provided - tabs will use placeholder tokens"
    echo "   💡 Generate tokens in IEx and pass as 4th and 5th arguments"
fi
echo ""
echo "💡 The demo should auto-fill room ID and user ID from URL parameters."
echo "   If not, manually enter:"
echo "   - Room ID: $ROOM_ID"
echo "   - User IDs: teacher-1, student-1, student-2, student-3, student-4"

