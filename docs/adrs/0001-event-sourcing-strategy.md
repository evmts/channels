# ADR-0001: Event Sourcing Strategy

<adr-metadata>
**Status:** Accepted | **Date:** 2025-11-08 | **Deciders:** Core Team | **Related:** ADR-0002, ADR-0003 | **Phase:** 1
</adr-metadata>

## Context

<context>
**Problem:** State channels require storing and managing state transitions. Traditional approaches use snapshots (store current state, discard history). Our vision: complete audit trails, time-travel debugging, provable state derivation, transparent state transitions.

**Constraints:**
- Must reconstruct state deterministically from history
- Performance: state reconstruction <100ms for 1000 events
- Storage: manageable growth (<10MB per channel per 24h expected)
- Must support concurrent access (multiple readers, single writer)
- Foundation for all protocol phases (P2-P9 depend on this)

**Assumptions:**
- Event log is append-only (immutable once written)
- Events are the source of truth (snapshots are optimizations)
- Typical channel: <10K events per day
- Storage costs acceptable for audit trail value

**Affected:**
- All protocol implementations (P3-P9) emit events
- State reconstruction for dispute resolution
- Debugging and development workflows
- Future analytics and monitoring systems
</context>

## Drivers

<drivers>
**Top 5 factors (prioritized):**
1. **Debuggability (10):** Replay any state transition, time-travel debugging
2. **Auditability (10):** Third parties can verify state derivation
3. **Transparency (9):** All state changes visible in event log
4. **Performance (8):** Reconstruct state <100ms for 1000 events
5. **Storage Efficiency (6):** Growth manageable, not unbounded

**Ex:** Event sourcing provides complete audit trail (can prove "channel entered state X because events Y, Z occurred"), enables time-travel debugging (replay up to any point), and makes state derivation transparent (vs opaque snapshots). Accept storage overhead, mitigate with snapshots.
</drivers>

## Options

<options>
### Opt 1: Pure Event Sourcing

**Desc:** Events are sole source of truth. State reconstructed by folding over event log. No snapshots, always replay from genesis.

**Pros:**
- ✅ Perfect audit trail (every transition recorded)
- ✅ Simple implementation (no snapshot complexity)
- ✅ Time-travel debugging (replay to any point)
- ✅ Provable state derivation (fold events deterministically)

**Cons:**
- ❌ Reconstruction cost grows linearly with event count
- ❌ Slow for long-lived channels (>10K events)
- ❌ No optimization path (always full replay)

**Effort:** Small (event store + fold logic only)

```zig
pub fn reconstructChannel(store: *EventStore, id: ChannelId) !ChannelState {
    const events = store.readAll(id);
    var state = ChannelState.init(id);
    for (events) |e| state = try state.apply(e);
    return state;
}
```

### Opt 2: Pure Snapshots

**Desc:** Store current state only. Discard event history. Traditional database approach.

**Pros:**
- ✅ Fast reconstruction (O(1) lookup)
- ✅ Minimal storage (only current state)
- ✅ Simple mental model (single source of truth)

