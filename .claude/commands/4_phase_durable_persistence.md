# P4: Durable Persistence

**Meta:** P4 | Deps: P1 | Owner: Core

## Zig RocksDB/C Interop

**C interop:**
- `@cImport/@cInclude` - import C headers
- `std.c.free` - free C-allocated mem (NOT allocator.free)
- `c_allocator` - libc malloc wrapper (misleading name)
- C libs hide allocator, manage own mem

**RocksDB libs:**
- `Syndica/rocksdb-zig` - idiomatic hand-written bindings
- `jiacai2050/zig-rocksdb` - vendored librocksdb v9.0.0

**Mem safety:** C allocations need `std.c.free`, Zig allocations need `allocator.free`. Never mix.

## Summary

Replace in-memory event log with RocksDB. Implements crash recovery via replay, snapshots for fast startup, WAL for atomicity. Critical - without persistence, all state lost on restart (unacceptable production). Swaps storage backend while maintaining EventStore interface.

## Objectives

- OBJ-1: RocksDB as event log backend
- OBJ-2: Crash recovery (replay from durable log)
- OBJ-3: Snapshots (every N events)
- OBJ-4: Atomic writes (WAL for consistency)
- OBJ-5: Recovery scenarios tested (crash, corruption, restart)

## Success Criteria

**Done when:**
- RocksDB integrated, zero mem leaks
- Crash recovery 100% (kill→restart→state matches)
- Snapshots reduce startup: <1s for 10K events
- Atomic writes guaranteed, no corruption
- Perf: <2s append 10K events
- 60+ tests, 90%+ cov
- 2 ADRs approved (RocksDB choice, snapshot freq)
- Docs + recovery tests pass

**Exit gates:** Tests pass, recovery validated, benchmarks met

## Architecture

**Components:** DurableEventStore (RocksDB-backed), SnapshotManager (periodic snapshots), RecoveryEngine (replay on startup), WAL (write-ahead log)

**Flow:**
```
Startup → LoadSnapshot → ReplayEvents(since snapshot) → Ready
Append → WAL → RocksDB → UpdateSnapshot(if N events)
Crash → Restart → Replay → Recovered
```

## ADRs

**ADR-0008: Storage Backend**
- Q: Which DB?
- Opts: A) RocksDB | B) SQLite | C) Custom
- Rec: A
- Why: Embedded, fast, proven, LSM tree fits append-only vs ⚠️ complex (ok worth it)

**ADR-0009: Snapshot Frequency**
- Q: When snapshot?
- Opts: A) Every N events | B) Adaptive | C) On complete
- Rec: A (N=1000)
- Why: Balance startup vs overhead vs ⚠️ arbitrary (ok tune later)

## Data Structures

```zig
pub const DurableEventStore = struct {
    db: *rocksdb.DB,
    write_opts: rocksdb.WriteOptions,
    snapshot_mgr: *SnapshotManager,

    pub fn append(self: *Self, event: Event) !EventOffset;
    pub fn readFrom(self: *Self, offset: EventOffset) ![]Event;
    pub fn recover(self: *Self) !void;
};

pub const SnapshotManager = struct {
    snapshots: HashMap(EventOffset, []u8),

    pub fn createSnapshot(self: *Self, offset: EventOffset) !void;
    pub fn loadLatest(self: *Self) ?EventOffset;
};
```

## APIs

```zig
// Open durable store
pub fn open(path: []const u8, a: Allocator) !*DurableEventStore;

// Append atomically
pub fn append(self: *Self, event: Event) !EventOffset;

// Read from offset
pub fn readFrom(self: *Self, offset: EventOffset) ![]Event;
```

## Implementation

**W1:** Docs (ADRs), RocksDB integration, basic read/write
**W2:** Snapshot create/load, recovery logic
**W3:** Testing (crash, corruption, benchmarks), validation

**Tasks:** T1: Add RocksDB (S) | T2: Wrap C API (M) | T3: DurableEventStore (L) | T4: Snapshots (L) | T5: Recovery (M) | T6: Crash tests (L) | T7: Benchmarks (M) | T8: Corruption tests (M)

**Path:** T1→T2→T3→T4→T5→T6

## Testing

**Unit:** 60+ tests
- Append persists across restarts
- Snapshot reduces replay time
- Corruption detected + handled

**Integration:**
- Crash during funding → restart → state recovered
- 10K events → <1s startup with snapshots

**Benchmarks:**
- Append 10K: <2s
- Restart with snapshot: <1s

## Dependencies

**Req:** P1 (EventStore interface), Zig 0.15+
**External:** Syndica/rocksdb-zig (rec) OR jiacai2050/zig-rocksdb
**Note:** defer/errdefer critical for C interop cleanup

## Risks

