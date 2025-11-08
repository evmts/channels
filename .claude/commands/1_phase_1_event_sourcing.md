# P1: Event Sourcing Foundation

**Meta:** P1 | Deps: None | Owner: Core

## Summary

Core innovation vs go-nitro: append-only event log = source-of-truth (not snapshots). Deterministic state reconstruction from events. Enables audit trails, time-travel debug, provable state derivation. Foundation - all later phases emit/replay events.

**vs go-nitro:** Events → derive state (transparent, verifiable) vs snapshots (opaque)

## Objectives

- OBJ-1: Event type hierarchy (15+ types)
- OBJ-2: Append-only log, atomic writes, thread-safe
- OBJ-3: State reconstruction engine (fold over events)
- OBJ-4: Snapshots (perf optimization, not source-of-truth)
- OBJ-5: Tests 90%+, benchmarks <100ms/1K events

## Success Criteria

**Done when:**
- 15+ event types defined
- EventStore: atomic append, thread-safe reads
- Reconstruct state from events deterministically
- Snapshots every N events (N=1000)
- 50+ tests, 90%+ cov
- Benchmark: <100ms reconstruct 1K events, <50MB for 10K
- 3 ADRs approved (sourcing strategy, serialization, storage)
- Docs: architecture + API
- Demo: event log → state reconstruction

**Exit gates:** All above + code review (2+) + integration test passes

## Architecture

**Components:**
```
Protocol Layer → emits events
  ↓
EventStore: append-only log + subscribers
  - EventLog: ArrayList (P1) → RocksDB (P4)
  - Dispatcher: notify subscribers
  ↓
StateReconstructor: fold events → state
SnapshotManager: cache every N events
```

**Flow:** Event → append → notify subscribers → read → reconstruct

## ADRs

**ADR-0001: Event Sourcing Strategy**
- Q: How store state?
- Opts: A) Snapshots (go-nitro) | B) Events | C) Hybrid
- Rec: B + snapshots as optimization
- Why: Audit trail, time-travel, transparent, debuggable vs ⚠️ reconstruct cost (mitigated cache)

**ADR-0002: Event Serialization**
- Q: Format?
- Opts: A) JSON | B) MessagePack | C) Custom binary
- Rec: A (P1), revisit P4 if >100MB or parse >1s
- Why: Debug (cat log readable), std.json, schema evolution vs ⚠️ size/speed (ok <10K events)

**ADR-0003: Storage Backend P1**
- Q: Where store P1?
- Opts: A) In-mem ArrayList | B) RocksDB | C) SQLite
- Rec: A (P1) → RocksDB (P4)
- Why: Simple, fast dev, easy test, validate sourcing vs ⚠️ ephemeral (ok testing)

## Data Structures

```zig
// Event union (all types)
pub const Event = union(enum) {
    objective_created: ObjectiveCreatedEvent,
    objective_approved: ObjectiveApprovedEvent,
    objective_rejected: ObjectiveRejectedEvent,
    objective_completed: ObjectiveCompletedEvent,
    state_signed: StateSignedEvent,
    state_received: StateReceivedEvent,
    deposit_detected: DepositDetectedEvent,
    challenge_registered: ChallengeRegisteredEvent,
    channel_concluded: ChannelConcludedEvent,
    message_sent: MessageSentEvent,
    message_received: MessageReceivedEvent,
    snapshot_created: SnapshotCreatedEvent,

    pub fn toJson(self: Event, a: Allocator) ![]u8;
    pub fn fromJson(a: Allocator, json: []u8) !Event;
    pub fn timestamp(self: Event) i64;
};

// Example event
pub const ObjectiveCreatedEvent = struct {
    event_id: EventId,        // hash(content)
    objective_id: ObjectiveId,
    objective_type: ObjectiveType,
    timestamp: i64,
};

pub const StateSignedEvent = struct {
    event_id: EventId,
    channel_id: ChannelId,
    state_hash: [32]u8,
    turn_num: u64,
    signature: Signature,
    timestamp: i64,
};

// Types
pub const EventId = [32]u8;
pub const EventOffset = u64;
```

