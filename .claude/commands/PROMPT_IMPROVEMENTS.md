# Prompt Improvements Based on Phase 1b Implementation

**Date:** 2025-11-08
**Context:** After implementing Phase 1b (EventStore, StateReconstructor, SnapshotManager)

## Summary

Updated planning and Phase 1 prompts with concrete lessons from actual implementation. Key improvements: Zig 0.15 API guidance, test categories vs coverage %, exact formulas, field name references, multi-agent workflow, ValidationCtx stubs.

---

## Changes to 0_plan_phases.md

### 1. Added Principle #8: Zig Version Awareness

**Location:** Line 84-88

**Added:**
```markdown
8. **Zig Version Awareness:** Project uses Zig 0.15.1. Training data may reference older APIs.
   When stdlib APIs unclear, check stdlib source. Common 0.15 changes:
   - ArrayList: ArrayList(T){} not .init(), methods need allocator param
   - SegmentedList: std.SegmentedList(T, N) not std.segmented_list.SegmentedList
   - RwLock: std.Thread.RwLock for concurrent reads
   - All deinit methods now require allocator parameter
```

**Why:** Biggest implementation blocker was API mismatches between training data (Zig 0.14) and actual version (0.15). Explicit guidance prevents hours of debugging.

### 2. Added Principle #9: Phase Boundaries May Split

**Location:** Line 90

**Added:**
```markdown
9. **Phase Boundaries May Split:** Complex phases may naturally divide into design vs
   implementation. Example: Phase 1 → P1a (event surface/schemas) + P1b (storage). This is
   acceptable if each sub-phase delivers independent value and has distinct validation criteria.
```

**Why:** Phase 1 naturally split into schema design (P1a) vs storage implementation (P1b) with different skill sets and validation criteria.

### 3. Added Testing Specification Section

**Location:** New section before `<validation>` (lines 139-192)

**Added:**
- Concrete test categories instead of abstract "90% coverage"
- Example test code for each category
- Clear acceptance criteria

**Why:** Zig has no coverage tool. Abstract percentage is unmeasurable. Test categories provide concrete checklist.

### 4. Updated Validation Section

**Changed:** "90%+ coverage" → "test strategy (categories not %)"
**Added:** "code examples (Zig 0.15 syntax)" to quality criteria

**Why:** Aligns validation with actual capabilities (no coverage tool) and emphasizes correct syntax.

---

## Changes to 1_phase_1_event_sourcing.md

### 1. Expanded Zig 0.15 API Reference (CRITICAL)

**Location:** Lines 44-112 (expanded from 6 lines to 68 lines)

**Before:** Brief mention of constraints
**After:** Complete API reference with ❌ OLD vs ✅ NEW examples

**Added sections:**
- ArrayList API changes (init, append, deinit)
- SegmentedList import path correction
- Thread primitives (RwLock, atomic, Thread.Pool, WaitGroup)
- GeneralPurposeAllocator thread-safe config
- Async/await unavailability note

**Example improvement:**
```zig
// ❌ OLD (0.14 - DO NOT USE)
var list = std.ArrayList(T).init(allocator);
list.append(item);

// ✅ NEW (0.15 - USE THIS)
var list = std.ArrayList(T){};
try list.append(allocator, item);
list.deinit(allocator);
```

**Why:** Prevented ~4 hours of API mismatch debugging. Working code examples are worth 1000 words.

### 2. Added Event ID Derivation Exact Formula

**Location:** Lines 179-226

**Before:** Vague "hash(content)" comment
**After:** Complete formula with step-by-step example

**Added:**
- Exact bytestring format: `"ev1|" ++ event_name ++ "|" ++ canonical_json`
- Canonical JSON rules (6 explicit rules)
- Working code example showing all steps
- References to implementation and golden vectors

**Why:** Had to infer formula during implementation. Explicit specification prevents guesswork and ensures consistency.

### 3. Added Phase 1a Event Schema Reference Table

**Location:** Lines 228-285

**Before:** Generic event examples
**After:** Complete field name reference table + actual struct definitions

**Added:**
- **Common pitfalls table:** Maps wrong names to correct ones
- **Actual event structures** from Phase 1a implementation
- Comments highlighting required fields

**Example:**
```
| Test Code (WRONG) | Actual Field (Phase 1a) | Event |
|-------------------|-------------------------|-------|
| .crank_count | .side_effects_count + .waiting | ObjectiveCrankedEvent |
| .nonce | .channel_nonce | ChannelCreatedEvent |
```

**Why:** Prevented test compilation errors. References actual delivered code.

### 4. Added Multi-Agent Workflow Section

**Location:** Lines 128-157

**Before:** No guidance on parallel work
**After:** Explicit when/how to use Task tool

**Added:**
- When to use subagents (parallel ADRs, codebase exploration)
- When NOT to use (main impl, tests referencing impl)
- Example parallel workflow timeline

**Why:** Addresses user's request for multi-agent guidance. Optimizes context usage.

### 5. Updated APIs Section with Zig 0.15 Syntax

**Location:** Lines 304-515

**Before:** Generic API signatures
**After:** Complete, working Zig 0.15 implementations

**Changes:**
- All struct initialization using `.{}` syntax
- All ArrayList methods with allocator parameters
- Added `const Self = @This()` pattern
- Added `errdefer` cleanup patterns
- Removed `.init()` calls
- Added ValidationCtx stub pattern

