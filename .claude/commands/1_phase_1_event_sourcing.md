# Phase 1: Event Sourcing Foundation

<phase-metadata>
**Phase Number:** 1
**Phase Name:** Event Sourcing Foundation
**Status:** Planning
**Dependencies:** None (this is the foundation)
**Estimated Duration:** 4-5 weeks
**Owner:** Core Team
</phase-metadata>

---

## 1. Executive Summary

<summary>
Phase 1 establishes the **event-sourcing foundation** that is our core innovation over go-nitro's snapshot-based approach. We implement an append-only event log as the source of truth for all state channel data, with deterministic state reconstruction from events. This is critical because without this foundation, we cannot achieve the debuggability, auditability, and time-travel capabilities that differentiate our system from existing state channel implementations. All subsequent phases build upon this event-sourced architecture - channels, objectives, protocols, and persistence all emit events that are logged, replayed, and reconstructed.

**Key Innovation:** Unlike go-nitro which stores state snapshots, we store the **events that led to that state**. Anyone can replay the event log to verify state correctness - no hidden state transitions, complete transparency.
</summary>

---

## 2. Objectives & Success Criteria

### 2.1 Primary Objectives

<objectives>
- **OBJ-1:** Define complete event type hierarchy for state channel operations
- **OBJ-2:** Implement append-only event log with atomic append guarantees
- **OBJ-3:** Build state reconstruction engine that derives state from events
- **OBJ-4:** Create snapshot mechanism as performance optimization (not source of truth)
- **OBJ-5:** Validate event sourcing with comprehensive test suite (90%+ coverage)
</objectives>

### 2.2 Success Criteria

<success-criteria>
**Definition of Done:** Phase 1 is complete when we have a working event-sourced system that can:
1. Append events atomically to a log
2. Reconstruct state by replaying events
3. Create snapshots for performance
4. Survive crashes without data loss
5. Pass all tests and benchmarks

| Criterion | Validation Method | Target |
|-----------|------------------|--------|
| Event types defined | Code review + docs | 15+ event types covering objectives/channels |
| Atomic append works | Unit test: concurrent appends | 100% success rate |
| Event log append-only enforced | Unit test: modification attempts fail | 0 modifications allowed |
| State reconstruction correct | Integration test: replay vs direct | 100% match |
| Reconstruction performance | Benchmark: 1000 events | <100ms P95 |
| Snapshot creation works | Unit test: snapshot + restore | Exact state match |
| Memory efficiency | Benchmark: 10K events | <50MB RAM |
| Documentation complete | Doc review | Architecture + API docs exist |
| ADRs written | ADR review | 3 ADRs approved |

**Exit Criteria (Must ALL be met):**
- [ ] All unit tests passing (target: 50+ tests, 90%+ coverage)
- [ ] Integration test: Append 1000 events, reconstruct state correctly
- [ ] Benchmark: Reconstruction <100ms for 1000 events
- [ ] Code review approved by 2+ engineers
- [ ] Performance benchmarks meet targets
- [ ] ADR-0001, ADR-0002, ADR-0003 written and approved
- [ ] Documentation complete: architecture doc + API reference
- [ ] Demo: Show event log → state reconstruction to team
</success-criteria>

---

## 3. Architecture & Design

### 3.1 System Architecture

<architecture>
**Component Diagram:**

```
┌─────────────────────────────────────────────────┐
│         Application / Protocol Layer            │
│    (Objectives, Channels - Phase 2+)            │
└──────────────────┬──────────────────────────────┘
                   │ emits events
                   ↓
┌─────────────────────────────────────────────────┐
│              Event Store (Phase 1)              │
│  ┌──────────────┐         ┌──────────────────┐ │
│  │  Event Log   │         │  Event Dispatcher│ │
│  │  (append)    │         │  (subscribe)     │ │
│  └──────┬───────┘         └────────┬─────────┘ │
│         │                          │           │
│         ↓                          ↓           │
│  ┌──────────────────────────────────────────┐  │
│  │     In-Memory Storage (Phase 1)          │  │
│  │     (RocksDB in Phase 4)                 │  │
│  └──────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
                   │
                   ↓ reads events
┌─────────────────────────────────────────────────┐
│        State Reconstruction Engine              │
│  ┌──────────────┐         ┌──────────────────┐ │
│  │  Projections │         │  Snapshots       │ │
│  │  (rebuild)   │         │  (optimize)      │ │
│  └──────────────┘         └──────────────────┘ │
└─────────────────────────────────────────────────┘
```

