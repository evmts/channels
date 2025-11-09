# ADR-0002: Event Serialization Format

<adr-metadata>
**Status:** Accepted | **Date:** 2025-11-08 | **Deciders:** Core Team | **Related:** ADR-0001, ADR-0003 | **Phase:** 1
</adr-metadata>

## Context

<context>
**Problem:** Events must be serialized for storage, transmission, and ID derivation. Need format that balances debuggability, performance, schema evolution, and cross-language compatibility.

**Constraints:**
- Must support ID derivation (deterministic serialization)
- Human-readable for debugging (cat event.log should be useful)
- Schema evolution (add fields without breaking old events)
- Cross-language (potential TypeScript/Rust clients)
- Performance acceptable for <10K events per channel per day

**Assumptions:**
- Typical event: <1KB serialized
- Event log files opened infrequently (debugging, not hot path)
- Storage cost acceptable for JSON overhead (~2x vs binary)
- Performance target: parse <1ms per event

**Affected:**
- Event ID derivation (canonical JSON required)
- EventStore persistence (Phase 4 RocksDB migration)
- Event log debugging workflows
- Cross-language client implementations
</context>

## Drivers

<drivers>
**Top 5 factors (prioritized):**
1. **Debuggability (10):** Human-readable event logs for development
2. **Determinism (10):** Canonical form for ID derivation
3. **Schema Evolution (8):** Add fields without breaking changes
4. **Simplicity (7):** std.json available, no external deps
5. **Performance (6):** Parse <1ms per event, <10MB for 10K events

**Ex:** JSON provides human-readable logs (`cat event.log` useful), deterministic canonical form (sorted keys for ID derivation), schema flexibility (optional fields), and std.json stdlib support (no deps).
</drivers>

## Options

<options>
### Opt 1: JSON (std.json)

**Desc:** JSON with canonical form for ID derivation. Use std.json for serialization/deserialization.

**Pros:**
- ✅ Human-readable (debugging, log inspection)
- ✅ Schema evolution (optional fields, unknown field tolerance)
- ✅ Canonical form (sorted keys, deterministic)
- ✅ Cross-language support (every language has JSON)
- ✅ No external dependencies (std.json built-in)

**Cons:**
- ❌ Larger size (~2x vs binary)
- ❌ Slower parsing (~1ms vs ~0.1ms binary)
- ❌ No schema validation (runtime errors vs compile-time)

**Effort:** Small (std.json + canonical JSON implementation complete ✅ Phase 1a)

```zig
const json = try std.json.stringifyAlloc(allocator, event, .{});
const canonical = try canonicalizeJson(allocator, json);
const event_id = keccak256(canonical);
```

### Opt 2: MessagePack

**Desc:** Efficient binary serialization, smaller than JSON, faster parsing.

**Pros:**
- ✅ Compact (~50% smaller than JSON)
- ✅ Faster parsing (~0.3ms vs ~1ms)
- ✅ Schema evolution support
- ✅ Cross-language libraries available

**Cons:**
- ❌ Not human-readable (binary format)
- ❌ No Zig stdlib support (external dependency)
- ❌ Canonical form not standard (need custom implementation)
- ❌ Debugging harder (need msgpack tools to inspect)

**Effort:** Medium (find/integrate Zig library, implement canonical form)

### Opt 3: Protocol Buffers

**Desc:** Google's binary format with schema-first design.

**Pros:**
- ✅ Compact binary format
- ✅ Schema validation (compile-time)
- ✅ Backward/forward compatibility
- ✅ Code generation

**Cons:**
- ❌ Not human-readable
- ❌ Schema changes require recompilation
- ❌ No official Zig support (external dependency)
- ❌ Heavier tooling (protoc compiler)
- ❌ Canonical form not built-in

**Effort:** Large (integrate protobuf library, schema management, codegen)

### Opt 4: Custom Binary Format

**Desc:** Hand-rolled binary encoding optimized for our event types.

**Pros:**
- ✅ Maximum compactness
- ✅ Fastest parsing (optimized for our use case)
- ✅ Full control over format

**Cons:**
- ❌ Not human-readable
- ❌ No cross-language support
- ❌ High maintenance burden
- ❌ Schema evolution manual
- ❌ Likely to have bugs

**Effort:** Extra-Large (design, implement, test, maintain)

### Comparison

|Criterion (weight)|JSON (Opt1)|MessagePack (Opt2)|Protobuf (Opt3)|Custom (Opt4)|
|------------------|-----------|------------------|---------------|-------------|
|Debuggability (10)|10→100|2→20|2→20|1→10|
|Determinism (10)|10→100|7→70|8→80|10→100|
|Schema Evolution (8)|9→72|8→64|9→72|6→48|
|Simplicity (7)|10→70|6→42|4→28|3→21|
|Performance (6)|6→36|8→48|9→54|10→60|
|**Total**|**378**|**244**|**254**|**239**|
</options>

## Decision

<decision>
**Choose:** JSON (std.json) for Phase 1, with migration path to MessagePack in Phase 4 if needed

**Why:**
- Human-readable logs critical for development/debugging
- std.json available (no dependencies, simple implementation)
- Canonical JSON implementation complete (Phase 1a ✅)
- Schema evolution straightforward (optional fields)
- Performance acceptable for P1-P3 (<10K events per channel)

**Decision Point (Phase 4):** Migrate to MessagePack if:
- Event logs >100MB per channel (size bottleneck)
- Parse time >1s for typical reconstruction (performance bottleneck)
- Production deployment with high event volume

