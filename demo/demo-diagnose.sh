#!/bin/bash
# Diagnostic script to check demo setup
# Usage: ./demo/demo-diagnose.sh [tenant_id]

set -e

TENANT_ID="${1:-test-tenant}"
HOSTNAME="${TENANT_ID}.localhost"
PORT=4000

echo "🔍 Demo Diagnostic Tool"
echo "======================"
echo ""

# Check 1: /etc/hosts entry
echo "1️⃣  Checking /etc/hosts entry..."
if grep -q "$HOSTNAME" /etc/hosts 2>/dev/null; then
    echo "   ✅ Found entry in /etc/hosts"
    grep "$HOSTNAME" /etc/hosts | sed 's/^/      /'
else
    echo "   ❌ NOT FOUND in /etc/hosts"
    echo "   💡 Add this line to /etc/hosts:"
    echo "      sudo sh -c 'echo \"127.0.0.1 $HOSTNAME\" >> /etc/hosts'"
fi
echo ""

# Check 2: DNS resolution
echo "2️⃣  Testing DNS resolution..."
if ping -c 1 "$HOSTNAME" > /dev/null 2>&1; then
    echo "   ✅ DNS resolves correctly"
    ping -c 1 "$HOSTNAME" 2>&1 | grep "from" | sed 's/^/      /'
else
    echo "   ❌ DNS does not resolve"
    echo "   💡 After adding to /etc/hosts, restart your browser"
fi
echo ""

# Check 3: Server running
echo "3️⃣  Checking if server is running..."
if curl -s "http://localhost:$PORT/healthcheck" > /dev/null 2>&1; then
    echo "   ✅ Server is running on port $PORT"
    HEALTH=$(curl -s "http://localhost:$PORT/healthcheck" 2>/dev/null || echo "unknown")
    echo "      Health check: $HEALTH"
else
    echo "   ❌ Server is NOT running on port $PORT"
    echo "   💡 Start server with: iex -S mix phx.server"
fi
echo ""

# Check 4: Tenant in database (if server is running)
echo "4️⃣  Checking if tenant exists in database..."
if curl -s "http://localhost:$PORT/healthcheck" > /dev/null 2>&1; then
    echo "   💡 To check tenant, run this in IEx:"
    echo "      Realtime.Api.get_tenant_by_external_id(\"$TENANT_ID\")"
    echo "   💡 If nil, create it with the command from demo-test-setup.sh"
else
    echo "   ⏭️  Skipping (server not running)"
fi
echo ""

# Check 5: HTTP server for demo
echo "5️⃣  Checking HTTP server for demo..."
HTTP_PORT=8080
if curl -s "http://localhost:$HTTP_PORT" > /dev/null 2>&1; then
    echo "   ✅ HTTP server is running on port $HTTP_PORT"
    if curl -s "http://localhost:$HTTP_PORT/index.html" > /dev/null 2>&1; then
        echo "   ✅ index.html is accessible"
    else
        echo "   ⚠️  index.html not found (might be in wrong directory)"
    fi
else
    echo "   ⏭️  HTTP server not running (will be started by demo-test-setup.sh)"
fi
echo ""

# Check 6: WebSocket connection test
echo "6️⃣  Testing WebSocket connection..."
if command -v websocat > /dev/null 2>&1; then
    echo "   💡 websocat found - could test connection"
    echo "   💡 Run: echo '{\"topic\":\"test\",\"event\":\"phx_join\",\"payload\":{},\"ref\":\"1\"}' | websocat ws://$HOSTNAME:$PORT/socket/websocket?vsn=2.0.0"
else
    echo "   ⏭️  websocat not installed (optional tool for WebSocket testing)"
fi
echo ""

# Summary
echo "📋 Summary"
echo "=========="
echo ""
echo "Quick fixes:"
echo "  • Add to /etc/hosts: sudo sh -c 'echo \"127.0.0.1 $HOSTNAME\" >> /etc/hosts'"
echo "  • Restart browser after /etc/hosts change"
echo "  • Start server: iex -S mix phx.server"
echo "  • Create tenant: Run IEx command from demo-test-setup.sh"
echo ""
echo "Next steps:"
echo "  • Run: ./demo/demo-test-setup.sh"
echo "  • Follow prompts to create room and generate tokens"
echo ""

