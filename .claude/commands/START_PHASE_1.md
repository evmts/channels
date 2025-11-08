# Execute Phase 1: Event Sourcing Foundation

**Status:** Ready to Execute
**Phase:** 1 of 12
**Duration:** 4-5 weeks
**Dependencies:** None (foundation phase)

---

## Context

You are beginning implementation of the event-sourced state channels system. Phase planning is complete (12 phases documented). Now execute Phase 1 - Event Sourcing Foundation.

**Why Phase 1 is Critical:**
- Core innovation over traditional snapshots (events vs snapshots)
- Foundation for all subsequent phases
- Establishes event sourcing patterns
- Validates architecture before complexity

---

## Phase 1 Reference

**Full Spec:** `.claude/commands/1_phase_1_event_sourcing.md`

**Key Sections:**
- Summary (lines 14-20): Core innovation explanation
- Objectives (lines 26-34): 5 primary goals
- Architecture (lines 72-153): Component diagram, data flow
- ADRs (lines 158-217): 3 architectural decisions needed
- Data Structures (lines 222-329): Event types, EventStore, supporting types
- APIs (lines 334-529): EventStore interface, StateReconstructor, SnapshotManager
- Work Breakdown (lines 537-566): 13 tasks with estimates
- Implementation Sequence (lines 571-681): Week-by-week plan
- Testing (lines 690-948): Unit tests, integration tests, benchmarks
- Success Criteria (lines 38-67): Exit criteria checklist

---

## Week 1: Documentation & Design (Days 1-5)

### Days 1-2: Write ADRs

**Task:** Write 3 ADRs guiding Phase 1 implementation

**ADR-0001: Event Sourcing Strategy**
- **File:** `docs/adrs/0001-event-sourcing-strategy.md`
- **Template:** `docs/adr-template.md`
- **Content:** See Phase 1 spec lines 158-177
- **Decision:** Event sourcing with snapshots as optimization
- **Rationale:** Audit trail, time-travel, transparent derivation vs snapshot-only

**ADR-0002: Event Serialization Format**
- **File:** `docs/adrs/0002-event-serialization-format.md`
- **Decision:** JSON for Phase 1, reconsider binary in Phase 4
- **Rationale:** Debuggability, Zig JSON support, schema evolution
- **Content:** See Phase 1 spec lines 180-196

**ADR-0003: In-Memory Event Log**
- **File:** `docs/adrs/0003-in-memory-event-log.md`
- **Decision:** ArrayList for Phase 1, migrate to RocksDB in Phase 4
- **Rationale:** Simplest for validation, fast iteration, testing
- **Content:** See Phase 1 spec lines 199-217

**Deliverable:** 3 ADRs written, reviewed, committed

---

### Days 3-5: Architecture Documentation

**Task:** Write comprehensive architecture docs for event sourcing

**File:** `docs/architecture/event-types.md` (already created - review and enhance if needed)

**Sections:**
1. **Overview:** What is event sourcing, why we chose it ✅
2. **Event Types Catalog:** All event types (20 events) ✅
3. **EventStore Design:** Append-only log, atomicity, subscribers (to implement)
4. **State Reconstruction:** Fold algorithm, determinism (to implement)

**Note:** The event catalog [docs/architecture/event-types.md](../../docs/architecture/event-types.md) is already comprehensive. Focus on implementing EventStore and reconstruction logic
5. **Snapshots:** Optimization strategy, frequency, storage
6. **Diagrams:** Component diagram, data flow, event lifecycle
7. **Code Examples:** Creating events, appending, reconstructing

**Additional Files:**
- `docs/architecture/event-types.md` - Detailed event catalog
- Update `docs/architecture/README.md` - Add event sourcing section

**Deliverable:** Architecture docs complete, diagrams created

---

## Week 2: Core Implementation (Days 6-10)

### Days 6-7: Event Type Definitions (TASK-1)

**File:** `src/event_store/events.zig`

**Implement:**
```zig
// Event union (all event types)
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
};

// Individual event structs (12+)
pub const ObjectiveCreatedEvent = struct { ... };
pub const StateSignedEvent = struct { ... };
// etc.

// Event serialization
pub fn toJson(self: Event, allocator: Allocator) ![]const u8;
pub fn fromJson(allocator: Allocator, json: []const u8) !Event;
```

**Reference:** Phase 1 spec lines 226-272

**Tests:** `src/event_store/events.test.zig`
- Serialization roundtrip for each event type
- Timestamp extraction
- EventId uniqueness

**Deliverable:** 15+ event types defined, serialization working, tests passing