|Risk|P|I|Mitigation|
|--|--|--|--|
|RocksDB integration issues|M|H|Existing Zig bindings, 3 days allocated|
|Corruption on crash|L|H|WAL, atomic writes, tests|
|Snapshot bugs lose data|M|H|Validate, checksums, extensive tests|
|Performance worse than mem|L|M|Acceptable if <10x, optimize|

## Deliverables

**Code:** `src/storage/{durable_store,snapshot,recovery}.zig`, tests
**Docs:** ADR-0008/0009, persistence arch, recovery guide
**Val:** 90%+ cov, crash tests pass, benchmarks met

## Validation Gates

- G1: ADRs approved, RocksDB integrated
- G2: Code review, crash tests pass
- G3: Benchmarks met, recovery validated
- G4: Docs complete, production-ready

## Refs

**Phases:** P1 (EventStore)
**ADRs:** 0008 (RocksDB), 0009 (Snapshots), 0001 (Event Sourcing)
**External:** RocksDB docs, state channel persistence patterns

## Example

```zig
// Open durable store
var store = try DurableEventStore.open("data/events.db", allocator);
defer store.close();

// Append events (persisted)
_ = try store.append(event);

// Restart - auto recovers
store.close();
store = try DurableEventStore.open("data/events.db", allocator);
```

---

## CONTEXT FROM PHASE 1 (Event Types for Persistence)

**Phase 1 Status:** Event types defined ✅ | In-memory EventStore → Phase 1b (pending)

### Events to Persist

Phase 1 defined **20 event types** that must be durably stored in RocksDB:

**Event Categories:**
- **Objective Lifecycle (5 events):** objective-created, approved, rejected, cranked, completed
- **Channel State (5 events):** channel-created, state-signed, state-received, state-supported-updated, channel-finalized
- **Chain Bridge (6 events):** deposit-detected, allocation-updated, challenge-registered, challenge-cleared, channel-concluded, withdraw-completed
- **Messaging (4 events):** message-sent, message-received, message-acked, message-dropped

**Event Structure:**
```zig
pub const Event = union(enum) {
    objective_created: ObjectiveCreatedEvent,
    objective_approved: ObjectiveApprovedEvent,
    // ... 18 more variants
    
    pub fn toJson(self: Event, a: Allocator) ![]u8;
    pub fn fromJson(a: Allocator, json: []u8) !Event;
};
```

**Event Identifiers:**
- Each event has deterministic ID: `keccak256("ev1|" + event_name + "|" + canonical_json)`
- Event IDs are content-addressed (different content → different ID)
- Implementation: [src/event_store/id.zig](../../src/event_store/id.zig)

### RocksDB Schema Design

**Key-Value Layout:**

**Option A: Sequential Keys (Append-Optimized)**
```
Key Format: <counter:u64> (8 bytes, big-endian for sorting)
Value: JSON-serialized Event

Example:
0x0000000000000001 → {"objective_created": {...}}
0x0000000000000002 → {"state_signed": {...}}
```

**Option B: Content-Addressed Keys (Deduplication)**
```
Key Format: <event_id:32bytes>
Value: JSON-serialized Event

Example:
0x7a8f3c2e... → {"state_signed": {...}}
```

**Recommendation:** Use **Option A** with secondary index on event_id
- Primary store: Sequential append (optimal for RocksDB LSM tree)
- Secondary index: event_id → offset (for deduplication checks)

### Serialization for Persistence

**Format:** JSON (from Phase 1 ADR-0002)

**Why JSON for P4:**
- Human-readable durability (debug crashes via cat file)
- Schema evolution (add fields without migration)
- Proven in production systems
- Acceptable size (<100MB for <10K events)

**Serialization API (already implemented):**
```zig
const event = Event{ .objective_created = ... };
const json = try event.toJson(allocator);  // Implemented in events.zig
defer allocator.free(json);

// Store in RocksDB
try db.put(key, json);

// Retrieve
const stored_json = try db.get(key, allocator);
const restored = try Event.fromJson(allocator, stored_json);
```

**Note:** toJson/fromJson need to be implemented in Phase 1b or Phase 2 (currently stub)

### Recovery & Replay

**Crash Recovery Flow:**
1. Open RocksDB at startup
2. Scan sequential keys from 0 → max
3. Deserialize each Event via `fromJson`
4. Replay through StateReconstructor (Phase 1b)
5. Rebuild in-memory state (objectives, channels)

**Example:**
```zig
pub fn recoverFromDisk(
    db: *RocksDB,
    reconstructor: *StateReconstructor,
    allocator: Allocator
) !void {
    var offset: u64 = 0;
    while (true) {
        const key = std.mem.toBytes(offset);
        const json = db.get(key, allocator) catch |err| {
            if (err == error.NotFound) break;
            return err;
        };
        defer allocator.free(json);
        
        const event = try Event.fromJson(allocator, json);
        try reconstructor.apply(event);
        
        offset += 1;
    }
}
```

### Snapshot Schema