**Trade-offs accepted:**
- Larger storage (~2x vs binary) acceptable for development phase
- Slower parsing (~1ms vs ~0.1ms) acceptable given <10K events
- No compile-time schema validation (rely on runtime + tests)

**Mitigation:**
- Monitor log sizes, set alert at 50MB per channel
- Benchmark parse performance, set alert at P95 >10ms
- Plan MessagePack migration in Phase 4 if thresholds exceeded
- Keep serialization abstracted (easy format swap)
</decision>

## Consequences

<consequences>
**Pos:**
- ✅ Human-readable event logs (cat/grep/jq work)
- ✅ No external dependencies (std.json only)
- ✅ Canonical JSON implementation complete (ID derivation working)
- ✅ Schema evolution straightforward (optional fields)
- ✅ Cross-language compatible (every language has JSON)

**Neg:**
- ❌ Larger storage (~2x vs binary formats)
- ❌ Slower parsing (~1ms vs ~0.1ms binary)
- ❌ No compile-time schema validation

**Mitigate:**
- Storage → Monitor sizes, migrate to MessagePack if >100MB
- Performance → Benchmark early, optimize or migrate if bottleneck
- Validation → Runtime checks + comprehensive test coverage + JSON Schema
</consequences>

## Implementation

<implementation>
**Structure:**
```
src/event_store/
├── events.zig           # Event union with toJson/fromJson ✅ Phase 1a
├── id.zig               # Canonical JSON + keccak256 ✅ Phase 1a
└── events.test.zig      # Serialization roundtrip tests ✅ Phase 1a

schemas/events/
└── *.schema.json        # JSON Schema 2020-12 definitions ✅ Phase 1a
```

**Canonical JSON (implemented Phase 1a):**
```zig
pub fn canonicalizeJson(allocator: Allocator, json: []const u8) ![]u8 {
    // 1. Parse JSON
    // 2. Sort keys recursively
    // 3. Remove whitespace
    // 4. Escape special chars
    // 5. Return deterministic bytestring
}
```

**Event Serialization:**
```zig
pub const Event = union(enum) {
    objective_created: ObjectiveCreatedEvent,
    // ... 19 other event types

    pub fn toJson(self: Event, allocator: Allocator) ![]u8 {
        return try std.json.stringifyAlloc(allocator, self, .{});
    }

    pub fn fromJson(allocator: Allocator, json: []const u8) !Event {
        return try std.json.parseFromSlice(Event, allocator, json, .{});
    }
};
```

**Tests (implemented Phase 1a):**
- Serialization roundtrip (event → JSON → event)
- Canonical JSON determinism (same input → same output)
- Golden vectors (ID stability across runs)
- Edge cases (nested objects, arrays, special chars)

**Docs:**
- `docs/architecture/event-types.md` - Event catalog with JSON examples ✅
- JSON Schema files for all events ✅

**Migration Path (Phase 4):**
If migrating to MessagePack:
1. Implement MessagePack canonical form
2. Add format version to event metadata
3. Support both formats during transition
4. Migrate old events in background
5. Deprecate JSON after migration complete
</implementation>

## Validation

<validation>
**Metrics:**
- Serialization performance: <1ms per event P95
- Event log size: <10MB per channel per 24h (typical)
- Parse errors: 0% for valid events
- Developer satisfaction: logs useful for debugging

**Monitor:**
- Event log file sizes (alert if >50MB per channel)
- Serialization/parse latency (P50/P95/P99)
- Parse error rate
- Time spent debugging with logs

**Review:**
- 3mo: Size/performance acceptable? Debugging experience good?
- 6mo: Event volume increased? Migration needed?
- 12mo: JSON still best choice? New formats emerged?

**Revise if:**
- Event logs exceed 100MB per channel (migrate to MessagePack)
- Parse time >1s for typical reconstruction (optimize or migrate)
- Debugging workflows don't use logs (binary format acceptable)
- Compile-time validation becomes critical (consider Protobuf)
</validation>

## Related

<related>
**ADR Dependencies:**
- **Depends on:** ADR-0001 (Event Sourcing Strategy)
- **Informs:** ADR-0003 (Storage Backend P1)
- **Informs:** Future ADR (Phase 4 RocksDB integration)

**Project Context:**
- **PRD:** [prd.md](../prd.md) §4.1 - Event Sourcing Architecture
- **Context:** [context.md](../context.md) - State Channel Prior Art
- **Phase:** [.claude/commands/1_phase_1_event_sourcing.md](../../.claude/commands/1_phase_1_event_sourcing.md)
- **Architecture:** [docs/architecture/event-types.md](../architecture/event-types.md) ✅

**Implementation:**
- **Code:** `src/event_store/events.zig`, `src/event_store/id.zig` ✅
- **Tests:** `src/event_store/events.test.zig` ✅
- **Schemas:** `schemas/events/*.schema.json` ✅

**External References:**
- [RFC 8259](https://tools.ietf.org/html/rfc8259) - JSON specification
- [RFC 8785](https://tools.ietf.org/html/rfc8785) - JSON Canonicalization Scheme (JCS)
- [JSON Schema](https://json-schema.org/) - Schema definition format
- [MessagePack](https://msgpack.org/) - Alternative binary format
</related>

<changelog>
- 2025-11-08: Initial (Accepted) - Phase 1b
</changelog>