---

### Days 8-9: EventStore Implementation (TASK-2, TASK-3)

**File:** `src/event_store/store.zig`

**Implement:**
```zig
pub const EventStore = struct {
    allocator: Allocator,
    events: std.ArrayList(Event),
    subscribers: std.ArrayList(EventCallback),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: Allocator) !*EventStore;
    pub fn append(self: *EventStore, event: Event) !EventOffset;
    pub fn readFrom(self: *EventStore, offset: EventOffset) []const Event;
    pub fn readRange(self: *EventStore, start: EventOffset, end: EventOffset) []const Event;
    pub fn subscribe(self: *EventStore, callback: EventCallback) !SubscriptionId;
    pub fn len(self: *EventStore) EventOffset;
    pub fn deinit(self: *EventStore) void;
};
```

**Reference:** Phase 1 spec lines 336-428

**Critical Features:**
- Mutex-protected append (thread-safe writes)
- Atomic append guarantees
- Event offset tracking
- Subscriber notifications

**Tests:** `src/event_store/store.test.zig`
- Append increases count
- Concurrent append safety (spawn 10 threads)
- ReadFrom returns correct slice
- Subscribers notified on append

**Deliverable:** EventStore working, concurrent-safe, tests passing

---

### Day 10: Event Subscription (TASK-4)

**File:** Update `src/event_store/store.zig`

**Implement:**
```zig
pub fn subscribe(
    self: *EventStore,
    callback: EventCallback
) !SubscriptionId {
    self.mutex.lock();
    defer self.mutex.unlock();
    try self.subscribers.append(callback);
    return self.subscribers.items.len - 1;
}

// Notify subscribers on append
for (self.subscribers.items) |callback| {
    callback(event, offset);
}
```

**Tests:**
- Subscriber receives events
- Multiple subscribers supported
- Callback invoked with correct event/offset

**Deliverable:** Event subscription working

---

## Week 3: State Reconstruction & Testing (Days 11-15)

### Days 11-13: StateReconstructor (TASK-5)

**File:** `src/event_store/reconstructor.zig`

**Implement:**
```zig
pub const StateReconstructor = struct {
    allocator: Allocator,
    event_store: *EventStore,
    cache: StateCache,

    pub fn init(allocator: Allocator, store: *EventStore) !*StateReconstructor;
    pub fn reconstructObjective(self: *Self, id: ObjectiveId) !ObjectiveState;
    pub fn reconstructChannel(self: *Self, id: ChannelId) !ChannelState;

    // Helper: Filter events for specific entity
    fn getObjectiveEvents(self: *Self, id: ObjectiveId) ![]Event;
    fn getChannelEvents(self: *Self, id: ChannelId) ![]Event;
};

// State types (simple for Phase 1)
pub const ObjectiveState = struct {
    id: ObjectiveId,
    status: ObjectiveStatus,
    event_count: usize,

    pub fn init(id: ObjectiveId) ObjectiveState;
    pub fn apply(self: ObjectiveState, event: Event) !ObjectiveState;
};
```

**Reference:** Phase 1 spec lines 433-484

**Algorithm:**
```
1. Filter events for entity (objective/channel)
2. Fold over events: state' = state.apply(event)
3. Return final state
```

**Tests:** `src/event_store/reconstructor.test.zig`
- Reconstruction produces correct state
- Multiple events applied in order
- Empty event log → initial state

**Deliverable:** State reconstruction working, tests passing

---

### Days 14-15: Unit Tests (TASK-7, TASK-8)

**Files:**
- `src/event_store/events.test.zig` (expand)
- `src/event_store/store.test.zig` (expand)
- `src/event_store/reconstructor.test.zig`

**Test Scenarios:**
- Event serialization (all types)
- EventStore append (single, concurrent)
- EventStore read (from offset, range)
- Subscription (single, multiple subscribers)
- Reconstruction (objective, channel)
- Edge cases (empty log, out-of-order timestamps)
- Memory cleanup (no leaks)

**Target:** 50+ tests, 90%+ coverage

**Command:**
```bash
zig build test
# Check coverage
zig build test -- --coverage
```

**Deliverable:** Comprehensive test suite passing

---

## Week 4: Optimization & Validation (Days 16-20)

### Days 16-17: Snapshots (TASK-6)

**File:** `src/event_store/snapshot.zig`