**Components:**

1. **Event Store**
   - **Responsibility:** Persist events, provide event stream
   - **Interface:** `append(event)`, `readFrom(offset)`, `subscribe(callback)`
   - **Implementation:** In-memory ArrayList (Phase 1), RocksDB (Phase 4)

2. **Event Log**
   - **Responsibility:** Maintain append-only sequence of events
   - **Guarantees:** Atomicity, ordering, durability (Phase 4)
   - **Storage:** Sequential array indexed by offset

3. **Event Dispatcher**
   - **Responsibility:** Notify subscribers when events appended
   - **Pattern:** Observer pattern with callbacks
   - **Use case:** Real-time UI updates, metrics

4. **State Reconstruction Engine**
   - **Responsibility:** Derive current state from event log
   - **Algorithm:** Fold/reduce over events
   - **Optimization:** Cache last reconstructed state

5. **Snapshot Manager**
   - **Responsibility:** Create/restore snapshots for performance
   - **Strategy:** Snapshot every N events (N=1000 initially)
   - **Trade-off:** Storage space vs reconstruction speed

**Data Flow:**

```
1. Objective emits event
   ↓
2. EventStore.append(event)
   ↓
3. Event written to log (append-only)
   ↓
4. Subscribers notified (async)
   ↓
5. State reconstruction requested
   ↓
6. Fold over events since last snapshot
   ↓
7. Return reconstructed state
```
</architecture>

### 3.2 Key Design Decisions (ADRs)

<architectural-decisions>
### **ADR-0001: Event Sourcing as State Management Strategy**

- **Question:** How do we store state channel data?
- **Options:**
  - **A) Snapshots** (like go-nitro): Store latest state only
  - **B) Event Sourcing**: Store events, derive state
  - **C) Hybrid**: Store snapshots + recent events
- **Recommendation:** B (Event Sourcing) with snapshots as optimization
- **Rationale:**
  - ✅ Complete audit trail for debugging
  - ✅ Time-travel to any historical state
  - ✅ Transparent state derivation (anyone can verify)
  - ✅ Natural fit for state machines (events = transitions)
  - ⚠️ Requires reconstruction cost (mitigated by caching)
- **Consequences:**
  - Event log is source of truth, not snapshots
  - All state changes must be modeled as events
  - Reconstruction must be deterministic
- **Status:** To be written in Week 1

---

### **ADR-0002: Event Serialization Format**

- **Question:** How do we serialize events to disk/memory?
- **Options:**
  - **A) JSON**: Human-readable, debuggable
  - **B) MessagePack**: Binary, compact
  - **C) Custom Binary**: Maximum efficiency
  - **D) Cap'n Proto**: Zero-copy deserialization
- **Recommendation:** A (JSON) for Phase 1, reconsider in Phase 4
- **Rationale:**
  - ✅ Easy debugging (can cat event log and read it)
  - ✅ Zig has good JSON support (`std.json`)
  - ✅ Schema evolution easier (can add fields)
  - ⚠️ Larger size than binary (acceptable for Phase 1)
  - ⚠️ Slower parsing (acceptable for <10K events)
- **Decision point:** If event logs exceed 100MB or parsing >1s, switch to MessagePack
- **Status:** To be written in Week 1

---

### **ADR-0003: In-Memory Event Log for Phase 1**

- **Question:** Where do we store events in Phase 1?
- **Options:**
  - **A) In-memory ArrayList**: Simple, fast
  - **B) RocksDB from start**: Durable
  - **C) SQLite**: Queryable
