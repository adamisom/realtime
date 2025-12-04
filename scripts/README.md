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

The automated test script covers:

### Core Features
- Room creation and management
- Room joining (single and multiple students)
- Beat assignment and clearing
- Tempo server operations
- Tempo get/set operations
- Clock start/stop

### Game Features
- Game type setting
- Game state updates
- Turn rotation
- Call and response pattern matching
- Pattern recording and validation

### Database Persistence
- Game session saving and loading
- SEL participation event logging

### Error Handling
- Non-existent room handling
- Invalid BPM validation
- Game type validation

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