**Cons:**
- ❌ No audit trail (history lost)
- ❌ No time-travel debugging (can't replay)
- ❌ Opaque state transitions (can't prove derivation)
- ❌ Hard to debug disputes (no event log)

**Effort:** Small (key-value store)

```zig
pub fn getChannel(db: *Database, id: ChannelId) !ChannelState {
    return db.get(id);
}
```

### Opt 3: Hybrid Event Sourcing + Snapshots

**Desc:** Events are source of truth, snapshots are cache. Reconstruct from latest snapshot + delta events. Best of both worlds.

**Pros:**
- ✅ Full audit trail (events preserved)
- ✅ Fast reconstruction (start from snapshot)
- ✅ Time-travel debugging (replay from any snapshot)
- ✅ Provable derivation (events + deterministic fold)
- ✅ Performance optimization (snapshot every N events)

**Cons:**
- ❌ More complexity (manage snapshots + events)
- ❌ Higher storage (events + snapshots)
- ❌ Snapshot invalidation logic required

**Effort:** Medium (event store + snapshot manager)

```zig
pub fn reconstructChannel(store: *EventStore, snapshots: *SnapshotManager, id: ChannelId) !ChannelState {
    const latest_snap = snapshots.getLatest(id);
    const events = store.readFrom(id, latest_snap.offset);
    var state = latest_snap.state;
    for (events) |e| state = try state.apply(e);
    return state;
}
```

### Comparison

|Criterion (weight)|Pure Events (Opt1)|Pure Snapshots (Opt2)|Hybrid (Opt3)|
|------------------|------------------|---------------------|-------------|
|Debuggability (10)|10→100|2→20|10→100|
|Auditability (10)|10→100|0→0|10→100|
|Transparency (9)|10→90|3→27|10→90|
|Performance (8)|4→32|10→80|9→72|
|Storage Efficiency (6)|6→36|10→60|5→30|
|**Total**|**358**|**187**|**392**|
</options>

## Decision

<decision>
**Choose:** Hybrid Event Sourcing + Snapshots (Opt 3)

**Why:**
- Events provide audit trail, transparency, debuggability (core value prop)
- Snapshots mitigate reconstruction cost without sacrificing history
- Best balance: correctness (events) + performance (snapshots)
- Aligns with state channel requirements (dispute resolution needs proof)

**Trade-offs accepted:**
- Additional complexity (snapshot management) acceptable for performance gain
- Higher storage (events + snapshots) acceptable given audit trail value
- Snapshot invalidation logic required but well-understood pattern

**Mitigation:**
- Snapshot every 1000 events (balance memory vs computation)
- Prune old snapshots (keep latest 10 per channel)
- Compress snapshots if >1MB (defer to P4)
- Cache reconstruction in memory (invalidate on new events)
</decision>

## Consequences

<consequences>
**Pos:**
- ✅ Complete audit trail (every state transition recorded)
- ✅ Time-travel debugging (replay to any event offset)
- ✅ Provable state derivation (third parties verify)
- ✅ Fast reconstruction (<100ms via snapshots)
- ✅ Transparent state changes (events human-readable)

**Neg:**
- ❌ Storage overhead (events + snapshots)
- ❌ Snapshot management complexity
- ❌ Cache invalidation logic required

**Mitigate:**
- Storage → Snapshot every 1000 events, prune old snapshots, compress if needed
- Complexity → Well-tested snapshot manager, clear APIs
- Invalidation → Simple rule: cache valid until new append
</consequences>

## Implementation

<implementation>
**Structure:**
```
src/event_store/
├── events.zig           # Event type definitions (20 events) ✅ Phase 1a
├── id.zig               # Event ID derivation ✅ Phase 1a
├── store.zig            # EventStore (append-only log) ⏸ Phase 1b
├── reconstructor.zig    # StateReconstructor (fold engine) ⏸ Phase 1b
├── snapshots.zig        # SnapshotManager (cache) ⏸ Phase 1b
└── *.test.zig           # Tests for each module
```

**Event Store:**
```zig
pub const EventStore = struct {
    events: SegmentedList(Event, 1024),  // Stable pointers
    subscribers: ArrayList(EventCallback),
    rw_lock: Thread.RwLock,
    count: atomic.Value(u64),

    pub fn append(self: *Self, event: Event) !EventOffset;
    pub fn readFrom(self: *Self, offset: EventOffset) ![]const Event;
};
```

**State Reconstructor:**
```zig
pub const StateReconstructor = struct {
    event_store: *EventStore,
    snapshot_mgr: *SnapshotManager,

    pub fn reconstructObjective(self: *Self, id: ObjectiveId) !ObjectiveState;
    pub fn reconstructChannel(self: *Self, id: ChannelId) !ChannelState;
};
```

**Snapshot Manager:**
```zig
pub const SnapshotManager = struct {
    snapshots: AutoHashMap(EventOffset, Snapshot),
    interval: usize = 1000,

    pub fn createSnapshot(self: *Self, store: *EventStore, offset: EventOffset) !void;
    pub fn getLatestSnapshot(self: *Self, before: EventOffset) ?Snapshot;
};
```

**Tests:**
- Unit: Event append, read, fold correctness
- Integration: 1000 events → reconstruct → verify state
- Concurrency: Parallel appends/reads (Thread.Pool)
- Performance: <100ms reconstruct 1000 events

**Docs:**
- `docs/architecture/event-sourcing.md` - Design overview
- `docs/architecture/event-types.md` - Event catalog ✅ Phase 1a
- API docs in source code

**Migration:** None (greenfield)
</implementation>

## Validation

<validation>
**Metrics:**
- Append throughput: >1000 events/second
- Reconstruct latency: <100ms P95 for 1000 events
- Storage: <10MB per channel per 24h (typical workload)
- Cache hit rate: >90% (snapshots effective)
- Developer satisfaction: time-travel debugging valuable

**Monitor:**
- Event log size (alert if >100MB per channel)
- Reconstruction performance (P50/P95/P99)
- Snapshot creation frequency
- Cache hit/miss ratio

**Review:**
- 3mo: Performance targets met? Snapshot interval tuned?
- 6mo: Storage growth acceptable? Developer experience positive?
- 12mo: Event sourcing still best choice? New patterns emerged?

**Revise if:**
- Reconstruction bottleneck >100ms P95 (adjust snapshot interval)
- Storage exceeds budget (implement compression/pruning)
- New tech enables better approach (ZK proofs for state derivation?)
- Requirements change (audit trail no longer needed)
</validation>

## Related

<related>
**ADR Dependencies:**
- **Depends on:** None (foundation)
- **Informs:** ADR-0002 (Event Serialization Format)
- **Informs:** ADR-0003 (Storage Backend P1)

**Project Context:**
- **PRD:** [prd.md](../prd.md) §4.1 - Event Sourcing Architecture
- **Context:** [context.md](../context.md) - State Channel Prior Art
- **Phase:** [.claude/commands/1_phase_1_event_sourcing.md](../../.claude/commands/1_phase_1_event_sourcing.md)
- **Architecture:** [docs/architecture/event-sourcing.md](../architecture/event-sourcing.md) (TBD)

**Implementation:**
- **Code:** `src/event_store/*.zig`
- **Tests:** `src/event_store/*.test.zig`
- **Schemas:** `schemas/events/*.schema.json` ✅ Phase 1a

**External References:**
- [Event Sourcing Pattern](https://martinfowler.com/eaaDev/EventSourcing.html) - Martin Fowler
- [CQRS Journey](https://docs.microsoft.com/en-us/previous-versions/msp-n-p/jj554200(v=pandp.10)) - Microsoft patterns
- [go-nitro](https://github.com/statechannels/go-nitro) - State channel implementation (snapshot-based, contrast)
- [Event Store DB](https://www.eventstore.com/) - Production event sourcing database
</related>

<changelog>
- 2025-11-08: Initial (Accepted) - Phase 1b
</changelog>