**Invariants:**
- Events immutable once created
- EventIDs unique (hash content)
- Log append-only (no delete/modify)
- Timestamps monotonic within sequence
- Deserialization deterministic

## APIs

```zig
pub const EventStore = struct {
    allocator: Allocator,
    events: ArrayList(Event),
    subscribers: ArrayList(EventCallback),
    mutex: Mutex,  // thread-safe writes

    pub fn init(a: Allocator) !*EventStore;

    // Append atomically, return offset
    pub fn append(self: *Self, event: Event) !EventOffset {
        self.mutex.lock();
        defer self.mutex.unlock();
        const offset = self.events.items.len;
        try self.events.append(event);
        for (self.subscribers.items) |cb| cb(event, offset);
        return offset;
    }

    pub fn readFrom(self: *Self, offset: EventOffset) []const Event;
    pub fn readRange(self: *Self, start: EventOffset, end: EventOffset) []const Event;
    pub fn subscribe(self: *Self, cb: EventCallback) !SubscriptionId;
    pub fn len(self: *Self) EventOffset;
    pub fn deinit(self: *Self) void;
};

pub const EventCallback = *const fn(Event, EventOffset) void;

pub const StateReconstructor = struct {
    allocator: Allocator,
    event_store: *EventStore,
    cache: StateCache,

    pub fn init(a: Allocator, store: *EventStore) !*Self;

    // Reconstruct objective from events
    pub fn reconstructObjective(self: *Self, id: ObjectiveId) !ObjectiveState {
        const events = try self.getObjectiveEvents(id);
        defer self.allocator.free(events);
        var state = ObjectiveState.init(id);
        for (events) |e| state = try state.apply(e);
        return state;
    }

    pub fn reconstructChannel(self: *Self, id: ChannelId) !ChannelState;
    fn getObjectiveEvents(self: *Self, id: ObjectiveId) ![]Event;
};

pub const SnapshotManager = struct {
    allocator: Allocator,
    interval: usize,  // default 1000
    snapshots: AutoHashMap(EventOffset, Snapshot),

    pub fn createSnapshot(self: *Self, store: *EventStore, offset: EventOffset) !void;
    pub fn getLatestSnapshot(self: *Self, before: EventOffset) ?Snapshot;
};

pub const Snapshot = struct {
    offset: EventOffset,
    timestamp: i64,
    data: []const u8,  // serialized state
};
```

## Implementation

**Tasks:**
- T1: Event types (S, 2-4h)
- T2: EventStore impl (M, 1-2d) - ArrayList, mutex, append
- T3: Atomic append (M, 1-2d) - thread-safe
- T4: Subscriptions (M, 1-2d) - callbacks
- T5: StateReconstructor (L, 3-5d) - fold logic
- T6: SnapshotManager (L, 3-5d) - create/restore
- T7: EventStore tests (L, 3-5d)
- T8: Reconstructor tests (L, 3-5d)
- T9: Integration test (M, 1-2d) - append→reconstruct
- T10: Benchmarks (M, 1-2d)
- T11: ADRs 0001-0003 (M, 1-2d)
- T12: Architecture docs (M, 1-2d)
- T13: API docs (M, 1-2d)

**Path:** T1→T2→T3→T5→T7→T8→T9→Demo

**Effort:** ~20d → 4wk + buffer

## Schedule

**W1 (Docs):** ADRs 0001-0003, architecture docs, API specs
**W2 (Core):** Event types, EventStore, atomic append, subscriptions
**W3 (Reconstruct):** StateReconstructor, unit tests
**W4 (Optimize):** Snapshots, integration tests, benchmarks
**W5 (Validate):** Code review, perf validation, demo

## Testing

