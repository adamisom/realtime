# Music Extension Demo

A single-file HTML demo application that demonstrates the music extension's real-time collaborative music capabilities.

## Quick Start

1. **Start the server:**
   ```bash
   mix phx.server
   ```

2. **Create a room (in IEx or another terminal):**
   ```bash
   iex -S mix
   ```
   ```elixir
   {:ok, room_id} = Realtime.Music.SessionManager.create_room("teacher-1", "test-tenant", bpm: 120)
   # Copy the room_id (e.g., "MUSIC-1234")
   ```

3. **Open the demo:**
   - Open `demo/index.html` in your browser
   - Or serve it: `python3 -m http.server 8080` then visit `http://localhost:8080/demo/`

4. **Join the room:**
   - Select role (Student or Teacher)
   - Enter the room ID (e.g., `MUSIC-1234`)
   - Enter a student ID (e.g., `student-1`)
   - Click "Join Room"

5. **Test with multiple users:**
   - Open the demo in multiple browser tabs
   - Join the same room with different student IDs
   - Play notes and see them sync in real-time!

## Features Demonstrated

- ✅ Real-time note broadcasting
- ✅ Synchronized tempo and beat indicators
- ✅ Multi-user coordination
- ✅ Teacher controls (tempo, beat assignment)
- ✅ Rate limiting
- ✅ Audio synthesis with Tone.js

## Keyboard Shortcuts

- **A, S, D, F, G, H, J, K**: Play notes (C4 to C5)

## Troubleshooting

**Socket won't connect:**
- Ensure server is running: `mix phx.server`
- **Important:** Add tenant to `/etc/hosts` for `.localhost` subdomain resolution:
  ```bash
  echo "127.0.0.1 test-tenant.localhost" | sudo tee -a /etc/hosts
  ```
- Check browser console for WebSocket errors
- Verify JWT token is valid (generate with `mix run demo/demo-generate-token.exs test-tenant teacher`)

**Can't join room:**
- Verify room exists (create in IEx)
- Check room ID format: `MUSIC-####`

**No audio:**
- Click anywhere on the page first (browser autoplay policy)
- Check browser console for errors

**JWT Token Issues:**
- Generate a real token: `mix run demo/demo-generate-token.exs test-tenant teacher`
- Copy the token and add `?token=YOUR_TOKEN` to the demo URL
- Or store in browser localStorage: `localStorage.setItem('demo_jwt_token', 'YOUR_TOKEN')`

## JWT Token Generation

The demo includes a simplified JWT token generator. For a real token:

**Option 1: Generate token via script**
```bash
mix run demo/generate-token.exs test-tenant teacher
# Copy the token and update demo/index.html generateJWT function
```

**Option 2: Generate in IEx**
```elixir
tenant = Realtime.Api.get_tenant_by_external_id("test-tenant")
jwt = Generators.generate_jwt_token(tenant, %{role: "teacher", exp: System.system_time(:second) + 3600})
```

**Option 3: Use existing script**
```bash
mix run priv/repo/generate_test_jwt.exs test-tenant
```

Then update the `generateJWT` function in `demo/index.html` to return the real token, or modify the code to accept a token input field.

## Notes

- JWT token generation is simplified for demo purposes
- For production, generate tokens server-side with proper signing
- Student tracking uses note events (simplified approach)
- For production, use Phoenix Presence for proper tracking