**Snapshot Key:**
```
Key Format: "snapshot:<offset:u64>"
Value: Serialized State Snapshot

Example:
snapshot:1000 → {objectives: [...], channels: [...]}
snapshot:2000 → {objectives: [...], channels: [...]}
```

**Snapshot Content:**
```zig
pub const Snapshot = struct {
    offset: EventOffset,           // Last event included
    timestamp: i64,
    objectives: []ObjectiveState,  // Reconstructed state
    channels: []ChannelState,
    
    pub fn toJson(self: Snapshot, a: Allocator) ![]u8;
    pub fn fromJson(a: Allocator, json: []u8) !Snapshot;
};
```

**Recovery with Snapshots:**
1. Find latest snapshot: `snapshot:<max_offset>`
2. Load snapshot → restore state
3. Replay events from `<max_offset + 1>` → current
4. Faster startup: 1000 events replayed vs 10,000

### Atomic Writes via WriteBatch

RocksDB WriteBatch ensures atomicity:
```zig
pub fn appendAtomic(
    self: *EventStore,
    events: []Event,
    allocator: Allocator
) !void {
    var batch = try self.db.createWriteBatch();
    defer batch.destroy();
    
    for (events, 0..) |event, i| {
        const offset = self.next_offset + i;
        const key = std.mem.toBytes(offset);
        const json = try event.toJson(allocator);
        defer allocator.free(json);
        
        try batch.put(key, json);
    }
    
    // Atomic commit - all or nothing
    try self.db.write(batch);
    self.next_offset += events.len;
}
```

### Files to Reference

**Phase 1 deliverables:**
- Event union type: [src/event_store/events.zig](../../src/event_store/events.zig)
- Event schemas: [schemas/events/*.schema.json](../../schemas/events/)
- Event ID derivation: [src/event_store/id.zig](../../src/event_store/id.zig)
- Event catalog: [docs/architecture/event-types.md](../../docs/architecture/event-types.md)

**Phase 1b deliverables (when complete):**
- In-memory EventStore interface to replace
- StateReconstructor (replay logic to reuse)

### Migration from In-Memory to RocksDB

**Interface Compatibility:**

Phase 1b will define EventStore interface:
```zig
pub const EventStore = struct {
    // Public API (keep same for RocksDB)
    pub fn append(self: *Self, event: Event) !EventOffset;
    pub fn readFrom(self: *Self, offset: EventOffset) *const Event;
    pub fn len(self: *Self) EventOffset;
    
    // Internal storage (replace SegmentedList → RocksDB)
    backend: union(enum) {
        memory: SegmentedList(Event),  // Phase 1b
        rocksdb: *RocksDB,              // Phase 4 (this phase)
    },
};
```

**Migration Strategy:**
1. Keep EventStore API unchanged
2. Replace `backend.memory` with `backend.rocksdb`
3. Tests should pass without modification (interface-driven)

### Event Size Considerations

**Approximate sizes (from Phase 1 schemas):**
- Small events (objective-approved): ~100 bytes JSON
- Medium events (state-signed): ~300 bytes JSON
- Large events (channel-created with 255 participants): ~5KB JSON

**10K events ≈ 3-5MB** (well under 100MB threshold from ADR-0002)

**Compression:** RocksDB compresses with Snappy by default (2-3x reduction typical)

### Testing with Event Types

**Crash Recovery Test:**
```zig
test "recover all 20 event types after crash" {
    var db = try RocksDB.open("test.db", allocator);
    defer db.close();
    
    // Append one of each event type
    for (all_event_types, 0..) |event_type, i| {
        const event = createSampleEvent(event_type, i);
        _ = try db.append(event, allocator);
    }
    
    // Simulate crash (close DB)
    db.close();
    
    // Reopen and verify all events recovered
    db = try RocksDB.open("test.db", allocator);
    const recovered = try db.readAll(allocator);
    defer allocator.free(recovered);
    
    try testing.expectEqual(@as(usize, 20), recovered.len);
}
```

**Snapshot Test:**
```zig
test "snapshot captures all event types" {
    var store = try EventStore.init(allocator);
    
    // Generate 1000 events (mix of all 20 types)
    for (0..1000) |i| {
        const event_type = i % 20;  // Cycle through types
        _ = try store.append(createSampleEvent(event_type, i), allocator);
    }
    
    // Create snapshot
    const snapshot = try store.createSnapshot(1000);
    
    // Clear store and restore from snapshot
    store.deinit();
    store = try EventStore.fromSnapshot(snapshot, allocator);
    
    // Verify state matches
    try testing.expectEqual(@as(u64, 1000), store.len());
}
```

---

**Context Added:** 2025-11-08  
**Dependencies:** Phase 1 (event types ✅), Phase 1b (EventStore interface - pending)  
**Note:** Implement Event.toJson/fromJson in Phase 1b or Phase 2 before starting Phase 4