**Implement:**
```zig
pub const SnapshotManager = struct {
    allocator: Allocator,
    snapshot_interval: usize,  // Default: 1000 events
    snapshots: std.AutoHashMap(EventOffset, Snapshot),

    pub fn init(allocator: Allocator) !*SnapshotManager;
    pub fn createSnapshot(
        self: *Self,
        event_store: *EventStore,
        offset: EventOffset,
    ) !void;
    pub fn getLatestSnapshot(
        self: *Self,
        before_offset: EventOffset,
    ) ?Snapshot;
};

pub const Snapshot = struct {
    offset: EventOffset,
    timestamp: i64,
    data: []const u8,  // Serialized state
};
```

**Reference:** Phase 1 spec lines 489-521

**Strategy:** Snapshot every 1000 events

**Tests:**
- Snapshot creation
- Snapshot retrieval
- Reconstruction from snapshot + recent events

**Deliverable:** Snapshots working

---

### Days 18-19: Integration Tests & Benchmarks (TASK-9, TASK-10)

**Integration Test:** `src/event_store/integration.test.zig`

```zig
test "integration: full event sourcing flow" {
    // Create EventStore
    var store = try EventStore.init(allocator);
    defer store.deinit();

    var reconstructor = try StateReconstructor.init(allocator, store);
    defer reconstructor.deinit();

    // Simulate objective lifecycle
    const obj_id = ObjectiveId.generate();
    _ = try store.append(Event{ .objective_created = ... });
    _ = try store.append(Event{ .objective_approved = ... });
    _ = try store.append(Event{ .objective_completed = ... });

    // Reconstruct
    const state = try reconstructor.reconstructObjective(obj_id);

    // Verify
    try testing.expectEqual(ObjectiveStatus.Completed, state.status);
    try testing.expectEqual(@as(usize, 3), state.event_count);
}
```

**Benchmarks:** `src/event_store/benchmark.zig`

```zig
fn benchAppend(b: *Benchmark) !void {
    var store = try EventStore.init(b.allocator);
    defer store.deinit();

    b.reset();
    var i: usize = 0;
    while (i < 10000) : (i += 1) {
        _ = try store.append(testEvent());
    }
}

fn benchReconstruct(b: *Benchmark) !void {
    // Setup: 1000 events
    // Measure: Reconstruction time
    // Target: <100ms P95
}
```

**Performance Targets:**
- Append: <1ms per event
- Reconstruction: <100ms for 1000 events
- Memory: <50MB for 10K events

**Deliverable:** Integration tests pass, benchmarks meet targets

---

### Day 20: Documentation Polish (TASK-12, TASK-13)

**Tasks:**
1. Complete API documentation (all public functions)
2. Add code examples to architecture docs
3. Write usage guide: `docs/guides/using-event-store.md`
4. Update main README with Phase 1 status

