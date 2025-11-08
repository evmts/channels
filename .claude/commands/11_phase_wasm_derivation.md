# P11: WASM Derivation (Optional)

**Meta:** P11 | Deps: P1, P2, P9 | Owner: Core

## Zig WASM Features

**Compile TO wasm:**
- `zig build-exe -target wasm32-wasi` - official LLVM backend
- Tiny binaries (no GC, exceptions, aggressive DCE)
- Fast cold start, predictable perf

**Embed wasm runtime:**
- `wasmer-zig-api` (zig-wasm/wasmer-zig-api) - WASM/WASI bindings, updated 2025
- `wasm-zig` (zigwasm/wasm-zig) - common C API bindings
- wasmtime bindings less mature

**Rec:** Use wasmer-zig-api (active, full WASI). Zig-built WASM = tiny, fast.

## Summary

Core innovation - deterministic state derivation from message logs via WASM reducers + embedded PostgreSQL. Enables rich application state (SQL queries), transparent derivation (anyone can replay), compact on-chain representation (message log vs full state). Optional but high value - enables game/application use cases beyond payments. Most technically complex: WASM runtime integration, PGlite embedding, determinism guarantees, performance optimization.

## Objectives

- OBJ-1: Integrate WASM runtime (wasmer or wasmtime)
- OBJ-2: Embed PGlite (PostgreSQL in WASM) for derived state
- OBJ-3: Implement message log → DB derivation pipeline
- OBJ-4: Ensure determinism (same messages → same DB)
- OBJ-5: Performance optimization (caching, incremental updates)

## Success Criteria

**Done when:**
- WASM runtime integrated (hello world works)
- PGlite embedded (SQL works create table + query)
- Derivation deterministic (replay 100x → 100% identical)
- Perf: <5s derivation 1000 messages
- Cache optimization works (10x faster incremental)
- 70+ tests, 85%+ cov
- 2 ADRs approved (WASM runtime, determinism)
- Demo game working

**Exit gates:** Tests pass, integration (game app derivation), benchmarks met

## Architecture

**Components:** WasmRuntime (execute WASM reducers), PGliteManager (embedded PostgreSQL), DerivationEngine (message log → WASM → DB state), CacheManager (optimize repeated derivation)

**Flow:**
```
MessageLog[msg1..msgN] → DerivationEngine
  → WASM.reduce(db, msg1) → db'
  → WASM.reduce(db', msg2) → db''
  ... → Final DB state
```

**On-chain (if disputed):**
```
Submit: AppData = [msg1..msgN] (compact)
Validate: Replay in WASM → Derive DB → Check victory condition
```

## ADRs

**ADR-0016: WASM Runtime**
- Q: wasmer or wasmtime?
- Opts: A) wasmer | B) wasmtime | C) custom
- Rec: A
- Why: Better C API, Zig bindings available vs ⚠️ limited docs (ok doable)

**ADR-0017: Determinism Enforcement**
- Q: How ensure deterministic?
- Opts: A) Sandbox | B) WASI subset | C) Pure Zig
- Rec: A (sandbox no time/random/IO)
- Why: Strongest guarantee, provable vs ⚠️ restrictive (ok design constraint)

## Data Structures

```zig
pub const WasmRuntime = struct {
    engine: *wasmer.Engine,
    module: *wasmer.Module,

    pub fn call(self: *Self, function: []const u8, args: []wasmer.Value) ![]wasmer.Value;
};

pub const PGlite = struct {
    db: *pglite.Database,

    pub fn execute(self: *Self, sql: []const u8) !void;
    pub fn query(self: *Self, sql: []const u8) !QueryResult;
    pub fn export(self: *Self) ![]u8; // Serialize DB
    pub fn import(self: *Self, data: []u8) !void; // Restore
};

pub const DerivationEngine = struct {
    runtime: *WasmRuntime,
    pglite: *PGlite,
    cache: *CacheManager,

    pub fn deriveState(self: *Self, messages: []Message, a: Allocator) !*PGlite;
};
```

## APIs

```zig
// Init WASM runtime with reducer
pub fn initWasmRuntime(wasm_bytes: []const u8, a: Allocator) !*WasmRuntime;

// Derive state from message log
pub fn deriveState(messages: []Message, reducer_wasm: []const u8, a: Allocator) !*PGlite;
```

## Implementation

**W1-2:** WASM runtime integration + PGlite embedding + basic execution
**W3-4:** Derivation pipeline + determinism validation + caching
**W5-6:** Performance optimization + example game + demo + validation

**Tasks:** T1: Add wasmer (M) | T2: Wrap API (L) | T3: Integrate PGlite (XL) | T4: Derivation pipeline (L) | T5: Determinism tests (L) | T6: Cache impl (M) | T7: Perf optimization (L) | T8: Example game (XL) | T9: On-chain validation preview (L)

**Path:** T1→T2→T3→T4→T5→T6→T8

## Testing

**Unit:** 70+ tests
- WASM reducer executes deterministically
- PGlite queries work
- Cache speeds up repeated derivation

**Integration:**
- D&D game state derivation
- Messages (spawn, move, attack) → derive DB → query units → check victory

## Dependencies

**Req:** P1 (Event sourcing), P2 (State), P9 (Virtual channels for app channels)
**External:** wasmer (WASM runtime), PGlite (embedded PostgreSQL), Zig WASM support

## Risks

|Risk|P|I|Mitigation|
|--|--|--|--|
|PGlite integration extremely complex|H|H|6 weeks allocated, prototype early, consider alternatives|
|Non-determinism bugs (time/random)|M|Critical|Extensive fuzzing, sandbox enforcement, audits|
|Performance too slow (>10s)|M|H|Profile early, optimize hot paths, caching, WASM JIT|
|WASM memory limits|M|M|Monitor usage, set limits, handle OOM gracefully|
|On-chain validation expensive|M|M|Optimize reducer, use fault proofs (P12)|

## Deliverables

**Code:** `src/wasm/{runtime,pglite,derivation}.zig`, example game reducer, tests
**Docs:** ADR-0016/0017, `docs/architecture/wasm-derivation.md`, reducer guide
**Val:** 85%+ cov, determinism tests pass, perf benchmarks met, game demo

## Validation Gates

- G1: ADRs approved, WASM runtime working, PGlite basic queries work
- G2: Code review, determinism validated
- G3: Performance benchmarks met (<5s for 1000 messages)
- G4: Demo game works, docs complete, P12 unblocked

## Refs

**Phases:** P1 (Events), P2 (State), P9 (Virtual)
**ADRs:** 0016 (WASM runtime), 0017 (Determinism)
**External:** Wasmer docs, PGlite docs, PRD §4.3 Deterministic Derivation

## Example

```zig
// Load game reducer
const reducer_wasm = @embedFile("dnd_reducer.wasm");

// Derive state from message log
const app_data = channel.state.app_data;
const messages = try parseMessages(app_data, allocator);

const db = try deriveState(&messages, reducer_wasm, allocator);

// Query game state
const units = try db.query("SELECT * FROM units WHERE hp > 0");
const winner = try checkVictoryCondition(db);
```
