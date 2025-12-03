# Quality Guidelines for Music Extension Implementation

**Purpose:** Quality checklist and guidelines to review before considering implementation complete. Use this document during Phase 7 (Integration & Polish) and as a final review before production deployment.

**Last Updated:** December 2024

---

## Security Review

### ✅ Authorization & Access Control

- [ ] **Role extraction from JWT:** All role checks use `socket.assigns.claims["role"]`, not client-provided `params["role"]`
- [ ] **Tenant isolation:** All operations verify `tenant_id` matches before allowing access
- [ ] **Teacher-only operations:** All teacher controls (tempo, muting, game controls) verify role before execution
- [ ] **Student permissions:** Students cannot access teacher-only features
- [ ] **Authorization logging:** Failed authorization attempts are logged for security monitoring

**Check:**
```elixir
# ✅ Good: Extract from JWT
role = socket.assigns.claims["role"] || "student"

# ❌ Bad: Trust client
role = params["role"] || "student"
```

### ✅ Input Validation

- [ ] **MIDI note validation:** All MIDI values are in range 0-127
- [ ] **Velocity validation:** All velocity values are in range 0-127
- [ ] **BPM validation:** All tempo values are in valid range (1-299)
- [ ] **Room ID validation:** Room IDs are verified to exist before operations
- [ ] **Student ID validation:** Student IDs are validated (not empty, not nil)

### ✅ Rate Limiting

- [ ] **Note play rate limiting:** Students limited to configured rate (default 10/sec)
- [ ] **Teacher rate limiting:** Teachers have higher limit (default 50/sec)
- [ ] **Rate limit errors:** Rate limit exceeded returns clear error message
- [ ] **Rate limit per tenant:** Rate limits are isolated per tenant

---

## Performance & Reliability

### ✅ Timing Accuracy

- [ ] **Tempo drift fix:** Tempo server recalculates from current time (not fixed intervals)
- [ ] **Beat accuracy:** Beats arrive within ±50ms of expected time
- [ ] **Tempo changes:** Tempo changes don't cause accumulated drift
- [ ] **Long sessions:** Timing remains accurate for sessions > 5 minutes

**Check:**
```elixir
# ✅ Good: Recalculate from current time
now = System.monotonic_time(:millisecond)
next_beat_time = now + ms_per_beat
timer_ref = schedule_beat_at(next_beat_time)

# ❌ Bad: Fixed interval (drifts over time)
timer_ref = Process.send_after(self(), :beat, ms_per_beat)
```

### ✅ Resource Management

- [ ] **Room cleanup:** Expired/inactive rooms are cleaned up periodically
- [ ] **Tempo server cleanup:** Tempo servers are stopped when rooms are closed
- [ ] **Memory usage:** Memory usage is reasonable (monitor in production)
- [ ] **Process lifecycle:** All GenServers have proper shutdown handling

### ✅ Error Handling

- [ ] **Graceful degradation:** Errors don't crash the entire system
- [ ] **Error messages:** Error responses are clear and actionable
- [ ] **Logging:** Errors are logged with sufficient context
- [ ] **Recovery:** System recovers gracefully from transient failures

---

## Testing Coverage

### ✅ Unit Tests

- [ ] **Core logic:** All GenServer modules have unit tests
- [ ] **Edge cases:** Edge cases are tested (empty lists, nil values, boundary conditions)
- [ ] **Error paths:** Error conditions are tested
- [ ] **Validation:** Input validation is tested

### ✅ Integration Tests

- [ ] **Channel events:** All channel events are tested end-to-end
- [ ] **PubSub broadcasts:** Broadcasts are verified in integration tests
- [ ] **Multi-tenant:** Tenant isolation is tested
- [ ] **Timing:** Timing-sensitive features are tested (with `async: false`)

### ✅ Test Quality

- [ ] **Test isolation:** Tests don't interfere with each other
- [ ] **Test speed:** Tests run in reasonable time (< 30 seconds for full suite)
- [ ] **Test reliability:** Tests are not flaky (run multiple times to verify)
- [ ] **Coverage:** Critical paths have good test coverage (> 80%)

**See `docs/IMPLEMENTATION_TESTS.md` for testing best practices and examples.**

---

## Code Quality

### ✅ Elixir Best Practices

- [ ] **Pattern matching:** Uses pattern matching instead of conditionals where appropriate
- [ ] **Pipe operator:** Uses `|>` for readable data transformations
- [ ] **Function clauses:** Uses multiple function clauses instead of large if/else blocks
- [ ] **Guard clauses:** Uses guard clauses for validation
- [ ] **Documentation:** All public functions have `@doc` comments

### ✅ Multi-Tenant Patterns