- **Recommendation:** A (In-memory) for Phase 1, **RocksDB in Phase 4**
- **Rationale:**
  - ✅ Simplest possible implementation for validation
  - ✅ Fast development iteration
  - ✅ Easier testing (no disk I/O)
  - ✅ Phase 1 focus: prove event sourcing works, not durability
  - ⚠️ Data lost on crash (acceptable for Phase 1 testing)
- **Phase 4 Migration:** Replace ArrayList with RocksDB backend
- **Status:** To be written in Week 1

</architectural-decisions>

### 3.3 Data Structures

<data-structures>
### Event Type Hierarchy

**Core Event Union:**

```zig
/// All events in the system
/// Events are immutable once created
pub const Event = union(enum) {
    // Objective lifecycle events
    objective_created: ObjectiveCreatedEvent,
    objective_approved: ObjectiveApprovedEvent,
    objective_rejected: ObjectiveRejectedEvent,
    objective_completed: ObjectiveCompletedEvent,

    // Channel state events
    state_signed: StateSignedEvent,
    state_received: StateReceivedEvent,

    // Chain events
    deposit_detected: DepositDetectedEvent,
    challenge_registered: ChallengeRegisteredEvent,
    channel_concluded: ChannelConcludedEvent,

    // Message events
    message_sent: MessageSentEvent,
    message_received: MessageReceivedEvent,

    // System events
    snapshot_created: SnapshotCreatedEvent,

    /// Serialize event to JSON
    pub fn toJson(self: Event, allocator: Allocator) ![]const u8 {
        return try std.json.stringifyAlloc(allocator, self, .{});
    }

    /// Deserialize event from JSON
    pub fn fromJson(allocator: Allocator, json: []const u8) !Event {
        return try std.json.parseFromSliceLeaky(Event, allocator, json, .{});
    }

    /// Get event timestamp
    pub fn timestamp(self: Event) i64 {
        return switch (self) {
            .objective_created => |e| e.timestamp,
            .state_signed => |e| e.timestamp,
            // ... all event types have timestamp
            else => unreachable,
        };
    }
};
```

**Event Structures:**

```zig
/// Emitted when a new objective is created
pub const ObjectiveCreatedEvent = struct {
    event_id: EventId,          // Unique event identifier
    objective_id: ObjectiveId,  // Which objective
    objective_type: ObjectiveType, // DirectFund, VirtualFund, etc.
    timestamp: i64,             // Unix timestamp (ms)
};

/// Emitted when a state is signed by us
pub const StateSignedEvent = struct {
    event_id: EventId,
    channel_id: ChannelId,
    state_hash: [32]u8,         // Hash of signed state
    turn_num: u64,              // State turn number
    signature: Signature,        // Our signature
    timestamp: i64,
};

/// Emitted when we receive a signed state from counterparty
pub const StateReceivedEvent = struct {
    event_id: EventId,
    channel_id: ChannelId,
    state_hash: [32]u8,
    turn_num: u64,
    from_address: Address,      // Who sent it
    signature: Signature,        // Their signature
    timestamp: i64,
};

// ... more event types
```

**Supporting Types:**

```zig
/// Unique event identifier (hash of event content)
pub const EventId = [32]u8;

/// Event log offset (position in log)
pub const EventOffset = u64;

/// Event sequence (ordered list)
pub const EventSequence = std.ArrayList(Event);
```

**Invariants:**
- ✅ Events are immutable once created
- ✅ Event IDs are unique (hash of content)
- ✅ Event log is append-only (never delete/modify)
- ✅ Events have monotonic timestamps within a sequence
- ✅ Event deserialization is deterministic (same bytes → same event)

</data-structures>

### 3.4 Interfaces & APIs

<apis>
### EventStore Interface

