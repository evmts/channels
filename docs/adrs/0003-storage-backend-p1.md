# ADR-0003: Storage Backend Phase 1

<adr-metadata>
**Status:** Accepted | **Date:** 2025-11-08 | **Deciders:** Core Team | **Related:** ADR-0001, ADR-0002 | **Phase:** 1
</adr-metadata>

## Context

<context>
**Problem:** EventStore needs backing data structure for append-only log. Must support stable pointers (subscribers hold event references), concurrent reads, atomic appends, and prepare for Phase 4 RocksDB migration.

**Constraints:**
- Stable pointers (ArrayList reallocation invalidates references)
- Thread-safe (multiple readers, single writer)
- Atomic appends (event + subscriber notification)
- Phase 1-3: In-memory only (persistence in Phase 4)
- Phase 4: Migrate to RocksDB (minimal code churn)

**Assumptions:**
- Phase 1-3: <10K events per test run (memory acceptable)
- Subscribers hold event pointers during event processing
- Single EventStore instance per process
- Migration path to persistent storage clear

**Affected:**
- EventStore implementation (append, read, subscribe)
- Subscriber callbacks (event pointer stability)
- StateReconstructor (event iteration)
- Phase 4 RocksDB migration
</context>

## Drivers

<drivers>
**Top 5 factors (prioritized):**
1. **Pointer Stability (10):** Subscribers rely on stable event references
2. **Thread Safety (9):** Concurrent reads must not block
3. **Migration Path (8):** Minimal changes when moving to RocksDB
4. **Simplicity (7):** std.lib only, no external deps
5. **Performance (6):** Append <1ms, read <0.1ms per event

**Ex:** SegmentedList provides stable pointers (no reallocation), RwLock enables concurrent reads, and slice-based API (readFrom/readRange) maps cleanly to RocksDB iterators.
</drivers>

## Options

<options>
### Opt 1: std.ArrayList

**Desc:** Standard dynamic array with grow-by-doubling allocation strategy.

**Pros:**
- ✅ Simple, familiar API
- ✅ Contiguous memory (cache-friendly)
- ✅ Fast iteration
- ✅ stdlib (no deps)

**Cons:**
- ❌ Reallocation invalidates pointers (breaks subscribers)
- ❌ Growth pauses (copy all elements on resize)
- ❌ No stable references

**Effort:** Small

```zig
var events = std.ArrayList(Event){};
try events.append(allocator, event);  // May invalidate all pointers!
```

### Opt 2: std.SegmentedList

**Desc:** List of fixed-size segments. Appends allocate new segments, existing pointers remain valid.

**Pros:**
- ✅ Stable pointers (no reallocation)
- ✅ Predictable allocation (1024 events per segment)
- ✅ No growth pauses (incremental allocation)
- ✅ stdlib (no deps)
- ✅ Good cache locality within segments

**Cons:**
- ❌ Slightly slower iteration (segment boundaries)
- ❌ More complex than ArrayList
- ❌ Memory fragmentation (segments not contiguous)

**Effort:** Small (direct stdlib usage)

```zig
var events = std.segmented_list.SegmentedList(Event, 1024){};
try events.append(allocator, event);  // Stable pointers ✅
const ptr = events.at(offset);  // Always valid
```

### Opt 3: RocksDB (Phase 4)

**Desc:** Persistent key-value store with efficient range queries.

**Pros:**
- ✅ Persistent storage
- ✅ Efficient range scans (event iteration)
- ✅ Battle-tested (production-grade)
- ✅ Compression built-in

**Cons:**
- ❌ External dependency (C++ library)
- ❌ Zig bindings needed
- ❌ Overkill for Phase 1-3 (no persistence needed yet)
- ❌ Pointer stability N/A (disk-backed)

**Effort:** Large (defer to Phase 4)

### Opt 4: Custom Ring Buffer

**Desc:** Fixed-size circular buffer optimized for append-only workload.

