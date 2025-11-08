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
**External:** RocksDB docs, go-nitro durablestore.go

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