```zig
/// Event Store - append-only event log
/// Thread-safe for concurrent reads, synchronized writes
pub const EventStore = struct {
    allocator: Allocator,
    events: std.ArrayList(Event),
    subscribers: std.ArrayList(EventCallback),
    mutex: std.Thread.Mutex,  // Protects writes

    /// Initialize new event store
    pub fn init(allocator: Allocator) !*EventStore {
        var store = try allocator.create(EventStore);
        store.* = .{
            .allocator = allocator,
            .events = std.ArrayList(Event).init(allocator),
            .subscribers = std.ArrayList(EventCallback).init(allocator),
            .mutex = .{},
        };
        return store;
    }

    /// Append event atomically to the log
    /// Returns: Event offset in log
    /// Errors: OutOfMemory
    pub fn append(self: *EventStore, event: Event) !EventOffset {
        self.mutex.lock();
        defer self.mutex.unlock();

        const offset = self.events.items.len;
        try self.events.append(event);

        // Notify subscribers (async)
        for (self.subscribers.items) |callback| {
            callback(event, offset);
        }

        return offset;
    }

    /// Read events starting from offset
    /// Returns: Slice of events (valid until next append)
    pub fn readFrom(self: *EventStore, offset: EventOffset) []const Event {
        if (offset >= self.events.items.len) {
            return &[_]Event{};
        }
        return self.events.items[offset..];
    }

    /// Read events in range [start, end)
    pub fn readRange(
        self: *EventStore,
        start: EventOffset,
        end: EventOffset
    ) []const Event {
        if (start >= self.events.items.len) {
            return &[_]Event{};
        }
        const actual_end = @min(end, self.events.items.len);
        return self.events.items[start..actual_end];
    }

    /// Subscribe to new events
    /// Callback invoked for each new event (async)
    pub fn subscribe(
        self: *EventStore,
        callback: EventCallback
    ) !SubscriptionId {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.subscribers.append(callback);
        return self.subscribers.items.len - 1;
    }

    /// Get total number of events
    pub fn len(self: *EventStore) EventOffset {
        return self.events.items.len;
    }

    /// Cleanup resources
    pub fn deinit(self: *EventStore) void {
        self.events.deinit();
        self.subscribers.deinit();
        self.allocator.destroy(self);
    }
};

/// Callback signature for event subscribers
pub const EventCallback = *const fn (event: Event, offset: EventOffset) void;

/// Subscription identifier
pub const SubscriptionId = usize;
```

### State Reconstructor Interface

```zig
/// State Reconstructor - derives state from events
pub const StateReconstructor = struct {
    allocator: Allocator,
    event_store: *EventStore,
    cache: StateCache,  // Optimization

    /// Reconstruct objective state from events
    pub fn reconstructObjective(
        self: *StateReconstructor,
        objective_id: ObjectiveId,
    ) !ObjectiveState {
        // Find all events for this objective
        const events = try self.getObjectiveEvents(objective_id);
        defer self.allocator.free(events);

        // Fold over events to build state
        var state = ObjectiveState.init(objective_id);
        for (events) |event| {
            state = try state.apply(event);
        }

        return state;
    }

    /// Reconstruct channel state from events
    pub fn reconstructChannel(
        self: *StateReconstructor,
        channel_id: ChannelId,
    ) !ChannelState {
        // Similar to reconstructObjective
        // ...
    }

    // Helper: Filter events for specific objective
    fn getObjectiveEvents(
        self: *StateReconstructor,
        objective_id: ObjectiveId,
    ) ![]Event {
        var filtered = std.ArrayList(Event).init(self.allocator);
        errdefer filtered.deinit();

        const all_events = self.event_store.readFrom(0);
        for (all_events) |event| {
            if (eventBelongsToObjective(event, objective_id)) {
                try filtered.append(event);
            }
        }

        return try filtered.toOwnedSlice();
    }
};
```

### Snapshot Manager Interface

```zig
/// Snapshot Manager - performance optimization
pub const SnapshotManager = struct {
    allocator: Allocator,
    snapshot_interval: usize,  // Snapshot every N events
    snapshots: std.AutoHashMap(EventOffset, Snapshot),

    /// Create snapshot at current event log position
    pub fn createSnapshot(
        self: *SnapshotManager,
        event_store: *EventStore,
        offset: EventOffset,
    ) !void {
        // Reconstruct state up to offset
        // Serialize state
        // Store snapshot
        // Emit SnapshotCreatedEvent
    }

    /// Get latest snapshot before offset
    pub fn getLatestSnapshot(
        self: *SnapshotManager,
        before_offset: EventOffset,
    ) ?Snapshot {
        // Find most recent snapshot <= before_offset
    }
};

pub const Snapshot = struct {
    offset: EventOffset,       // Events up to this offset included
    timestamp: i64,
    data: []const u8,          // Serialized state
};
```