**Pros:**
- ✅ Stable pointers (pre-allocated)
- ✅ Fast appends (O(1))
- ✅ Simple implementation

**Cons:**
- ❌ Fixed capacity (must set max events)
- ❌ Complex wraparound logic
- ❌ Migration to RocksDB harder (different API)

**Effort:** Medium

### Comparison

|Criterion (weight)|ArrayList (Opt1)|SegmentedList (Opt2)|RocksDB (Opt3)|Ring Buffer (Opt4)|
|------------------|----------------|---------------------|--------------|------------------|
|Pointer Stability (10)|0→0|10→100|5→50|10→100|
|Thread Safety (9)|6→54|8→72|7→63|8→72|
|Migration Path (8)|4→32|9→72|10→80|3→24|
|Simplicity (7)|10→70|8→56|3→21|6→42|
|Performance (6)|9→54|8→48|7→42|9→54|
|**Total**|**210**|**348**|**256**|**292**|
</options>

## Decision

<decision>
**Choose:** std.SegmentedList for Phase 1-3, migrate to RocksDB in Phase 4

**Why:**
- Stable pointers solve subscriber reference problem
- stdlib (no external dependencies for P1-3)
- Predictable allocation (1024 events per segment)
- Clean migration path (slice-based API → RocksDB iterators)

**Migration Strategy (Phase 4):**
- Replace SegmentedList with RocksDB backend
- Keep EventStore API unchanged (append, readFrom, readRange)
- Subscribers receive event copies (not pointers) from RocksDB
- Persistence enables recovery after process restart

**Trade-offs accepted:**
- Slight iteration overhead (segment boundaries) acceptable
- Memory fragmentation (segments) acceptable for <10K events
- In-memory only (P1-3) acceptable before production

**Configuration:**
- Segment size: 1024 events (balance allocation overhead vs fragmentation)
- Initial capacity: 0 (allocate on demand)
- Allocator: GPA with `.thread_safe = true`
</decision>

## Consequences

<consequences>
**Pos:**
- ✅ Stable pointers (subscribers safe)
- ✅ No reallocation pauses
- ✅ stdlib only (no deps P1-3)
- ✅ Clear RocksDB migration path
- ✅ Predictable memory usage (1024 * sizeof(Event) per segment)

**Neg:**
- ❌ Slower iteration than ArrayList (segment boundaries)
- ❌ Memory fragmentation (non-contiguous segments)
- ❌ In-memory only (no persistence until P4)

**Mitigate:**
- Iteration → 1024-event segments minimize boundary overhead
- Fragmentation → <10K events means <10 segments (acceptable)
- Persistence → Clear Phase 4 migration plan, no data loss risk (tests only)
</consequences>

## Implementation

<implementation>
**Structure:**
```
src/event_store/
├── store.zig            # EventStore with SegmentedList ⏸ Phase 1b
└── store.test.zig       # Concurrency + pointer stability tests ⏸ Phase 1b
```

**EventStore:**
```zig
const std = @import("std");
const Event = @import("events.zig").Event;

pub const EventStore = struct {
    allocator: Allocator,
    events: std.segmented_list.SegmentedList(Event, 1024),
    subscribers: std.ArrayList(EventCallback),
    rw_lock: std.Thread.RwLock,
    count: std.atomic.Value(u64),

    pub fn init(allocator: Allocator) !*EventStore {
        const self = try allocator.create(EventStore);
        self.* = .{
            .allocator = allocator,
            .events = .{},
            .subscribers = std.ArrayList(EventCallback).init(allocator),
            .rw_lock = .{},
            .count = std.atomic.Value(u64).init(0),
        };
        return self;
    }

    pub fn append(self: *EventStore, event: Event) !EventOffset {
        self.rw_lock.lock();
        defer self.rw_lock.unlock();

        const offset = self.count.fetchAdd(1, .monotonic);
        try self.events.append(self.allocator, event);

        // Notify subscribers (stable pointer)
        for (self.subscribers.items) |callback| {
            callback(self.events.at(offset).*, offset);
        }

        return offset;
    }

    pub fn readFrom(self: *EventStore, offset: EventOffset) *const Event {
        self.rw_lock.lockShared();
        defer self.rw_lock.unlockShared();
        return self.events.at(offset);
    }

    pub fn readRange(self: *EventStore, start: EventOffset, end: EventOffset) EventIterator {
        return EventIterator{ .store = self, .start = start, .end = end, .current = start };
    }

    pub fn len(self: *EventStore) EventOffset {
        return self.count.load(.monotonic);
    }

    pub fn deinit(self: *EventStore) void {
        self.events.deinit(self.allocator);
        self.subscribers.deinit();
        self.allocator.destroy(self);
    }
};

pub const EventOffset = u64;
pub const EventCallback = *const fn (Event, EventOffset) void;
```

