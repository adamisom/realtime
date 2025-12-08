# Demo WebSocket Connection Troubleshooting

## Problem Summary

The demo client cannot establish a WebSocket connection to the server. The connection fails with error 1006 (abnormal closure) before the WebSocket handshake completes.

**Symptoms:**
- Browser console shows: `WebSocket connection to 'ws://localhost:4000/socket/websocket?...' failed:`
- Error code: 1006 (abnormal closure)
- Server logs show: `[info] GET /socket` but no WebSocket connection logs
- No errors in server IEx console (connection never reaches `connect/3` function)

## Attempted Fixes

### 1. Subdomain DNS Resolution (FAILED)
**Theory:** Browser couldn't resolve `test-tenant.localhost` subdomain

**Attempts:**
- Added `127.0.0.1 test-tenant.localhost` to `/etc/hosts`
- Verified DNS resolution with `ping test-tenant.localhost` (works)
- Restarted browser multiple times
- Tried incognito/private window

**Result:** Still fails with error 1006. Browser appears to have DNS resolution issues even though terminal `ping` works.

**Files Changed:**
- `demo/index.html`: WebSocket URL uses `test-tenant.localhost:4000`

### 2. WebSocket URL Construction (PARTIALLY FIXED)
**Theory:** Phoenix Socket was mangling the URL when query params were included

**Attempts:**
- Initially tried: `ws://localhost:4000/socket?tenant_id=test-tenant`
- Phoenix added `/websocket` after query string, creating malformed URL
- Fixed by passing `tenant_id` in socket `params` instead of URL query

**Result:** URL is now correct: `ws://localhost:4000/socket/websocket?apikey=...&tenant_id=test-tenant&vsn=2.0.0`
But connection still fails with error 1006.

**Files Changed:**
- `demo/index.html`: Pass `tenant_id` in socket params object
- `lib/realtime_web/channels/user_socket.ex`: Read tenant from socket params when hostname is `localhost`

### 3. Server-Side Tenant Extraction (IMPLEMENTED)
**Theory:** Server needs to extract tenant from socket params when using `localhost`

**Implementation:**
- Modified `UserSocket.connect/3` to check if hostname is `localhost`
- If so, read `tenant_id` from socket `params` instead of hostname
- Added logging to track tenant extraction

**Result:** Code is in place, but connection fails before `connect/3` is called (no logs appear).

**Files Changed:**
- `lib/realtime_web/channels/user_socket.ex`: Added fallback tenant extraction from params

### 4. Server Logging (ADDED)
**Theory:** Need more visibility into what's happening on the server

**Implementation:**
- Added `Logger.info` statements in `connect/3` function
- Log tenant extraction
- Log connection success/failure

**Result:** No logs appear, confirming connection never reaches `connect/3` function.

**Files Changed:**
- `lib/realtime_web/channels/user_socket.ex`: Added debug logging

## Current State

**Working:**
- ✅ Token generation and passing (JWT tokens are valid and included in URL)
- ✅ URL construction (WebSocket URL is correctly formatted)
- ✅ Server is running and accepting HTTP requests (`GET /socket` appears in logs)
- ✅ DNS resolution works from terminal (`ping test-tenant.localhost` succeeds)

**Not Working:**
- ❌ WebSocket handshake never completes
- ❌ Connection fails with error 1006 before reaching server `connect/3` function
- ❌ No server-side logs from `connect/3` function

## Theories (Unproven)

### Theory 1: Browser WebSocket Security Policy
**Hypothesis:** Browsers may block WebSocket connections to `localhost` with certain configurations or security policies.

**Evidence:**
- Connection works from terminal (`ping` succeeds)
- Browser can't establish WebSocket connection
- Error 1006 suggests connection is rejected before handshake

**Not Tested:**
- Different browsers (Chrome, Firefox, Safari)
- Browser security settings
- WebSocket protocol restrictions

### Theory 2: Phoenix Endpoint Configuration
**Hypothesis:** The Phoenix endpoint might not be configured to accept WebSocket connections on `localhost` without a subdomain.

**Evidence:**
- Server accepts HTTP requests (`GET /socket` appears)
- WebSocket upgrade might be failing
- No WebSocket-specific logs

**Not Tested:**
- Endpoint configuration for WebSocket transport
- Check if WebSocket transport is enabled
- Verify endpoint is listening on correct interface

### Theory 3: Cowboy/Transport Layer Issue
**Hypothesis:** The underlying Cowboy HTTP server might be rejecting the WebSocket upgrade request.

**Evidence:**
- HTTP requests work
- WebSocket upgrade fails silently
- Error 1006 is a transport-level error

**Not Tested:**
- Cowboy logs (if available)
- WebSocket upgrade request/response headers
- Network packet inspection

### Theory 4: Token/Authorization Pre-Validation
**Hypothesis:** Something might be rejecting the connection before it reaches Phoenix Socket, possibly related to authentication.

**Evidence:**
- Token is valid and properly formatted
- Connection fails before `connect/3` is called
- No authentication errors in logs

**Not Tested:**
- Connection without token
- Different token formats
- Authorization middleware

## Next Steps to Try

1. **Test with different browser** (Firefox, Safari) to rule out Chrome-specific issues
2. **Check Phoenix endpoint configuration** - verify WebSocket transport is enabled
3. **Test WebSocket connection directly** using `websocat` or similar tool:
   ```bash
   echo '{"topic":"test","event":"phx_join","payload":{},"ref":"1"}' | \
     websocat ws://localhost:4000/socket/websocket?vsn=2.0.0
   ```
4. **Check Cowboy/transport logs** - see if upgrade request is being received
5. **Try connecting without authentication** - see if issue is auth-related
6. **Inspect network traffic** - use browser DevTools Network tab to see WebSocket handshake
7. **Check server configuration** - verify `check_origin` and other WebSocket settings in `config/dev.exs`
8. **Test with a simple Phoenix Socket example** - verify WebSocket works at all on this server

## Files Modified

- `demo/index.html`: WebSocket URL construction, token handling, debugging
- `lib/realtime_web/channels/user_socket.ex`: Tenant extraction from params, logging
- `demo/demo-test-setup.sh`: Token generation prompts
- `demo/demo-launch-test-users.sh`: URL construction with tokens
- `demo/demo-diagnose.sh`: Diagnostic script

## Key Observations

1. **Connection never reaches server code** - `connect/3` function is never called
2. **HTTP requests work** - Server accepts `GET /socket` requests
3. **WebSocket upgrade fails** - Handshake never completes
4. **Error 1006** - Transport-level failure, not application-level
5. **No server errors** - Server doesn't log any errors, suggesting rejection happens at transport layer

## Configuration Checkpoints

- [ ] Verify `config/dev.exs` has WebSocket transport enabled
- [ ] Check `check_origin` setting in endpoint config
- [ ] Verify Cowboy is configured for WebSocket upgrades
- [ ] Check if any middleware is blocking WebSocket connections
- [ ] Verify port 4000 is not blocked by firewall

## Related Files

- `lib/realtime_web/endpoint.ex` - Phoenix endpoint configuration
- `config/dev.exs` - Development environment config
- `lib/realtime_web/channels/user_socket.ex` - WebSocket connection handler
- `demo/index.html` - Client-side WebSocket connection