**API Design Principles:**
- ✅ Explicit error handling (Zig error unions)
- ✅ Explicit allocation (pass allocator)
- ✅ Resource cleanup (deinit required)
- ✅ Type safety (no void pointers)
- ✅ Const correctness (mark read-only params const)
</apis>

---

## 4. Implementation Plan

### 4.1 Work Breakdown

<work-breakdown>
| Task ID | Description | Est. | Dependencies | Priority |
|---------|-------------|------|--------------|----------|
| **TASK-1** | Define event type hierarchy (Event union + struct definitions) | S | None | P0 |
| **TASK-2** | Implement EventStore (in-memory ArrayList backend) | M | TASK-1 | P0 |
| **TASK-3** | Implement atomic append with locking | M | TASK-2 | P0 |
| **TASK-4** | Implement event subscription/notification | M | TASK-2 | P1 |
| **TASK-5** | Implement StateReconstructor (fold over events) | L | TASK-2 | P0 |
| **TASK-6** | Implement SnapshotManager (create/restore) | L | TASK-5 | P1 |
| **TASK-7** | Write unit tests for EventStore | L | TASK-3 | P0 |
| **TASK-8** | Write unit tests for StateReconstructor | L | TASK-5 | P0 |
| **TASK-9** | Write integration test (append → reconstruct) | M | TASK-7, TASK-8 | P0 |
| **TASK-10** | Write performance benchmarks | M | TASK-9 | P1 |
| **TASK-11** | Write ADR-0001, ADR-0002, ADR-0003 | M | None | P0 |
| **TASK-12** | Write architecture documentation | M | ALL | P0 |
| **TASK-13** | Write API reference documentation | M | ALL | P1 |

**Estimation Key:**
- **S (Small):** 2-4 hours
- **M (Medium):** 1-2 days
- **L (Large):** 3-5 days

**Priority:**
- **P0:** Must have (blocks other work)
- **P1:** Should have (important but not blocking)

**Critical Path:** TASK-1 → TASK-2 → TASK-3 → TASK-5 → TASK-7 → TASK-8 → TASK-9 → Demo

**Total Estimated Effort:** ~20 days → 4 weeks with buffer
</work-breakdown>

### 4.2 Implementation Sequence

<implementation-sequence>
### Week 1: Documentation & Design

**Days 1-2: ADR Writing**
- Write ADR-0001: Event Sourcing Strategy
- Write ADR-0002: Event Serialization Format
- Write ADR-0003: In-Memory Event Log
- Get ADRs reviewed and approved

**Days 3-5: Architecture Documentation**
- Write `docs/architecture/event-sourcing.md`
- Document event type catalog
- Create API specifications
- Write code examples

**Deliverable:** Complete design docs + approved ADRs

---

### Week 2: Core Implementation

**Days 1-2: Event Types (TASK-1)**
```zig
// File: src/event_store/events.zig
pub const Event = union(enum) {
    objective_created: ObjectiveCreatedEvent,
    // ... all event types
};
```

**Days 3-4: EventStore (TASK-2, TASK-3)**
```zig
// File: src/event_store/store.zig
pub const EventStore = struct {
    pub fn init(...) !*EventStore { ... }
    pub fn append(...) !EventOffset { ... }
    pub fn readFrom(...) []const Event { ... }
};
```

**Day 5: Event Subscription (TASK-4)**
```zig
pub fn subscribe(callback) !SubscriptionId { ... }
```

**Deliverable:** Working EventStore with tests

---

### Week 3: State Reconstruction & Testing