**API Reference Format:**
```zig
/// Append event atomically to the log.
///
/// Example:
/// ```
/// const event = Event{ .objective_created = ... };
/// const offset = try store.append(event);
/// ```
///
/// Returns: Event offset in log
/// Errors: OutOfMemory
pub fn append(self: *EventStore, event: Event) !EventOffset {
    // ...
}
```

**Deliverable:** Docs complete, polished, reviewed

---

## Week 5: Code Review & Demo (Days 21-25)

### Days 21-22: Code Review

**Tasks:**
1. Self-review all code (style, clarity, comments)
2. Refactor complex functions
3. Add missing error handling
4. Fix any issues

**Checklist:**
- [ ] All public APIs documented
- [ ] All errors handled (no swallowed errors)
- [ ] No memory leaks (tested with allocator tracking)
- [ ] Code follows Zig style guide
- [ ] No unreachable/panic (except impossible paths)

**Deliverable:** Code review complete, issues fixed

---

### Days 23-24: Performance Validation

**Run Benchmarks:**
```bash
zig build benchmark
```

**Validate Targets:**
- ✅ Reconstruction: <100ms for 1000 events
- ✅ Memory: <50MB for 10K events
- ✅ Append: <1ms per event

**If targets missed:**
- Profile with `zig build -Drelease-safe`
- Optimize hot paths
- Consider caching

**Deliverable:** All performance targets met

---

### Day 25: Demo & Acceptance

**Prepare Demo:**
1. Clean build: `zig build`
2. Run all tests: `zig build test`
3. Live demo script:

```zig
// Demo: Event sourcing in action
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create EventStore
    var store = try EventStore.init(allocator);
    defer store.deinit();

    std.debug.print("Event Store initialized\n", .{});

    // Append events
    const obj_id = ObjectiveId.generate();
    _ = try store.append(Event{ .objective_created = ... });
    _ = try store.append(Event{ .objective_approved = ... });
    _ = try store.append(Event{ .objective_completed = ... });

    std.debug.print("Appended 3 events, total: {}\n", .{store.len()});

    // Reconstruct state
    var reconstructor = try StateReconstructor.init(allocator, store);
    defer reconstructor.deinit();

    const state = try reconstructor.reconstructObjective(obj_id);

    std.debug.print("Reconstructed state: {s}\n", .{@tagName(state.status)});
    std.debug.print("Event count: {}\n", .{state.event_count});

    // Show event log transparency
    const events = store.readFrom(0);
    std.debug.print("\nEvent Log (source of truth):\n", .{});
    for (events, 0..) |event, i| {
        std.debug.print("  [{}] {s} at {}\n", .{
            i,
            @tagName(event),
            event.timestamp(),
        });
    }
}
```

**Demo Talking Points:**
- Event log is source of truth (show append)
- State reconstructed from events (show reconstruction)
- Time-travel possible (reconstruct at any offset)
- Transparent (anyone can verify by replay)

**Acceptance Checklist:**
- [ ] All exit criteria met (see Phase 1 spec lines 59-67)
- [ ] Tests pass (50+ tests, 90%+ coverage)
- [ ] Integration test passes
- [ ] Benchmarks meet targets
- [ ] Code review approved (2+ engineers)
- [ ] ADRs approved (3 ADRs)
- [ ] Documentation complete
- [ ] Demo successful

**Deliverable:** Phase 1 accepted, ready for Phase 2

---

## Files to Create

**Source Code:**
```
src/
├── event_store/
│   ├── events.zig           (Event types, serialization)
│   ├── store.zig            (EventStore implementation)
│   ├── reconstructor.zig    (StateReconstructor)
│   ├── snapshot.zig         (SnapshotManager)
│   ├── events.test.zig      (Event tests)
│   ├── store.test.zig       (EventStore tests)
│   ├── reconstructor.test.zig (Reconstruction tests)
│   ├── integration.test.zig (Integration tests)
│   └── benchmark.zig        (Performance benchmarks)
└── root.zig                 (Updated with event_store module)
```

**Documentation:**
```
docs/
├── adrs/
│   ├── 0001-event-sourcing-strategy.md
│   ├── 0002-event-serialization-format.md
│   └── 0003-in-memory-event-log.md
├── architecture/
│   ├── event-types.md (✅ already exists - comprehensive event catalog)
│   └── README.md (✅ already exists - architecture index)
└── guides/
    └── using-event-store.md
```

---

## Success Criteria (from Phase 1 Spec)

**Must ALL be met:**
- [ ] All unit tests passing (target: 50+ tests, 90%+ coverage)
- [ ] Integration test: Append 1000 events, reconstruct state correctly
- [ ] Benchmark: Reconstruction <100ms for 1000 events
- [ ] Code review approved by 2+ engineers
- [ ] Performance benchmarks meet targets
- [ ] ADR-0001, ADR-0002, ADR-0003 written and approved
- [ ] Documentation complete: architecture doc + API reference
- [ ] Demo: Show event log → state reconstruction to team

---

## Build & Test Commands

```bash
# Build
zig build

# Run all tests
zig build test

# Run specific test
zig test src/event_store/store.test.zig

# Check coverage
zig build test -- --coverage

# Run benchmarks
zig build benchmark

# Build docs
zig build docs

# Demo
zig build run
```

---

## Next Agent Prompt

When Phase 1 is complete, use this prompt to start Phase 2:

```
Phase 1 (Event Sourcing Foundation) is complete. All exit criteria met:
- EventStore implemented with 15+ event types
- State reconstruction working
- Snapshots implemented
- 90%+ test coverage, all tests passing
- Benchmarks met (<100ms reconstruction)
- 3 ADRs approved
- Documentation complete

Now execute Phase 2: Core State & Signatures

Reference: .claude/commands/2_phase_core_state_and_signatures.md

Start with Week 1: Write ADR-0004 (Signature Scheme) and ADR-0005 (State Encoding)
```

---

## Resources

- **Phase 1 Spec:** `.claude/commands/1_phase_1_event_sourcing.md`
- **Phase Index:** `.claude/commands/README.md`
- **ADR Template:** `docs/adr-template.md`
- **PRD:** `docs/prd.md` (§4.1 Event Sourcing)
- **Reference:** State channel research on persistence patterns

---

**Ready to begin Phase 1 Week 1: Documentation & Design**

Start with: Write ADR-0001 (Event Sourcing Strategy)