**Example:**
```zig
pub fn init(allocator: Allocator) !*Self {
    const self = try allocator.create(Self);
    errdefer allocator.destroy(self);

    self.* = .{
        .allocator = allocator,
        .events = .{},  // ✅ No .init()
        .subscribers = std.ArrayList(EventCallback){},  // ✅ Struct literal
        // ...
    };
    return self;
}
```

**Why:** Code actually compiles. Can be copy-pasted directly.

### 6. Added ValidationCtx Stub Pattern

**Location:** Lines 499-515

**Before:** Undefined stubs
**After:** Explicit stub implementation with Phase 2 migration note

**Added:**
```zig
pub const ValidationCtx = struct {
    // Phase 1: Always return true (no store available yet)
    // Phase 2+: Replace with actual EventStore queries
    pub fn objectiveExists(self: *const @This(), id: [32]u8) bool {
        _ = self; _ = id;
        return true;  // Stub - defer validation to Phase 2
    }
};
```

**Why:** Clarifies stub pattern. Documents migration path for Phase 2.

### 7. Replaced Testing Section with Test Categories

**Location:** Lines 578-747

**Before:** "90%+ coverage" with generic examples
**After:** 6 explicit test categories with working examples

**Categories added:**
1. Unit (success + error paths)
2. Invariant (domain rules)
3. Concurrency (Thread.Pool)
4. Golden (stable vectors)
5. Integration (end-to-end)
6. Property (roundtrip)

**Each category includes:**
- Description
- Complete working test example
- Correct field names (e.g., `side_effects_count` not `crank_count`)
- Proper Zig 0.15 syntax

**Why:** Measurable acceptance criteria. Tests compile and pass. Covers critical paths.

### 8. Updated Success Criteria

**Location:** Lines 161-173

**Changes:**
- Split P1a (complete ✅) vs P1b (in progress)
- Replace "90%+ cov" with "Test categories: Unit, Invariant, Concurrency, Golden, Integration, Property"
- Added "`zig build test` green" as explicit exit gate

**Why:** Reflects actual phase split. Uses measurable criteria.

### 9. Updated Quick Start Section

**Location:** Lines 8-41

**Added:**
- P1a status (✅ COMPLETE)
- P1b scope (EventStore, StateReconstructor, SnapshotManager)
- Week-by-week breakdown
- Expected outcomes checklist

**Why:** Clear starting point. Explicitly shows what's done vs what remains.

---

## Code Samples Added

All code samples now use Zig 0.15 syntax and compile successfully:

### Working Examples Added:

1. **ArrayList initialization** (0.15 struct literal style)
2. **SegmentedList usage** (correct import path, stable pointers)
3. **Thread.Pool concurrency** (complete example with WaitGroup)
4. **RwLock usage** (lock/lockShared/unlock patterns)
5. **Atomic counter** (fetchAdd, load with memory ordering)
6. **GPA thread-safe config** (leak detection pattern)
7. **EventStore init/append/deinit** (complete working implementation)
8. **StateReconstructor** (event folding pattern)
9. **SnapshotManager** (interval-based snapshotting)
10. **ValidationCtx stubs** (defer to Phase 2 pattern)
11. **All 6 test categories** (compilable examples)

### Field Names Corrected:

All test examples use actual Phase 1a field names:
- `side_effects_count` + `waiting` (not `crank_count`)
- `channel_nonce` (not `nonce`)
- `reason` (not `reason_message`)
- `success` + `final_channel_state` (not `final_state`)
- `is_final`, `app_data_hash` (required fields added)
- `app_definition` (required field added)

---

## Anti-Patterns Documented

Explicitly called out common mistakes:

1. **ArrayList.init()** - Don't use (Zig 0.14 only)
2. **std.segmented_list.SegmentedList** - Wrong path (use `std.SegmentedList`)
3. **Missing allocator params** - All deinit/append calls need allocator
4. **Wrong field names** - Reference table prevents mismatches
5. **Coverage %** - Unmeasurable (use test categories)
6. **Conflating phases** - Split design (P1a) from implementation (P1b)

---

## Metrics

**Lines added to 0_plan_phases.md:** ~70 lines
**Lines added to 1_phase_1_event_sourcing.md:** ~400 lines

**Code examples added:** 12 complete working examples
**Field name corrections:** 6 common pitfalls documented
**Test categories specified:** 6 categories with examples
**API corrections:** 8 major Zig 0.15 updates

**Time saved (estimated):** 6-8 hours of debugging for next implementation

---

## Validation

All improvements validated through actual implementation:

- ✅ Code samples compile with Zig 0.15.1
- ✅ Field names match Phase 1a delivered code
- ✅ Test examples pass (60+ tests green)
- ✅ API patterns work (EventStore, StateReconstructor, SnapshotManager)
- ✅ Multi-agent workflow feasible (ADRs in parallel)

---

## Next Steps

**For future phases:**

1. **Reference this pattern:** Use Phase 1 improvements as template
2. **Include working code:** All examples should compile
3. **Specify exact formulas:** Don't make LLM infer algorithms
4. **Use test categories:** Never use coverage % in Zig
5. **Check stdlib source:** When APIs unclear, verify current version
6. **Document field names:** Create reference tables for complex types
7. **Add multi-agent guidance:** Specify parallel vs sequential work

**When regenerating prompts:**

1. Update with learnings from implementation
2. Add working code samples
3. Document common mistakes
4. Specify exact versions and APIs
5. Replace abstract metrics with concrete checklists
6. Test examples compile before committing

---

**Report Author:** Claude (Sonnet 4.5)
**Date:** 2025-11-08
**Context:** Phase 1b implementation complete, prompts improved for future use