**Days 1-3: StateReconstructor (TASK-5)**
```zig
// File: src/event_store/reconstructor.zig
pub fn reconstructObjective(...) !ObjectiveState {
    // Fold over events
}
```

**Days 4-5: Unit Tests (TASK-7, TASK-8)**
- EventStore append tests
- Concurrent append tests
- Reconstruction correctness tests
- Edge case tests

**Deliverable:** State reconstruction working + comprehensive tests

---

### Week 4: Optimization & Validation

**Days 1-2: Snapshots (TASK-6)**
```zig
// File: src/event_store/snapshot.zig
pub const SnapshotManager = struct {
    pub fn createSnapshot(...) !void { ... }
};
```

**Days 3-4: Integration Tests & Benchmarks (TASK-9, TASK-10)**
- End-to-end: append → reconstruct
- Performance: 1000 events <100ms
- Memory: Track allocation

**Day 5: Documentation Polish (TASK-12, TASK-13)**
- Complete API docs
- Add examples
- Review all docs

**Deliverable:** Phase 1 complete and validated

---

### Week 5: Code Review & Demo

**Days 1-2: Code Review**
- Address review feedback
- Refactor for clarity
- Fix any issues

**Days 3-4: Performance Validation**
- Run benchmarks
- Optimize hot paths if needed
- Verify all targets met

**Day 5: Demo & Acceptance**
- Live demo to team
- Show event log → state reconstruction
- Get stakeholder sign-off

**Deliverable:** Phase 1 accepted, ready for Phase 2

</implementation-sequence>

---

## 5. Testing Strategy

### 5.1 Unit Tests

<unit-tests>
**Coverage Target:** 90%+

**Test Categories:**

### Event Serialization Tests

```zig
test "event serialization roundtrip" {
    const allocator = std.testing.allocator;

    const original = Event{
        .objective_created = .{
            .event_id = generateEventId(),
            .objective_id = ObjectiveId.generate(),
            .objective_type = .DirectFund,
            .timestamp = std.time.milliTimestamp(),
        },
    };

    // Serialize
    const json = try original.toJson(allocator);
    defer allocator.free(json);

    // Deserialize
    const deserialized = try Event.fromJson(allocator, json);

    // Verify exact match
    try testing.expectEqual(original, deserialized);
}
```

### EventStore Append Tests

```zig
test "append increases event count" {
    var store = try EventStore.init(testing.allocator);
    defer store.deinit();

    const event = testEvent();

    try testing.expectEqual(@as(EventOffset, 0), store.len());

    const offset = try store.append(event);

    try testing.expectEqual(@as(EventOffset, 0), offset);
    try testing.expectEqual(@as(EventOffset, 1), store.len());
}

test "append is atomic under concurrent access" {
    var store = try EventStore.init(testing.allocator);
    defer store.deinit();

    // Spawn 10 threads, each appending 100 events
    const num_threads = 10;
    const events_per_thread = 100;

    var threads: [num_threads]std.Thread = undefined;
    for (&threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, appendMany, .{
            store, events_per_thread
        });
    }

    for (threads) |thread| {
        thread.join();
    }

    // Should have exactly 1000 events, no duplicates/losses
    try testing.expectEqual(
        @as(EventOffset, num_threads * events_per_thread),
        store.len()
    );
}

fn appendMany(store: *EventStore, count: usize) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        _ = store.append(testEvent()) catch unreachable;
    }
}
```

### State Reconstruction Tests

```zig
test "reconstruction produces correct state" {
    var store = try EventStore.init(testing.allocator);
    defer store.deinit();

    var reconstructor = try StateReconstructor.init(testing.allocator, store);
    defer reconstructor.deinit();

    const objective_id = ObjectiveId.generate();

    // Emit sequence of events
    try store.append(Event{ .objective_created = .{
        .event_id = generateEventId(),
        .objective_id = objective_id,
        .objective_type = .DirectFund,
        .timestamp = 1000,
    }});

    try store.append(Event{ .objective_approved = .{
        .event_id = generateEventId(),
        .objective_id = objective_id,
        .timestamp = 2000,
    }});

    // Reconstruct state
    const state = try reconstructor.reconstructObjective(objective_id);

    // Verify state matches expected
    try testing.expectEqual(ObjectiveStatus.Approved, state.status);
    try testing.expectEqual(objective_id, state.id);
}
```