- [ ] **Explicit tenant_id:** All functions that need tenant isolation accept `tenant_id` as parameter
- [ ] **Tenant verification:** All operations verify `tenant_id` matches before proceeding
- [ ] **Registry keys:** Registry keys include `tenant_id` to prevent collisions
- [ ] **PubSub topics:** PubSub topics use `Tenants.tenant_topic/3` for correct isolation

**See `docs/ELIXIR_IDIOMS_TENANT.md` for tenant isolation patterns.**

### ✅ Linting & Formatting

- [ ] **Credo:** All Credo checks pass (`mix credo --strict`)
- [ ] **Dialyzer:** Dialyzer passes without errors (`mix dialyzer`)
- [ ] **Sobelow:** Security checks pass (`mix sobelow`)
- [ ] **Format:** Code is formatted (`mix format`)

---

## Architecture & Design

### ✅ Separation of Concerns

- [ ] **GenServer responsibilities:** Each GenServer has a clear, single responsibility
- [ ] **Channel handlers:** Channel handlers are focused and delegate to GenServers
- [ ] **Business logic:** Business logic is in GenServers, not channels
- [ ] **State management:** State is managed appropriately (in-memory vs database)

### ✅ Scalability Considerations

- [ ] **Bottlenecks identified:** Known bottlenecks are documented (e.g., SessionManager)
- [ ] **Sharding strategy:** Sharding strategy is considered for high-scale scenarios
- [ ] **Database persistence:** Database persistence is implemented for critical state (Phase 6)
- [ ] **Monitoring:** Key metrics are identified for production monitoring

**See `docs/CODEBASE_ARCHITECTURE.md` for scalability considerations.**

### ✅ Backward Compatibility

- [ ] **API compatibility:** New features don't break existing API contracts
- [ ] **Default values:** Optional parameters have sensible defaults
- [ ] **Migration path:** Database migrations have rollback strategies

---

## Documentation

### ✅ Code Documentation

- [ ] **Module docs:** All modules have `@moduledoc` explaining purpose
- [ ] **Function docs:** All public functions have `@doc` with examples
- [ ] **Type specs:** Complex functions have `@spec` annotations
- [ ] **Examples:** Examples in docs are accurate and tested

### ✅ Implementation Documentation

- [ ] **Implementation plan:** IMPLEMENTATION_PLAN.md is up to date
- [ ] **Test examples:** IMPLEMENTATION_TESTS.md has examples for all phases
- [ ] **Architecture docs:** CODEBASE_ARCHITECTURE.md covers music extension
- [ ] **API reference:** API usage is documented (see MUSIC_EXTENSION_SUMMARY.md)

---

## Deployment Readiness

### ✅ Configuration

- [ ] **Environment variables:** All configurable values use environment variables
- [ ] **Default values:** Sensible defaults for all configuration
- [ ] **Config validation:** Configuration is validated on startup
- [ ] **Feature flags:** Feature flags are used for gradual rollout (if needed)

### ✅ Monitoring & Observability

- [ ] **Logging:** Important events are logged (room creation, errors, rate limits)
- [ ] **Metrics:** Key metrics are tracked (room count, tempo server count, rate limit rejections)
- [ ] **Health checks:** Health check endpoints verify system health
- [ ] **Alerting:** Critical errors trigger alerts (if monitoring system in place)

### ✅ Database

- [ ] **Migrations:** All database migrations are tested
- [ ] **Rollback:** Migration rollback is tested
- [ ] **Indexes:** Appropriate indexes are created for queries
- [ ] **Data integrity:** Constraints ensure data integrity

---

## Final Checklist

Before considering implementation complete:

- [ ] All phases in IMPLEMENTATION_PLAN.md are complete
- [ ] All tests pass (`mix test`)
- [ ] All linters pass (`mix credo --strict`, `mix dialyzer`, `mix sobelow`)
- [ ] Code is formatted (`mix format`)
- [ ] Documentation is up to date
- [ ] Security review completed (authorization, input validation)
- [ ] Performance review completed (timing, resource management)
- [ ] Architecture review completed (scalability, design)
- [ ] Deployment plan is ready (config, monitoring, database)

---

## Priority Order

If time is limited, focus on these in order:

1. **Security** (authorization, input validation) - Must fix before production
2. **Correctness** (timing accuracy, error handling) - Must fix before production
3. **Testing** (coverage, reliability) - Should have before production
4. **Code quality** (linting, documentation) - Should have before production
5. **Performance** (scalability, monitoring) - Can optimize after initial deployment

---

**Remember:** Quality is not about perfection, but about ensuring the system is secure, reliable, and maintainable. Use this checklist as a guide, not a rigid requirement.