**Unit (50+ tests, 90%+ cov):**
```zig
test "event serialization roundtrip" {
    const e = Event{ .objective_created = ... };
    const json = try e.toJson(a);
    defer a.free(json);
    const decoded = try Event.fromJson(a, json);
    try testing.expectEqual(e, decoded);
}

test "append atomic concurrent" {
    var store = try EventStore.init(a);
    defer store.deinit();
    // Spawn 10 threads × 100 appends
    var threads: [10]Thread = undefined;
    for (&threads) |*t| t.* = try Thread.spawn(.{}, appendMany, .{store, 100});
    for (threads) |t| t.join();
    try testing.expectEqual(@as(u64, 1000), store.len());
}

test "reconstruction correct" {
    var store = try EventStore.init(a);
    var reconstructor = try StateReconstructor.init(a, store);
    const obj_id = ObjectiveId.generate();
    _ = try store.append(Event{ .objective_created = ...obj_id... });
    _ = try store.append(Event{ .objective_approved = ...obj_id... });
    const state = try reconstructor.reconstructObjective(obj_id);
    try testing.expectEqual(ObjectiveStatus.Approved, state.status);
}
```

**Integration:**
```zig
test "full event sourcing flow" {
    var store = try EventStore.init(a);
    var reconstructor = try StateReconstructor.init(a, store);
    const obj_id = ObjectiveId.generate();

    // Lifecycle: create → approve → complete
    _ = try store.append(Event{ .objective_created = ... });
    _ = try store.append(Event{ .objective_approved = ... });
    _ = try store.append(Event{ .objective_completed = ... });

    const state = try reconstructor.reconstructObjective(obj_id);
    try testing.expectEqual(ObjectiveStatus.Completed, state.status);
    try testing.expectEqual(@as(usize, 3), state.event_count);
}
```

**Benchmarks:**
```zig
fn benchAppend(b: *Benchmark) !void {
    var store = try EventStore.init(b.allocator);
    defer store.deinit();
    b.reset();
    var i: usize = 0;
    while (i < 10000) : (i += 1) _ = try store.append(testEvent());
}
// Target: <1ms/event

fn benchReconstruct(b: *Benchmark) !void {
    // Setup: 1000 events
    // Measure: reconstruction time
    // Target: <100ms P95
}
```

## Docs

**Create:**
- `docs/adrs/0001-event-sourcing-strategy.md`
- `docs/adrs/0002-event-serialization-format.md`
- `docs/adrs/0003-in-memory-event-log.md`
- `docs/architecture/event-sourcing.md` - overview, design, diagrams
- `docs/architecture/event-types.md` - catalog all 15+ types

**Code docs:** All public funcs, complex algos, examples

## Dependencies

**Req:** None (foundation)
**External:** Zig 0.15+, std.json

## Risks

| Risk | Prob | Impact | Mitigation |
|------|------|--------|------------|
| Reconstruct perf >100ms | M | H | Benchmark early, snapshot cache, optimize |
| Event log unbounded growth | M | M | Snapshot + prune (defer P4), <10K events P1 |
| Thread-safety bugs | L | H | Mutex all writes, extensive concurrent tests |
| JSON size issues | L | M | Switch MessagePack if >100MB (decision pt ADR-0002) |

## Deliverables

**Code:** `src/event_store/{events,store,reconstructor,snapshot}.zig` + tests
**Docs:** 3 ADRs, architecture docs, API reference
**Validation:** Coverage report (90%+), benchmarks (<100ms), integration test passes

## Validation Gates

**G1 (Design→Code):** ADRs approved, API reviewed, test strategy OK
**G2 (During):** 2+ reviewers, no criticals, cov met
**G3 (Pre-Done):** CI green, perf met, integration OK
**G4 (Accept):** Demo, deliverables in, docs published, sign-off

## Refs

- ADRs: 0001-0003 (to write)
- Phases: P4 (RocksDB migration)
- External: go-nitro/node/engine/store/ (snapshot approach - contrast)
- PRD: §4.1 Event Sourcing

## Example

```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var store = try EventStore.init(a);
    defer store.deinit();

    // Append events
    const obj_id = ObjectiveId.generate();
    _ = try store.append(Event{ .objective_created = .{...obj_id...} });
    _ = try store.append(Event{ .objective_approved = .{...obj_id...} });

    // Reconstruct
    var reconstructor = try StateReconstructor.init(a, store);
    const state = try reconstructor.reconstructObjective(obj_id);

    std.debug.print("State: {s}, Events: {}\n", .{@tagName(state.status), state.event_count});
}
```