**Additional Test Scenarios:**
- ✅ Empty event log → empty reconstruction
- ✅ Event filtering (only relevant events)
- ✅ Out-of-order timestamp handling
- ✅ Memory cleanup (no leaks)
- ✅ Error handling (malformed JSON)

</unit-tests>

### 5.2 Integration Tests

<integration-tests>
**Scenarios:**

### End-to-End: Append → Reconstruct

```zig
test "integration: full event sourcing flow" {
    // Setup
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    var reconstructor = try StateReconstructor.init(allocator, store);
    defer reconstructor.deinit();

    // Simulate objective lifecycle
    const obj_id = ObjectiveId.generate();

    // 1. Create objective
    _ = try store.append(Event{ .objective_created = .{
        .event_id = generateEventId(),
        .objective_id = obj_id,
        .objective_type = .DirectFund,
        .timestamp = 1000,
    }});

    // 2. Approve objective
    _ = try store.append(Event{ .objective_approved = .{
        .event_id = generateEventId(),
        .objective_id = obj_id,
        .timestamp = 2000,
    }});

    // 3. Complete objective
    _ = try store.append(Event{ .objective_completed = .{
        .event_id = generateEventId(),
        .objective_id = obj_id,
        .timestamp = 3000,
    }});

    // Reconstruct and verify
    const state = try reconstructor.reconstructObjective(obj_id);

    try testing.expectEqual(ObjectiveStatus.Completed, state.status);
    try testing.expectEqual(@as(usize, 3), state.event_count);
}
```

### Snapshot + Recovery

```zig
test "integration: snapshot and recovery" {
    // ... setup ...

    // Append 1000 events
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        _ = try store.append(testEvent());
    }

    // Create snapshot at 1000
    var snapshot_mgr = try SnapshotManager.init(allocator);
    defer snapshot_mgr.deinit();

    try snapshot_mgr.createSnapshot(store, 1000);

    // Append 500 more events
    i = 0;
    while (i < 500) : (i += 1) {
        _ = try store.append(testEvent());
    }

    // Reconstruct from snapshot (should only replay 500 events)
    const start_time = std.time.milliTimestamp();
    const state = try reconstructFromSnapshot(snapshot_mgr, store);
    const duration = std.time.milliTimestamp() - start_time;

    // Should be faster than replaying all 1500
    try testing.expect(duration < 50); // <50ms
}
```

</integration-tests>

### 5.3 Performance Benchmarks

```zig
const benchmark = @import("benchmark");

// Benchmark: Append performance
fn benchAppend(b: *benchmark.Benchmark) !void {
    var store = try EventStore.init(b.allocator);
    defer store.deinit();

    const event = testEvent();

    b.reset();

    var i: usize = 0;
    while (i < 10000) : (i += 1) {
        _ = try store.append(event);
    }
}

// Benchmark: Reconstruction performance
fn benchReconstruct(b: *benchmark.Benchmark) !void {
    // Setup: 1000 events in store
    var store = try EventStore.init(b.allocator);
    defer store.deinit();

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        _ = try store.append(testEvent());
    }

    var reconstructor = try StateReconstructor.init(b.allocator, store);
    defer reconstructor.deinit();

    b.reset();

    // Measure reconstruction time
    _ = try reconstructor.reconstructObjective(test_objective_id);
}

// Target: <100ms for 1000 events
```

---

_(Continued in next section due to length)_

## Summary

Phase 1 establishes the event-sourcing foundation that differentiates our system. With a comprehensive test suite, clear ADRs, and proven performance, we create the bedrock for all future phases.

**Key Deliverables:**
- ✅ Working event log with atomic appends
- ✅ State reconstruction from events
- ✅ Snapshot optimization
- ✅ 90%+ test coverage
- ✅ Complete documentation

**Ready for Phase 2:** Core Channel State & Signatures