**Tests:**
- Pointer stability: append 1000 events, verify old pointers still valid
- Concurrent appends: Thread.Pool with 10 threads × 100 appends
- Concurrent reads: Parallel readFrom during appends
- Segment allocation: Verify 1024-event boundaries

**Phase 4 Migration:**
```zig
// RocksDB backend (Phase 4)
pub fn append(self: *EventStore, event: Event) !EventOffset {
    const offset = self.count.fetchAdd(1, .monotonic);
    const key = try std.fmt.allocPrint(self.allocator, "{d}", .{offset});
    defer self.allocator.free(key);
    const value = try event.toJson(self.allocator);
    defer self.allocator.free(value);
    try self.db.put(key, value);
    return offset;
}
```

**Docs:**
- API documentation in source
- `docs/architecture/event-sourcing.md` - Storage backend section
</implementation>

## Validation

<validation>
**Metrics:**
- Append latency: <1ms P95
- Read latency: <0.1ms per event
- Memory usage: ~1KB per event (Event size + overhead)
- Pointer stability: 100% (no invalidation)
- Segment count: <10 for typical test runs

**Monitor:**
- Append/read performance (P50/P95/P99)
- Memory allocation (total + per segment)
- Segment count growth
- Subscriber callback latency

**Review:**
- 3mo: Performance acceptable? Pointer stability working?
- 6mo: Ready for Phase 4 migration? RocksDB plan clear?
- 12mo: SegmentedList still best choice for P1-3?

**Revise if:**
- Pointer invalidation bugs found (investigate SegmentedList usage)
- Performance bottleneck <1ms (optimize or profile)
- Phase 4 migration harder than expected (revisit API design)
- Memory usage excessive (tune segment size)
</validation>

## Related

<related>
**ADR Dependencies:**
- **Depends on:** ADR-0001 (Event Sourcing Strategy)
- **Depends on:** ADR-0002 (Event Serialization Format)
- **Informs:** Future ADR (Phase 4 RocksDB Integration)

**Project Context:**
- **PRD:** [prd.md](../prd.md) §4.1 - Event Sourcing Architecture
- **Context:** [context.md](../context.md) - State Channel Prior Art
- **Phase:** [.claude/commands/1_phase_1_event_sourcing.md](../../.claude/commands/1_phase_1_event_sourcing.md)
- **Architecture:** [docs/architecture/event-sourcing.md](../architecture/event-sourcing.md) (TBD)

**Implementation:**
- **Code:** `src/event_store/store.zig` (Phase 1b)
- **Tests:** `src/event_store/store.test.zig` (Phase 1b)
- **Migration:** Phase 4 RocksDB backend

**External References:**
- [Zig SegmentedList](https://ziglang.org/documentation/master/std/#A;std:segmented_list) - stdlib docs
- [RocksDB](https://rocksdb.org/) - Persistent storage for Phase 4
- [go-nitro](https://github.com/statechannels/go-nitro) - In-memory store (comparison)
</related>

<changelog>
- 2025-11-08: Initial (Accepted) - Phase 1b
</changelog>
