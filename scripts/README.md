# Music Extension Test Scripts

Automated testing scripts for the music extension with error recovery and failure reporting.

## Quick Start

Run the automated test suite:

```bash
./scripts/test_music_extension.sh
```

Or directly with mix:

```bash
mix run scripts/test_music_extension.exs
```

## What It Tests

The automated test script covers **24 tests** across 5 categories:

### Core Features (6 tests)
- Room Creation (line 115) - Creates room, validates ID format (MUSIC-####)
- Get Room (line 121) - Retrieves room and validates BPM/teacher_id
- Join Room (line 127) - Single student joins room
- Multiple Students Join (line 133) - Multiple students join room
- Beat Assignment (line 140) - Assigns beat to student
- Clear Beat Assignment (line 146) - Clears beat assignment

### Tempo Server (6 tests)
- Start Tempo Server (line 158) - Verifies tempo server starts and registers
- Get Tempo (line 181) - Retrieves current BPM (120)
- Set Tempo (line 186) - Changes tempo to 140 BPM
- Invalid BPM Rejected (line 192) - Rejects BPM 0 (out of range)
- Start Clock (line 197) - Starts the beat clock
- Stop Clock (line 206) - Stops the beat clock

### Game Features (6 tests)
- Set Game Type - Melody Builder (line 223) - Sets game type
- Update Game State (line 229) - Updates game state with melody sequence
- Start Turn Rotation (line 242) - Starts turn rotation with student queue
- Set Call Pattern (line 254) - Sets call pattern for call-and-response
- Record Response (line 261) - Records student response pattern
- Validate Response (line 266) - Validates response and returns match/accuracy

### Database Persistence (3 tests)
- Save Game Session (line 281) - Saves game session to database
- Load Game Sessions (line 303) - Loads saved sessions from database
- SEL Participation Logging (line 318) - Logs SEL participation events

### Error Handling (3 tests)
- Get Non-Existent Room (line 354) - Returns `:not_found` for invalid room
- Invalid BPM Range (line 359) - Rejects BPM > 299
- Game Type Validation (line 364) - Validates game type changes

## Features

### ✅ Error Recovery
- Tests continue even if individual tests fail
- Graceful error handling with try/catch
- No test stops the entire suite

### 📊 Failure Reporting
- Collects all failures with error messages
- Reports success rate and test counts
- Detailed failure information with timestamps

### 🔄 Graceful Degradation
- Handles missing dependencies
- Skips tests that require unavailable resources
- Continues with remaining tests

## Output

The script provides:
- Real-time test progress (✅/❌ indicators)
- Summary statistics (total, passed, failed, success rate)
- Detailed failure reports with error messages
- Exit code: 0 for success, 1 for failures

## Prerequisites

- Elixir and Mix installed
- Database accessible (for persistence tests)
- Application dependencies installed (`mix deps.get`)
- Application compiled (`mix compile`)

## Troubleshooting

### "mix command not found"
Install Elixir: https://elixir-lang.org/install.html

### Database connection errors
- Ensure database is running
- Run migrations: `mix ecto.migrate`
- Check database configuration in `config/`

### Module not found errors
- Ensure dependencies are installed: `mix deps.get`
- Compile the application: `mix compile`

### Tests fail but manual testing works
- Check server is running: `mix phx.server` (for some tests)
- Verify tenant setup and database access
- Check application logs for errors

## Extending the Script

To add new tests, edit `scripts/test_music_extension.exs` and add test cases to the appropriate test suite function:

```elixir
|> test("My New Test", fn s ->
  # Your test code here
  assert condition, "Error message if fails"
  s
end)
```

The `test/3` helper automatically handles error recovery and failure collection.

