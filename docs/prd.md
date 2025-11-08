# EVENT-SOURCED STATE CHANNELS: PRODUCT REQUIREMENTS DOCUMENT

**Version:** 0.0.0
**Date:** 2025-11-07
**Status:** Draft
**Authors:** Fucory (currently ai generted though)

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Problem Statement](#2-problem-statement)
3. [Solution Overview](#3-solution-overview)
4. [Core Concepts](#4-core-concepts)
5. [System Architecture](#5-system-architecture)
6. [Detailed Requirements](#6-detailed-requirements)
7. [Protocol Specifications](#7-protocol-specifications)
8. [Implementation Roadmap](#8-implementation-roadmap)
9. [Technical Decisions & Rationale](#9-technical-decisions--rationale)
10. [Security Considerations](#10-security-considerations)
11. [Performance Targets](#11-performance-targets)
12. [Open Questions](#12-open-questions)
13. [References & Prior Art](#13-references--prior-art)

---

## 1. EXECUTIVE SUMMARY

### Vision

**Build the application layer for Blockchains: verifiable, high-performance, with improved trust assumptions through new primitives.**

We're creating infrastructure for **ephemeral, high-throughput applications** that inherit Ethereum's security without its cost or latency constraints. By combining state channel technology with event-sourcing architecture and embedded databases, we enable a new class of applications impossible with traditional blockchain or existing L2 solutions.

### Core Innovation

**Private, app-specific channels with transparent state derivation.**

Traditional state channels store state snapshots. We store **message logs** and derive state deterministically via WASM execution. Anyone can replay the message log to verify state correctness - no cryptographic proofs required. This is **blockchain's model** (consensus on transactions → derive state) applied to 2-party channels.

Multiparty is a virtual abstraction on top of the two party channel method.

### Target Users

**Phase 1:** Crypto nerds and early technologists

- Developers building high-frequency, stateful applications
- Gaming communities seeking provable fairness + instant finality
- Builders frustrated with rollup latency and composability constraints

**Phase 2:** Mainstream gamers (via viral D&D-style game)

- Players who want instant gameplay without gas fees
- Communities around competitive, skill-based games
- Users seeking transparent game mechanics (no hidden server logic)

### Success Metrics

- **Developer adoption:** 10+ games/apps built on framework within 6 months
- **User experience:** <100ms state updates, zero cost for in-game actions
- **Viral game traction:** 10K+ monthly active players
- **Protocol robustness:** <1% dispute rate, no loss of funds
- **Performance:** 1000+ state updates/second per channel

### Differentiation

Unlike rollups (general-purpose, composable) or Lightning (payments-only), we target **ephemeral, application-specific interactions**:

- Game matches (30 min - 3 hours)
- Trading sessions
- Collaborative editing
- Interactive media

Not for: DeFi, permanent storage, spontaneous transactions with strangers

---

## 2. PROBLEM STATEMENT

### Current State: Why State Channels Didn't Scale

**State channels didn't fail - they were solving the wrong problem.**

The initial wave of state channel development (Connext, Perun, Plasma) focused on **scaling DeFi**: enabling high-frequency trading, micropayments, and financial applications. This required trust assumptions the technology was fundamentally poor at solving until Rollups fundamentally changed the architecture.

- Exit problems made long term applications where state constantly grows challenging
- As the value secured scale the cost to attack via unique attack vectors like not sharing data availability needed to form proofs become viable
- The cost of opening and closing the channels themselves were expensive enough to struggle to scale costs meaningfully

### The Real Opportunity: Ephemeral Applications

**State channels excel where rollups are overkill:**

| Requirement       | Rollups               | State Channels          |
| ----------------- | --------------------- | ----------------------- |
| Latency           | 1-15 seconds          | <100ms (instant)        |
| Cost per action\* | $0.001-0.10           | $0 (off-chain)          |
| Privacy           | Public state          | Private until dispute   |
| Throughput        | 10-1000 TPS           | Unlimited (per channel) |
| Setup cost        | None                  | 1-2 on-chain txs        |
| Best for          | Permanent state, DeFi | Ephemeral interactions  |

- - Cost is marginal cost for additional actions beyond the cost of opening and closing the channel

**Games are the perfect use case:**

- ✅ **Liveness assumption already exists** - players online during match
- ✅ **Bounded duration** - match ends, close channel, discard state
- ✅ **High-frequency updates** - hundreds of moves, zero gas cost
- ✅ **Privacy desirable** - strategies hidden until match end
- ✅ **Instant finality required** - no waiting for block confirmation
- ✅ **No composability needed** - game logic is self-contained

### Technical Requirements for op-stack Integration

State channels on op-stack L2s require WASM-based state derivation support. Current gaps we address:

1. **Application framework** - Need WASM runtime for off-chain game logic:
   - Deterministic execution in disputes
   - Rich expressiveness for complex rules
   - Easy testing/debugging

2. **Rich state management** - Need structured state beyond opaque bytes:
   - Query game state (e.g., "which units in range?")
   - Handle state exceeding memory via embedded DB
   - Natural modeling of complex entities

3. **Event sourcing** - Need transparent state derivation:
   - Debug state transitions via replay
   - Complete audit trail
   - Test scenarios via message log replay

4. **Network effects** - Need hub infrastructure/discovery:
   - Player matchmaking
   - Hub operator incentives
   - Solve cold start problem

### Opportunity: Event Sourcing + Embedded DB

**Core insight:** Most games/applications naturally express state as **events** applied to a **database**:

```
Game move: "Attack unit 5 with unit 3"
         ↓ (deterministic WASM reducer)
Database: UPDATE units SET hp = hp - 20 WHERE id = 5;
```

**Benefits:**

- **Compact on-chain representation** - Message log (few KB) instead of full state (hundreds of KB)
- **Rich queries** - SQL for "find all units in range", "calculate victory conditions"
- **Natural expressiveness** - Game designers think in entities/relationships
- **Transparency** - Anyone can replay message log to verify state correctness
- **Debuggability** - Step through message log to understand bugs

**This enables Ethereum's trust model for applications:** Consensus on transaction log, derive state deterministically.

### Success Metrics

We'll know we've succeeded when:

1. **Developer experience:** Building a game takes days (not months) using our framework
2. **Player experience:** Games feel instant and free (no gas awareness)
3. **Trust model:** Players trust game fairness due to transparent derivation (not blind trust in server)
4. **Network effects:** Hub operators earn fees facilitating matches, creating sustainable ecosystem
5. **Viral growth:** One breakout game demonstrates feasibility, attracts more developers

---

## 3. SOLUTION OVERVIEW

### High-Level Architecture

**Three-layer design:**

```
┌──────────────────────────────────────────────────────────────┐
│  APPLICATION LAYER (D&D Game, Chess, etc.)                   │
│  - Game-specific logic in WASM                               │
│  - SQL queries against derived DB state                      │
│  - Message creation (player actions)                         │
└────────────────────┬─────────────────────────────────────────┘
                     │
┌────────────────────▼─────────────────────────────────────────┐
│  STATE CHANNEL ENGINE (Zig)                                  │
│  ┌────────────┐  ┌──────────────┐  ┌────────────────────┐   │
│  │ Objectives │  │ Event Store  │  │ Derivation Engine │   │
│  │ (Protocols)│  │ (Message Log)│  │ (WASM Runtime)    │   │
│  └────────────┘  └──────────────┘  └────────────────────┘   │
│  ┌────────────┐  ┌──────────────┐  ┌────────────────────┐   │
│  │  P2P Net   │  │ Chain Service│  │   PGlite/Postgres │   │
│  │  (libp2p)  │  │ (Ethereum)   │  │   (Derived State) │   │
│  └────────────┘  └──────────────┘  └────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
                     │
┌────────────────────▼─────────────────────────────────────────┐
│  BLOCKCHAIN LAYER (Ethereum/L2)                              │
│  - NitroAdjudicator (dispute resolution)                     │
│  - Channel funding/withdrawals                               │
│  - Challenge/timeout mechanism                               │
└──────────────────────────────────────────────────────────────┘
```

### Key Innovations

**1. Message Log as Source of Truth**

Traditional: `State.AppData = {board: [...], hp: [...], turn: 42}`
**Our approach:** `State.AppData = [msg1, msg2, msg3, ...]`

**Analogy:** Blockchain consensus model applied to 2-party channels

- Blockchain: Nodes agree on transaction order → derive state via EVM
- Our channels: Players agree on message order → derive state via WASM

**Benefits:**

- Compact: Message log << full state as game complexity grows
- Verifiable: Anyone can replay to check correctness
- Flexible: Change derivation logic without changing message log
- Debuggable: Step through messages to understand bugs

**2. Deterministic WASM Derivation**

```zig
// Pure function: same messages → same database state
fn deriveState(messages: []Message, wasm: []u8) !PGliteDB {
    var db = PGlite.init();
    var runtime = WasmRuntime.init(wasm);

    for (messages) |msg| {
        const dbState = db.export();
        const newState = runtime.call("reduce", dbState, msg);
        db.import(newState);
    }

    return db;
}
```

**Why WASM:**

- Deterministic execution (critical for consensus)
- Sandboxed (can't access network/filesystem)
- Fast (near-native performance)
- Portable (runs anywhere)
- Zig compiles to optimized WASM

**Why not EVM:**
You can use the EVM! Guillotine supports compiling EVM contracts to wasm. It will simply use the postgres database as it's backing ethereum state store.

**3. PostgreSQL as Derived State**

All actions are just emitting a ordered stream of postgresql commands giving us 3 levels of state

1. Raw Actions taken by one of the channel participants
2. The stream of POSTGRESQL updates
3. The actual state of the system

```sql
-- Game state materializes as SQL tables
SELECT * FROM units WHERE owner = 'player1' AND hp > 0;
SELECT COUNT(*) FROM units WHERE x BETWEEN 5 AND 10;

-- Victory conditions as queries
SELECT player_id FROM players WHERE
  (SELECT COUNT(*) FROM units WHERE owner = player_id) = 0;
```

**Why PostgreSQL:**

- **Expressiveness:** Complex game logic natural in relational model
- **Query power:** Find entities matching conditions (range queries, joins)
- **Familiarity:** Developers know SQL
- **PGlite:** Embedded WASM PostgreSQL, runs in-process

**Trade-off:** State doesn't scale forever (OK for ephemeral games)

- 1-hour game: ~1000 messages = ~100KB
- 10-hour session: ~10K messages = ~1MB
- Solution: Snapshot periodically (store DB state + recent messages)

### Technical Approach

**Core principles:**

1. **Event sourcing** - Store events, derive state
2. **Functional core** - Protocols are pure functions returning side effects
3. **Single-threaded event loop** - Predictable ordering, no race conditions
4. **Immutable updates** - Objectives never mutate, always return new copies
5. **Explicit allocators** - Zig's manual memory management for control
6. **Comptime optimization** - Zero-cost abstractions via Zig's comptime

**State channel best practices adopted:**

- ✅ Objective pattern (state machines with `Crank()`)
- ✅ Declarative side effects (messages/transactions returned, not executed)
- ✅ WaitingFor enumeration (explicit blocking states)
- ✅ Channel ownership tracking (one objective per channel)
- ✅ Event streams (transparent state derivation)
- ✅ Structured concurrency (Zig async)
- ✅ Tagged unions (type-safe variants)

**Why Zig over Go:**

- **WASM generation:** Zig produces smaller, faster WASM (10-100x smaller than Go)
- **No runtime:** No GC pauses, predictable performance
- **Explicit control:** Manual memory management, explicit allocators
- **Comptime:** Zero-cost abstractions, compile-time guarantees
- **C interop:** Seamless integration with libpq, secp256k1, etc.
- **Safety:** Compile-time checks prevent undefined behavior

---

## 4. CORE CONCEPTS

### 4.1 Event-Sourced State Channels

**Definition:** State channels where the source of truth is an ordered log of events (messages), not snapshots of state.

**Comparison:**

| Traditional State Channels       | Event-Sourced State Channels        |
| -------------------------------- | ----------------------------------- |
| `AppData = {hp: 80, x: 5, y: 3}` | `AppData = [Move(5,3), Attack(2)]`  |
| State grows with complexity      | Log size bounded by actions taken   |
| Hard to debug transitions        | Can replay events to understand bug |
| No audit trail                   | Full history preserved              |
| Can't change interpretation      | Can re-derive with updated logic    |

**Key insight:** This mirrors blockchain architecture:

- **Bitcoin/Ethereum:** UTXO set / account state is **derived** from transaction history
- **Our channels:** Database state is **derived** from message history

**Properties:**

1. **Append-only log:** Messages never deleted, only appended
2. **Deterministic derivation:** `f(messages) → state` is pure function
3. **Verifiable:** Any party can replay messages to verify correctness
4. **Time-travel:** Can reconstruct state at any point in history
5. **Event IDs:** Messages have unique IDs (hash of content) to prevent duplicates
6. **Proving via fault proves:** Because it's all wasm it gets verified on chain using fault proofs

**Example flow:**

```zig
// Message log (stored in channel)
messages = [
    {id: 0xABC..., type: "spawn_unit", unitId: 1, x: 5, y: 3, owner: "p1"},
    {id: 0xDEF..., type: "spawn_unit", unitId: 2, x: 8, y: 3, owner: "p2"},
    {id: 0x123..., type: "move_unit", unitId: 1, x: 6, y: 3},
    {id: 0x456..., type: "attack", attacker: 1, target: 2, damage: 20},
]

// Derived database state (not stored in channel)
units table:
┌────────┬───┬───┬────┬───────┐
│ unitId │ x │ y │ hp │ owner │
├────────┼───┼───┼────┼───────┤
│   1    │ 6 │ 3 │100 │  p1   │
│   2    │ 8 │ 3 │ 80 │  p2   │
└────────┴───┴───┴────┴───────┘

// On-chain (if disputed)
State.AppData = encode(messages[0..4])  // ~200 bytes
// NOT: encode(units table) // would be larger + less flexible
```

**Scalability consideration:**

- For long-running games: Implement **snapshots**
- Store `(snapshot_db_state, messages_since_snapshot)`
- Snapshots are optimization, not required for correctness

### 4.2 Message Log as Source of Truth

**Message structure:**

```zig
pub const Message = struct {
    id: [32]u8,           // Hash(channelId || turnNum || payload)
    type: []const u8,     // "spawn_unit", "move", "attack", etc.
    payload: json.Value,  // Type-specific data
    timestamp: i64,       // For ordering (not consensus-critical)
    playerIndex: u8,      // Which player sent (0 or 1 for 2-player)
};
```

**Channel state evolution:**

```
Turn 0: State {
    AppData: [],
    Outcome: [P1: 100, P2: 100],
    TurnNum: 0
}

P1 proposes:
Turn 1: State {
    AppData: [msg1],
    Outcome: [P1: 100, P2: 100],
    TurnNum: 1
} + P1.signature

P2 signs → Both have Turn 1

P2 proposes:
Turn 2: State {
    AppData: [msg1, msg2],
    Outcome: [P1: 100, P2: 100],
    TurnNum: 2
} + P2.signature

P1 signs → Both have Turn 2

... continues until game end ...

Final: State {
    AppData: [msg1...msgN],
    Outcome: [P1: 80, P2: 120],  // Winner gets pot
    TurnNum: N,
    IsFinal: true
}
```

**Properties:**

- Each state includes **all previous messages** (cumulative)
- Signatures commit to full message history (can't rewrite history)
- Turn number increases with each state update
- Outcome can change when game conditions met (checkmate, HP=0, etc.)

**Why not delta compression?**

- Could store `AppData = {base: turnNum, delta: [msgN]}` to save space
- Trade-off: More complex validation on-chain
- Decision: Start simple (full log), optimize later if needed

### 4.3 Deterministic Derivation (WASM)

**WASM Reducer Interface:**

```rust
// Compiled to WASM, embedded in channel engine
#[no_mangle]
pub extern "C" fn reduce(
    db_state_ptr: *const u8,    // Serialized PGlite state
    db_state_len: usize,
    message_ptr: *const u8,     // Serialized message
    message_len: usize,
    result_ptr: *mut *const u8, // Output: new DB state
    result_len: *mut usize
) -> i32 {
    let db = PGlite::from_bytes(unsafe {
        std::slice::from_raw_parts(db_state_ptr, db_state_len)
    });
    let msg: Message = serde_json::from_slice(unsafe {
        std::slice::from_raw_parts(message_ptr, message_len)
    }).unwrap();

    // Execute game logic
    match msg.type.as_str() {
        "spawn_unit" => {
            db.execute(
                "INSERT INTO units (id, x, y, hp, owner) VALUES ($1, $2, $3, 100, $4)",
                &[msg.payload["unitId"], msg.payload["x"], msg.payload["y"], msg.player_index]
            )?;
        }
        "move_unit" => {
            // Validate move is legal
            let unit = db.query_one(
                "SELECT * FROM units WHERE id = $1 AND owner = $2",
                &[msg.payload["unitId"], msg.player_index]
            )?;

            let distance = manhattan_distance(
                (unit.x, unit.y),
                (msg.payload["x"], msg.payload["y"])
            );
            if distance > 3 {
                return Err("move too far");
            }

            db.execute(
                "UPDATE units SET x = $1, y = $2 WHERE id = $3",
                &[msg.payload["x"], msg.payload["y"], msg.payload["unitId"]]
            )?;
        }
        "attack" => {
            // Check range, update HP, remove if dead
            let attacker = db.query_one("SELECT * FROM units WHERE id = $1", &[msg.payload["attacker"]])?;
            let target = db.query_one("SELECT * FROM units WHERE id = $1", &[msg.payload["target"]])?;

            if manhattan_distance((attacker.x, attacker.y), (target.x, target.y)) > attacker.range {
                return Err("target out of range");
            }

            let new_hp = target.hp - attacker.damage;
            if new_hp <= 0 {
                db.execute("DELETE FROM units WHERE id = $1", &[msg.payload["target"]])?;
            } else {
                db.execute("UPDATE units SET hp = $1 WHERE id = $2", &[new_hp, msg.payload["target"]])?;
            }
        }
        _ => return Err("unknown message type"),
    }

    // Serialize result
    let result_bytes = db.to_bytes();
    unsafe {
        *result_ptr = result_bytes.as_ptr();
        *result_len = result_bytes.len();
    }

    0 // Success
}
```

**Zig side (calling WASM):**

```zig
pub fn deriveState(allocator: Allocator, messages: []const Message, wasm_bytecode: []const u8) !PGliteState {
    var runtime = try WasmRuntime.init(allocator, wasm_bytecode);
    defer runtime.deinit();

    var db_state = PGliteState.init(allocator);

    for (messages) |msg| {
        const msg_json = try json.stringify(msg, allocator);
        defer allocator.free(msg_json);

        const db_bytes = try db_state.serialize(allocator);
        defer allocator.free(db_bytes);

        var result_ptr: [*]const u8 = undefined;
        var result_len: usize = undefined;

        const ret = runtime.call(
            "reduce",
            &[_]Val{
                Val.fromBytes(db_bytes.ptr, db_bytes.len),
                Val.fromBytes(msg_json.ptr, msg_json.len),
                Val.fromPtr(&result_ptr),
                Val.fromPtr(&result_len),
            }
        );

        if (ret != 0) return error.DerivationFailed;

        db_state.deinit();
        db_state = try PGliteState.deserialize(
            allocator,
            result_ptr[0..result_len]
        );
    }

    return db_state;
}
```

**Why deterministic execution matters:**

- Both players must arrive at same state from same messages
- Non-deterministic sources forbidden:
  - ❌ Random number generation (unless seeded from message)
  - ❌ System time (except from message timestamp)
  - ❌ File I/O
  - ❌ Network calls
- WASM sandbox enforces this

**Handling randomness:**

- Include seed in message: `{type: "roll_dice", seed: 0x123...}`
- Use deterministic PRNG: `fn random(seed) -> u64`
- Both players agree on seed (commit-reveal scheme if needed)

### 4.4 PGlite/PostgreSQL State Materialization

**Why PostgreSQL:**

1. **Relational model natural for games:**

```sql
CREATE TABLE units (
    id INTEGER PRIMARY KEY,
    x INTEGER NOT NULL,
    y INTEGER NOT NULL,
    hp INTEGER NOT NULL,
    max_hp INTEGER NOT NULL,
    attack INTEGER NOT NULL,
    range INTEGER NOT NULL,
    owner TEXT NOT NULL,
    unit_type TEXT NOT NULL
);

CREATE TABLE game_state (
    turn_number INTEGER PRIMARY KEY,
    phase TEXT NOT NULL,  -- 'movement', 'combat', 'ended'
    current_player TEXT NOT NULL,
    winner TEXT
);

CREATE INDEX idx_units_owner ON units(owner);
CREATE INDEX idx_units_position ON units(x, y);
```

2. **Query power for game logic:**

```sql
-- Find all enemies in attack range
SELECT t.* FROM units a
JOIN units t ON t.owner != a.owner
WHERE a.id = $1
  AND ABS(t.x - a.x) + ABS(t.y - a.y) <= a.range;

-- Check victory condition
SELECT owner, COUNT(*) as unit_count
FROM units
GROUP BY owner
HAVING COUNT(*) > 0;

-- Get visible units (fog of war)
SELECT u.* FROM units u
WHERE EXISTS (
    SELECT 1 FROM units my
    WHERE my.owner = $1
      AND ABS(u.x - my.x) + ABS(u.y - my.y) <= my.vision_range
);
```

3. **PGlite advantages:**

- **Embedded:** Runs in same process as channel engine (no IPC overhead)
- **WASM:** Can compile to WASM for portability
- **Full PostgreSQL:** Not a subset - full SQL, triggers, indexes
- **Small:** ~3MB WASM bundle

**State serialization:**

- PGlite can export/import full DB state as bytes
- For snapshots: Serialize to disk or memory
- For derivation: Start from empty DB, apply messages

**Performance considerations:**

- **In-memory:** PGlite runs in RAM (fast)
- **No persistence needed:** Derive on demand, discard after
- **Indexes:** Create indexes for frequent queries (attack range, ownership)
- **Transactions:** Wrap each message in transaction (atomic application)

**Alternative: Custom in-memory structures**

- Phase 2 consideration: Replace PGlite with custom Zig data structures
- Trade-off: Performance vs expressiveness
- Decision: Start with PGlite (familiar, powerful), optimize later if needed

### 4.5 Proving results onchain

Proofs are done via fault proofs. Similar to the OneStepProver in arbitrum system.

Arbitrum is not open source so we owuld need to build this from scratch or use MIPs instead (optimism has a OSS mips contract)

### 4.5 Hub-Based Tournament Architecture

**Problem:** Cold start

- Alice wants to play chess
- Needs existing channel with Bob
- Opening channel costs $10-20 (on-chain tx)
- Can't play if she doesn't know anyone

**Solution: Hub as intermediary**

```
Hub Operator (runs server, earns fees)
  Opens ledger channels with many players
  Facilitates virtual channels between players
  Must stay online (liveness requirement)
  Compensated via fees
```

**Ledger channel structure:**

```
Alice ←─────── Ledger Channel ──────────→ Hub
  Funded: Alice 100 ETH, Hub 100 ETH
  Can create virtual channels through hub

Hub ←─────── Ledger Channel ──────────→ Bob
  Funded: Hub 100 ETH, Bob 100 ETH
  Can create virtual channels through hub
```

**Virtual channel creation (Alice vs Bob):**

```
1. Alice requests match with Bob via hub API
2. Hub coordinates 3-party protocol:
   - Alice signs prefund state for virtual channel
   - Bob signs prefund state
   - Hub signs prefund state
3. Hub updates ledger channels with "guarantees":

   Ledger(Alice-Hub):
   ┌──────────────────┐
   │ Alice:      90   │  (reduced by 10)
   │ Hub:       100   │
   │ Guarantee:  10   │  (backs virtual channel)
   └──────────────────┘

   Ledger(Hub-Bob):
   ┌──────────────────┐
   │ Hub:        90   │  (reduced by 10)
   │ Bob:       100   │
   │ Guarantee:  10   │  (backs virtual channel)
   └──────────────────┘

   Virtual(Alice-Bob):
   ┌──────────────────┐
   │ Alice:      10   │
   │ Bob:        10   │
   └──────────────────┘

4. Alice and Bob play game off-chain
   - Hub never sees game states
   - Hub only involved in setup/teardown

5. Game ends, close virtual channel:
   - Final outcome: [Alice: 15, Bob: 5]  (Alice won)
   - Update ledger channels:

   Ledger(Alice-Hub):
   ┌──────────────────┐
   │ Alice:      95   │  (got back 15 from guarantee)
   │ Hub:       105   │  (lost 5 to Alice)
   │ Guarantee:   0   │
   └──────────────────┘

   Ledger(Hub-Bob):
   ┌──────────────────┐
   │ Hub:        95   │  (won 5 from Bob)
   │ Bob:       105   │  (got back 5 from guarantee)
   │ Guarantee:   0   │
   └──────────────────┘
```

**Hub economics:**

- **Capital requirement:** Hub must lock funds in ledger channels
- **Revenue models:**
  1. **Fee per game:** Hub charges 1-5% of pot
  2. **Subscription:** Monthly fee for unlimited games
  3. **Entry fees:** Tournament entry fees go to hub
- **Costs:**
  1. Capital lockup (opportunity cost)
  2. Server operation
  3. Liveness requirement (must respond to close requests)
- **Profit:** Fees > Costs + (Capital \* risk-free rate)

**Hub discovery:**

- **Phase 1:** Centralized registry (we run)
- **Phase 2:** On-chain registry (smart contract lists hubs)
- **Phase 3:** P2P gossip (hubs advertise via DHT)

**Multi-hub routing (future):**

```
Alice ←─ Ledger ─→ Hub1 ←─ Ledger ─→ Hub2 ←─ Ledger ─→ Bob
Alice ←═══════════ Virtual Channel ═══════════════════→ Bob
  (routed through 2 hubs, both take cut)
```

**Comparison to Lightning Network:**

- **Similar:** Hub = Lightning node, Virtual = Lightning payment
- **Different:**
  - We target games (bounded duration) not payments (ongoing)
  - No path finding needed (hub-based topology simpler)
  - Richer state (full DB) not just balances

---

## 5. SYSTEM ARCHITECTURE

### 5.1 Component Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           APPLICATION LAYER                              │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐  │
│  │   D&D Game       │  │   Chess Game     │  │   Custom Game        │  │
│  │  (WASM Reducer)  │  │  (WASM Reducer)  │  │   (WASM Reducer)     │  │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────────┘  │
│           │ Messages             │ Messages             │ Messages       │
└───────────┼──────────────────────┼──────────────────────┼────────────────┘
            │                      │                      │
┌───────────▼──────────────────────▼──────────────────────▼────────────────┐
│                       STATE CHANNEL ENGINE (Zig)                          │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐ │
│  │                        EVENT LOOP (Main Thread)                      │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │ │
│  │  │ API Requests │  │ Chain Events │  │ P2P Messages             │  │ │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────────────────┘  │ │
│  │         │                  │                  │                      │ │
│  │         └──────────────────┼──────────────────┘                      │ │
│  │                            ▼                                         │ │
│  │                 ┌──────────────────────┐                            │ │
│  │                 │  Event Dispatcher    │                            │ │
│  │                 └──────────┬───────────┘                            │ │
│  │                            │                                         │ │
│  │         ┌──────────────────┼──────────────────┐                     │ │
│  │         │                  │                  │                     │ │
│  │         ▼                  ▼                  ▼                     │ │
│  │  ┌────────────┐  ┌─────────────────┐  ┌────────────┐              │ │
│  │  │ Objective  │  │  Channel         │  │  Payment   │              │ │
│  │  │ Manager    │  │  Manager         │  │  Manager   │              │ │
│  │  └──────┬─────┘  └────────┬────────┘  └──────┬─────┘              │ │
│  │         │                  │                  │                     │ │
│  │         └──────────────────┼──────────────────┘                     │ │
│  │                            ▼                                         │ │
│  │                  ┌──────────────────┐                               │ │
│  │                  │ Side Effects     │                               │ │
│  │                  │ Executor         │                               │ │
│  │                  └──────────────────┘                               │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                                                                           │
│  ┌───────────────────────────┐   ┌────────────────────────────────────┐ │
│  │     EVENT STORE           │   │   DERIVATION ENGINE                │ │
│  │  ┌────────────────────┐   │   │  ┌──────────────────────────────┐ │ │
│  │  │ Objective Events   │   │   │  │   WASM Runtime               │ │ │
│  │  │ - Created          │   │   │  │   (wasmtime / wasmer)       │ │ │
│  │  │ - Approved         │   │   │  └────────────┬─────────────────┘ │ │
│  │  │ - Cranked          │   │   │               │                    │ │
│  │  │ - Completed        │   │   │               ▼                    │ │
│  │  └────────────────────┘   │   │  ┌──────────────────────────────┐ │ │
│  │                           │   │  │   PGlite / PostgreSQL        │ │ │
│  │  ┌────────────────────┐   │   │  │   (Derived State)            │ │ │
│  │  │ Channel Events     │   │   │  │  ┌────────┐  ┌────────────┐  │ │ │
│  │  │ - StateAdded       │   │   │  │  │ units  │  │ game_state │  │ │ │
│  │  │ - DepositDetected  │   │   │  │  └────────┘  └────────────┘  │ │ │
│  │  │ - Challenged       │   │   │  └──────────────────────────────┘ │ │
│  │  └────────────────────┘   │   └────────────────────────────────────┘ │
│  │                           │                                          │
│  │  ┌────────────────────┐   │   ┌────────────────────────────────────┐ │
│  │  │ Message Events     │   │   │   PROJECTIONS (Query Side)         │ │
│  │  │ - Sent             │   │   │  ┌──────────────────────────────┐ │ │
│  │  │ - Received         │   │   │  │ ObjectiveProjection          │ │ │
│  │  └────────────────────┘   │   │  │  - status, waitingFor        │ │ │
│  └───────────────────────────┘   │  └──────────────────────────────┘ │ │
│                                   │  ┌──────────────────────────────┐ │ │
│                                   │  │ ChannelProjection            │ │ │
│                                   │  │  - latestTurnNum, onChain    │ │ │
│                                   │  └──────────────────────────────┘ │ │
│                                   └────────────────────────────────────┘ │
│                                                                           │
│  ┌───────────────────────────┐   ┌────────────────────────────────────┐ │
│  │    P2P NETWORKING         │   │   CHAIN SERVICE                    │ │
│  │  ┌────────────────────┐   │   │  ┌──────────────────────────────┐ │ │
│  │  │ libp2p Host        │   │   │  │   Ethereum RPC Client        │ │ │
│  │  │ - TCP Transport    │   │   │  │   (JSON-RPC over HTTP)       │ │ │
│  │  │ - Peer Discovery   │   │   │  └────────────┬─────────────────┘ │ │
│  │  │ - Message Routing  │   │   │               │                    │ │
│  │  └────────────────────┘   │   │               ▼                    │ │
│  │                           │   │  ┌──────────────────────────────┐ │ │
│  │  ┌────────────────────┐   │   │  │   Event Listener             │ │ │
│  │  │ Message Codec      │   │   │  │   - Deposited                │ │ │
│  │  │ - Serialize        │   │   │  │   - ChallengeRegistered      │ │ │
│  │  │ - Deserialize      │   │   │  │   - Concluded                │ │ │
│  │  └────────────────────┘   │   │  └──────────────────────────────┘ │ │
│  └───────────────────────────┘   │                                    │ │
│                                   │  ┌──────────────────────────────┐ │ │
│                                   │  │   Transaction Submitter      │ │ │
│                                   │  │   - Deposit                  │ │ │
│                                   │  │   - Challenge                │ │ │
│                                   │  │   - Withdraw                 │ │ │
│                                   │  └──────────────────────────────┘ │ │
│                                   └────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────┘
                                      │
                                      │ RPC/WebSocket
                                      │
                          ┌───────────▼──────────────┐
                          │   ETHEREUM / L2          │
                          │  ┌────────────────────┐  │
                          │  │ NitroAdjudicator   │  │
                          │  │ (Solidity)         │  │
                          │  └────────────────────┘  │
                          └──────────────────────────┘
```

### 5.2 Data Flow

**Command Flow (User Action → State Update):**

```
1. User Action (e.g., "Move unit to (5,3)")
   │
   ▼
2. Application Layer creates Message
   message = {type: "move_unit", unitId: 1, x: 5, y: 3}
   │
   ▼
3. Engine receives via API
   ObjectiveRequest{channelId, message}
   │
   ▼
4. Objective Manager looks up active objective
   objective = store.getObjectiveByChannel(channelId)
   │
   ▼
5. Objective processes message
   newState = {
     AppData: [oldMessages..., message],
     TurnNum: oldTurnNum + 1,
     Outcome: oldOutcome  // unchanged yet
   }
   │
   ▼
6. Sign new state
   signature = sign(hash(newState), secretKey)
   signedState = (newState, {myIndex: signature})
   │
   ▼
7. Store event
   event = ObjectiveEvent.StateSigned{signedState}
   eventStore.append(objectiveId, event)
   │
   ▼
8. Generate side effects
   sideEffects = [
     SendMessage{to: counterparty, payload: signedState}
   ]
   │
   ▼
9. Execute side effects
   p2pService.send(counterparty, signedState)
   │
   ▼
10. Update projection
    projection.latestTurnNum = newState.TurnNum
    projection.waitingFor = "CounterpartySignature"
```

**Query Flow (User queries game state):**

```
1. User Query (e.g., "Which units can attack?")
   │
   ▼
2. Application requests derived state
   db = engine.getDerivedState(channelId)
   │
   ▼
3. Engine checks if cached
   if (derivedStateCache.has(channelId)) {
     return derivedStateCache.get(channelId)
   }
   │
   ▼
4. Rebuild from events
   messages = channel.getLatestState().AppData
   wasmBytecode = channel.getDerivationFunction()
   │
   ▼
5. Derivation Engine applies messages
   db = PGlite.init()
   for (msg in messages) {
     db = wasmRuntime.call("reduce", db, msg)
   }
   │
   ▼
6. Cache result
   derivedStateCache.put(channelId, db)
   │
   ▼
7. Application queries DB
   results = db.query(`
     SELECT u.* FROM units u
     WHERE u.owner = $1
       AND EXISTS (
         SELECT 1 FROM units t
         WHERE t.owner != $1
           AND ABS(t.x - u.x) + ABS(t.y - u.y) <= u.range
       )
   `, [myPlayerId])
   │
   ▼
8. Return to user
   UI displays "Units 1, 3, 5 can attack"
```

**Counterparty Message Flow:**

```
1. Receive P2P message
   p2pService → eventLoop: MessageReceived{from, payload}
   │
   ▼
2. Decode payload
   signedState = decode(payload)
   │
   ▼
3. Validate signature
   signer = recoverSigner(hash(signedState.state), signedState.sig)
   assert(signer == counterpartyAddress)
   │
   ▼
4. Validate state transition
   oldState = channel.getLatestState()
   assert(signedState.state.TurnNum == oldState.TurnNum + 1)
   assert(signedState.state.AppData starts with oldState.AppData)
   │
   ▼
5. Derive new DB state (validate message is legal)
   newMessages = signedState.state.AppData[oldState.AppData.length..]
   db = derivationEngine.apply(oldDBState, newMessages)
   if (error) reject("illegal move")
   │
   ▼
6. Update channel
   channel.addSignedState(signedState)
   │
   ▼
7. Store event
   event = ChannelEvent.StateAdded{signedState}
   eventStore.append(channelId, event)
   │
   ▼
8. Sign our copy
   signature = sign(hash(signedState.state), secretKey)
   fullySignedState = merge(signedState, {myIndex: signature})
   │
   ▼
9. Send back to counterparty
   sideEffects = [SendMessage{to: counterparty, payload: fullySignedState}]
   p2pService.send(counterparty, fullySignedState)
   │
   ▼
10. Update UI
    notify("Counterparty moved")
```

**Chain Event Flow:**

```
1. Ethereum emits event
   NitroAdjudicator.Deposited(channelId, asset, amount)
   │
   ▼
2. ChainService listener receives
   websocket → chainService: NewBlock{events: [...]}
   │
   ▼
3. Parse event
   event = DepositedEvent{
     channelId: 0xABC...,
     asset: 0x0 (ETH),
     amount: 100 ether,
     blockNum: 12345
   }
   │
   ▼
4. Wait for confirmations
   if (blockNum + 2 > latestBlock) queue(event)
   │
   ▼
5. Dispatch to Engine
   chainService → eventLoop: ChainEvent{event}
   │
   ▼
6. Update channel
   channel.onChainHoldings[asset] += amount
   │
   ▼
7. Store event
   event = ChannelEvent.DepositDetected{asset, amount, blockNum}
   eventStore.append(channelId, event)
   │
   ▼
8. Trigger objective crank
   objective = store.getObjectiveByChannel(channelId)
   objective.crank() // May unblock waiting objective
   │
   ▼
9. Execute side effects
   // e.g., sign postfund state now that deposits complete
```

### 5.3 Technology Stack (Zig-First)

**Core Engine (Zig):**

- **Language:** Zig 0.13+ (stable)
- **Build:** Zig build system (`build.zig`, `build.zig.zon`)
- **Standard library:** std (collections, crypto, JSON, HTTP)
- **Memory:** Explicit allocators (arena, GPA for different use cases)

**Cryptography:**

- **Library:** Zabi (https://github.com/Raiden1411/zabi)
  - secp256k1 ECDSA signatures
  - Keccak256 hashing
  - ABI encoding/decoding
  - RLP serialization
- **Alternative secp256k1:** zig-eth-secp256k1 (if Zabi insufficient)

**Database (Derived State):**

- **PGlite:** WASM-based PostgreSQL (https://pglite.dev/)
  - Embedded, no separate process
  - Full SQL support
  - ~3MB WASM bundle
- **Zig bindings:** Custom via `@cImport()` or WASM interface
- **Fallback:** SQLite with zig-sqlite bindings

**WASM Runtime:**

- **Library:** wasmer-zig or wasmtime bindings
  - Execute game reducer WASM
  - Sandbox execution
  - Memory limits
- **Alternative:** Custom WASM interpreter (if bindings immature)

**Networking:**

- **HTTP/WebSocket:** http.zig (https://github.com/karlseguin/http.zig)
  - 140K req/s on M2
  - Pure Zig, no C deps
- **libp2p:** zen-eth/zig-libp2p (https://github.com/zen-eth/zig-libp2p)
  - QUIC transport
  - Gossipsub
  - **Note:** Pre-release, may need forking/contributions
- **Alternative:** Custom TCP with discovery via HTTP registry

**Ethereum Integration:**

- **RPC Client:** Zabi HTTP client or custom via http.zig
  - JSON-RPC 2.0
  - WebSocket subscriptions for events
- **Contract Bindings:** Code-gen from ABI (similar to abigen)
  - Parse ABI JSON
  - Generate Zig functions for contract calls

**Serialization:**

- **JSON:** std.json (built-in)
- **MessagePack:** msgpack.zig for compact binary (optional)
- **ABI:** Zabi ABI encoder

**Storage (Event Store):**

- **Embedded DB:** RocksDB via zig-rocksdb bindings
  - Key-value store for events
  - LSM tree, good for writes
- **Alternative:** BuntDB (Go) via CGO bridge (if RocksDB immature)
- **Development:** In-memory HashMap

**Testing:**

- **Unit:** Zig test (built-in)
- **Integration:** Multi-process tests (spawn nodes, simulate network)
- **Fuzz:** Custom fuzzer or AFL integration

**Build & Deploy:**

- **Cross-compile:** Zig native (single command for Linux/Mac/Windows)
- **WASM target:** `zig build-lib -target wasm32-freestanding`
- **Docker:** Multi-stage build (compile in Alpine, run in distroless)
- **CI:** GitHub Actions with Zig cache

**Dependencies (via `build.zig.zon`):**

```zig
.{
    .name = "state-channels",
    .version = "0.1.0",
    .dependencies = .{
        .zabi = .{
            .url = "https://github.com/Raiden1411/zabi/archive/refs/tags/v0.18.0.tar.gz",
            .hash = "...",
        },
        .@"http.zig" = .{
            .url = "https://github.com/karlseguin/http.zig/archive/refs/tags/v0.1.0.tar.gz",
            .hash = "...",
        },
        .@"zig-libp2p" = .{
            .url = "https://github.com/zen-eth/zig-libp2p/archive/main.tar.gz",
            .hash = "...",
        },
        // ... others
    },
}
```

**Smart Contracts (Solidity):**

- **Implement for op-stack:**
  - NitroAdjudicator.sol
  - ForceMove.sol
  - MultiAssetHolder.sol
- **Modifications:** None initially (battle-tested contracts)
- **Tooling:** Hardhat for compilation/testing/deployment

**Frontend (Phase 2):**

- **Framework:** SvelteKit or Next.js
- **Web3:** viem + wagmi for Ethereum interactions
- **WASM:** Load game reducer in browser for spectating/validation

### 5.6 Architectural Patterns for State Channels

**Core patterns proven effective in production state channel implementations:**

#### 5.6.1 Patterns to Adopt (Proven Architecture)

**Objective/Crank Pattern** (ADR 0001)

The core abstraction is the "Objective" - a state machine representing a protocol (DirectFund, VirtualFund, etc.):

```go
type Objective interface {
    Crank(secretKey) (Objective, SideEffects, WaitingFor)
    Approve() Objective
    Reject() Objective
    Update(payload) Objective
    OwnsChannel(id) bool
}
```

**Key insights:**
- **Pure functions:** `Crank()` returns new objective + side effects (doesn't mutate)
- **Flowchart model:** No explicit FSM states stored, computed from extended state
- **Restartable:** Can call `Crank()` repeatedly until completes
- **WaitingFor states:** Explicit enumeration of blocking conditions
  - `WaitingForCompletePrefund`
  - `WaitingForMyTurnToFund`
  - `WaitingForTheirTurnToFund`
  - `WaitingForCompletePostfund`
  - etc.

**Our Zig translation:**
```zig
pub const Objective = union(enum) {
    direct_fund: DirectFundObjective,
    direct_defund: DirectDefundObjective,
    virtual_fund: VirtualFundObjective,
    virtual_defund: VirtualDefundObjective,

    pub fn crank(
        self: *const Objective,
        allocator: Allocator,
        secret_key: []const u8,
    ) !CrankResult {
        return switch (self.*) {
            .direct_fund => |obj| try obj.crank(allocator, secret_key),
            // ... other protocols
        };
    }
};

pub const CrankResult = struct {
    objective: Objective,
    side_effects: SideEffects,
    waiting_for: WaitingFor,
};
```

**Why preserve:** Proven pattern, enables protocol composition, clear separation of concerns.

---

**Channel Ownership Model**

State channels track which objective "owns" each channel:

```go
// In store:
channelToObjective map[ChannelId]ObjectiveId

// Only one objective can modify a channel at a time
// Released when objective completes
```

**Benefits:**
- Prevents concurrent modification bugs
- Clear responsibility model
- Easier to reason about channel lifecycle

**Our approach:** Maintain this pattern using event store metadata.

---

**Consensus Channel Pattern** (Ledger Channels)

Special handling for ledger channels that require coordinated updates:

```go
type ConsensusChannel struct {
    leader   ParticipantId
    follower ParticipantId
    proposals Queue[SignedProposal]
}
```

**Rules:**
- Proposals must be processed in order (ADR 0004)
- Leader/follower roles for proposal initiation
- Guarantees managed through ledger updates
- Used for virtual channel funding/defunding

**Our approach:** Implement as special objective type with ordered event processing.

---

#### 5.6.2 Pain Points to Address

**1. Snapshot-Based State (No Event Sourcing)**

**Problem:**
- Traditional implementations store current state only (no history)
- Can't explain how state was reached
- Debugging requires reproducing bug from scratch
- No audit trail for disputes

**Impact:**
```go
// Traditional snapshot store
GetObjective(id) -> Objective     // Latest state only
SetObjective(id, obj) -> void     // Overwrites

// Missing: How did we get here?
// Missing: What sequence of events occurred?
```

**Our solution:**
- Event log as source of truth
- State derived from events
- Full audit trail preserved
- Time-travel debugging

---

**2. Object Hydration Complexity**

**Problem:**
- Objectives stored without channel data
- Must fetch channels separately on load
- Error-prone (easy to forget hydration)

```go
// Load objective from disk (JSON)
obj := decode(json)

// Must manually hydrate with channel references
obj = populateChannelData(obj, store)  // Easy to forget!
```

**Our solution:**
- Events contain all context needed
- No separate channel fetching
- Reconstruction is self-contained

---

**3. Goroutine Complexity**

**Problem:**
- Complex concurrency with channels and goroutines
- Hard to debug race conditions
- Goroutine leaks possible
- Non-deterministic ordering

**Our solution:**
- Zig's async/await for structured concurrency
- Single-threaded event loop (deterministic)
- Explicit control flow (no hidden concurrency)

---

**4. String-Based WaitingFor**

**Problem:**
```go
type WaitingFor string  // Stringly typed!

const (
    WaitingForNothing = ""
    WaitingForCompletePrefund = "WaitingForCompletePrefund"
    // ... no compile-time checking
)
```

**Our solution:**
```zig
pub const WaitingFor = union(enum) {
    nothing,
    complete_prefund: CompletePrefundInfo,
    my_turn_to_fund: MyTurnInfo,
    their_turn_to_fund: TheirTurnInfo,
    // ... type-safe with payload
};
```

---

#### 5.6.3 Testing Strategies to Adopt

**Integration Test Pattern** (from `/node_test/integration_test.go`):

```go
type TestCase struct {
    Chain          ChainType        // Mock or Simulated
    MessageService MessageServiceType
    NumOfChannels  uint
    NumOfHops      uint             // Virtual channel routing
    NumOfPayments  uint
}
```

**Key practices:**
1. **Parameterized tests:** Run same logic with different configs
2. **Test actors:** Reusable Alice/Bob/Hub/Irene personas
3. **Deterministic fixtures:** Shared test data in `/internal/testdata/`
4. **Mock vs Simulated:** Both lightweight mocks and full blockchain simulation

**Our adoption:**
```zig
const TestScenario = struct {
    chain: ChainType,
    message_service: MessageServiceType,
    num_channels: u32,
    num_hops: u32,
    num_payments: u32,

    pub fn run(self: TestScenario, allocator: Allocator) !void {
        // Parameterized test execution
    }
};

test "virtual payment with hub" {
    try TestScenario{
        .chain = .mock,
        .num_channels = 2,
        .num_hops = 1,
        .num_payments = 10,
    }.run(testing.allocator);
}
```

---

**Property-Based Testing:**
- Fuzz test objective state machines
- Verify invariants (e.g., "sum of allocations == total funds")
- Test serialization round-trips
- Signature verification properties

---

#### 5.6.4 ADR Methodology

Following state channel best practices, we adopt Architectural Decision Records:

**Reference ADR patterns from prior implementations:**
- Offchain Protocols as Flowcharts
- Consensus Ledger Channels
- Proposal Messaging (ordered processing)
- Persistent Storage strategies

**Our ADR process:**
- ADRs in `/docs/adrs/`
- Template in `/docs/adr-template.md`
- Numbered sequentially (0001, 0002, ...)
- Immutable once accepted (new ADRs supersede old)
- See: `docs/adrs/0000-adrs.md` for methodology

**Critical ADRs to write:**
1. **ADR-0001:** Event Sourcing for State Management
2. **ADR-0002:** Zig as Implementation Language
3. **ADR-0003:** Message Serialization Format
4. **ADR-0004:** WASM Runtime Choice
5. **ADR-0005:** Snapshot Optimization Strategy

---

#### 5.6.5 Key Takeaways

**Architectural Patterns to Preserve:**
✅ Objective/Crank pattern (flowchart-based state machines)
✅ Pure function objectives with side effects separation
✅ Channel ownership model
✅ Consensus channel leader/follower pattern
✅ Multi-layered architecture (Engine/Store/Chain/Message)

**Improvements Our Design Makes:**
🚀 Event sourcing from day one (biggest differentiator)
🚀 Binary serialization for performance
🚀 Zig async/await instead of goroutines
🚀 Strong typing for states (tagged unions)
🚀 Formal verification considerations
🚀 Better observability and monitoring

**Critical Success Factors:**
⚠️ Maintain objective purity (no side effects in Crank)
⚠️ Ensure event log atomicity
⚠️ Handle chain reorganizations correctly
⚠️ Preserve proposal ordering in consensus channels
⚠️ Implement deposit safety logic correctly

**References:**
- State channel architecture patterns
- Protocol specification documents
- Integration test methodologies
- ADR best practices

---

## 6. DETAILED REQUIREMENTS

### 6.1 Core State Channel Engine (Zig)

**Reference:** State channel engine architecture

**Requirements:**

**R6.1.1 Event Loop**

- MUST run in single thread (no race conditions)
- MUST use Zig's async/await for I/O
- MUST process events from 4 sources:
  1. API requests (user commands)
  2. Chain events (deposits, challenges)
  3. P2P messages (counterparty updates)
  4. Timers (periodic tasks)
- MUST process events sequentially (one completes before next starts)
- MUST handle errors gracefully (non-fatal continue, fatal panic)

**R6.1.2 Objective Management**

- MUST support 4 objective types:
  1. DirectFund (open ledger channel) - ref: `/protocols/directfund/directfund.go`
  2. DirectDefund (close ledger channel) - ref: `/protocols/directdefund/directdefund.go`
  3. VirtualFund (open virtual channel) - ref: `/protocols/virtualfund/virtualfund.go`
  4. VirtualDefund (close virtual channel) - ref: `/protocols/virtualdefund/virtualdefund.go`
- MUST implement Objective interface:

  ```zig
  pub const Objective = union(enum) {
      DirectFund: DirectFundObjective,
      VirtualFund: VirtualFundObjective,
      DirectDefund: DirectDefundObjective,
      VirtualDefund: VirtualDefundObjective,

      pub const CrankResult = struct {
          objective: Objective,
          sideEffects: SideEffects,
          waitingFor: WaitingFor,
      };

      pub fn crank(self: *Objective, allocator: Allocator, secretKey: []const u8) !CrankResult;
      pub fn approve(self: Objective, allocator: Allocator) !Objective;
      pub fn getId(self: Objective) ObjectiveId;
      pub fn getStatus(self: Objective) ObjectiveStatus;
  };
  ```

- MUST track objective ownership (one objective per channel) - ref: `/node/engine/store/store.go:channel_to_objective`
- MUST crank objectives when relevant events occur
- MUST persist objective events before executing side effects

**R6.1.3 Channel Management**

- MUST track channel state (on-chain and off-chain)
- MUST store signed states indexed by turn number
- MUST validate state transitions (turn number increments, valid signatures)
- MUST track latest supported state (highest turn with all signatures)
- MUST handle on-chain events (deposits, challenges, conclusions)

**R6.1.4 Side Effects Execution**

- MUST execute side effects after persistence
- MUST support 3 side effect types:
  1. SendMessage (P2P to counterparty)
  2. SubmitTransaction (on-chain)
  3. ProcessProposal (ledger channel update)
- MUST use structured concurrency (no leaked goroutines)
- MUST handle failures (retry logic, error propagation)

**R6.1.5 Policy Management**

- MUST support auto-approval policy for trusted counterparties
- MUST allow manual approval for untrusted counterparties
- SHOULD support configurable policies (whitelist, blacklist, always-ask)

### 6.2 Message Protocol

**Requirements:**

**R6.2.1 Message Structure**

- MUST include message ID (hash of content for deduplication)
- MUST include message type (string discriminator)
- MUST include JSON payload (type-specific data)
- MUST include player index (which player sent)
- SHOULD include timestamp (for ordering, not consensus-critical)
- Example:
  ```zig
  pub const Message = struct {
      id: [32]u8,
      type: []const u8,
      payload: json.Value,
      playerIndex: u8,
      timestamp: i64,
  };
  ```

**R6.2.2 State Structure**

- MUST use standard state channel State structure for on-chain compatibility
- MUST include:
  ```zig
  pub const State = struct {
      participants: []Address,
      channelNonce: u64,
      appDefinition: Address,
      challengeDuration: u32,
      appData: []const u8,  // Encoded message log
      outcome: Outcome,
      turnNum: u64,
      isFinal: bool,
  };
  ```
- appData MUST encode message log (JSON array or MessagePack)
- MUST hash state for signing using Ethereum ABI encoding

**R6.2.3 Signature Handling**

- MUST use secp256k1 ECDSA
- MUST use Ethereum signed message format (`\x19Ethereum Signed Message:\n32` prefix)
- MUST recover signer address from signature
- MUST validate signer is participant
- MUST track signatures per participant index

**R6.2.4 P2P Message Format**

- MUST batch payloads (multiple updates in one message) - ref: `/protocols/messages.go:38`
- MUST include:
  ```zig
  pub const P2PMessage = struct {
      to: Address,
      from: Address,
      objectivePayloads: []ObjectivePayload,
      ledgerProposals: []SignedProposal,
      payments: []Voucher,
      rejectedObjectives: []ObjectiveId,
  };
  ```
- MUST serialize to JSON for transmission
- SHOULD compress large messages (gzip)

### 6.3 WASM Derivation Runtime

**Requirements:**

**R6.3.1 WASM Loading**

- MUST load WASM bytecode from file or memory
- MUST validate WASM module (magic number, version)
- MUST instantiate WASM runtime (wasmer/wasmtime)
- SHOULD cache compiled modules (avoid recompilation)

**R6.3.2 Reducer Interface**

- MUST export function: `reduce(db_state: *const u8, db_len: usize, message: *const u8, msg_len: usize) -> *const u8`
- MUST pass database state as bytes (serialized PGlite)
- MUST pass message as JSON bytes
- MUST return new database state as bytes
- MUST handle errors (return error code, not panic)

**R6.3.3 Sandboxing**

- MUST limit WASM memory (e.g., 128MB max)
- MUST limit execution time (e.g., 1 second timeout per message)
- MUST prevent file I/O access
- MUST prevent network access
- SHOULD track gas/fuel usage (prevent infinite loops)

**R6.3.4 Determinism**

- MUST produce identical output for identical inputs
- MUST NOT allow non-deterministic sources:
  - System time (except from message timestamp)
  - Random number generation (unless seeded from message)
  - External state
- SHOULD validate determinism via test suite (replay multiple times)

### 6.4 PGlite Integration

**Requirements:**

**R6.4.1 Embedding**

- MUST run PGlite in-process (no separate daemon)
- SHOULD use WASM build of PGlite (portability)
- MUST initialize fresh database for each derivation
- SHOULD support persistent databases (for caching)

**R6.4.2 SQL Execution**

- MUST support full PostgreSQL SQL (CREATE, SELECT, INSERT, UPDATE, DELETE)
- MUST support transactions (BEGIN, COMMIT, ROLLBACK)
- MUST support indexes (for query performance)
- SHOULD support triggers (for game logic hooks)

**R6.4.3 Serialization**

- MUST export database state to bytes
- MUST import database state from bytes
- SHOULD use PostgreSQL's native dump format (pg_dump)
- SHOULD compress exported state (zstd/lz4)

**R6.4.4 Schema Management**

- MUST allow custom schemas (application-defined tables)
- SHOULD support schema migrations (for game updates)
- SHOULD validate schema at derivation start (fail fast if invalid)

**R6.4.5 Performance**

- SHOULD keep database in memory (no disk I/O)
- SHOULD reuse database connections (connection pooling)
- SHOULD cache derived state (invalidate on new message)
- Target: <10ms per message derivation

### 6.5 Smart Contracts (Solidity)

**Reference:** Standard state channel contracts for op-stack

**Requirements:**

**R6.5.1 Contract Implementation**

- MUST implement standard state channel contracts:
  - NitroAdjudicator.sol (adjudication logic)
  - ForceMove.sol (force move game)
  - MultiAssetHolder.sol (asset management)
- MUST NOT modify core logic (security risk)
- MAY add new app contracts (custom validation logic)

**R6.5.2 App Contract Interface**

- MUST implement IForceMoveApp:
  ```solidity
  interface IForceMoveApp {
      function stateIsSupported(
          FixedPart calldata fixedPart,
          RecoveredVariablePart[] calldata proof,
          RecoveredVariablePart calldata candidate
      ) external view returns (bool, string memory);
  }
  ```
- SHOULD validate message format (not full execution)
  - Reason: Full WASM execution on-chain is expensive
  - Approach: Validate message structure, trust derivation off-chain
- Example:

  ```solidity
  contract MessageLogApp is IForceMoveApp {
      function stateIsSupported(...) external pure returns (bool, string memory) {
          Message[] memory oldMsgs = decodeMessages(proof[0].appData);
          Message[] memory newMsgs = decodeMessages(candidate.appData);

          // Validate exactly 1 new message
          require(newMsgs.length == oldMsgs.length + 1, "must append 1 message");

          // Validate message format
          Message memory newMsg = newMsgs[newMsgs.length - 1];
          require(bytes(newMsg.msgType).length > 0, "invalid message type");
          require(newMsg.playerIndex < fixedPart.participants.length, "invalid player");

          // Validate turn taking
          require(newMsg.playerIndex == expectedPlayer(candidate.turnNum), "wrong player");

          return (true, '');
      }
  }
  ```

**R6.5.3 Deployment**

- MUST deploy to Ethereum mainnet and major L2s (Arbitrum, Optimism, Base)
- MUST verify contracts on Etherscan
- SHOULD use CREATE2 for deterministic addresses (ref: `/packages/nitro-protocol/contracts/deploy/Create2Deployer.sol`)

### 6.6 P2P Networking

**Requirements:**

**R6.6.1 Transport**

- MUST support direct TCP connections
- SHOULD support libp2p (if bindings mature)
- SHOULD support WebRTC (browser compatibility)
- MUST handle NAT traversal (STUN/TURN or relay via hub)

**R6.6.2 Peer Discovery**

- MUST support manual peer addition (address + multiaddr)
- SHOULD support HTTP registry (centralized discovery)
- MAY support DHT (decentralized discovery in Phase 2)

**R6.6.3 Message Delivery**

- MUST guarantee delivery (retry + ack)
- MUST detect duplicates (message ID deduplication)
- SHOULD preserve ordering (within same channel)
- SHOULD handle offline peers (queue messages, timeout after 1 hour)

**R6.6.4 Security**

- MUST encrypt messages (TLS 1.3 or noise protocol)
- MUST authenticate peers (verify Ethereum address ownership)
- SHOULD support peer blacklisting (block malicious peers)

### 6.7 Hub/Tournament System

**Requirements:**

**R6.7.1 Hub Operator**

- MUST open ledger channels with multiple players
- MUST facilitate virtual channel setup (3-party protocol)
- MUST stay online 24/7 (>99.9% uptime)
- MUST respond to close requests within 1 hour
- MAY charge fees (percentage or fixed)

**R6.7.2 Matchmaking**

- MUST expose API for match requests:
  ```typescript
  POST /api/match
  {
    "gameType": "chess",
    "playerId": "0xAlice...",
    "wager": "0.1 ETH"
  }
  ```
- MUST pair compatible players (similar skill, same game, same wager)
- MUST create virtual channel between matched players
- MUST handle unpaired requests (timeout after 5 minutes)

**R6.7.3 Hub Registry**

- MUST provide on-chain registry contract:

  ```solidity
  contract HubRegistry {
      struct Hub {
          address operator;
          string endpoint;  // "https://hub.example.com"
          uint256 feeBps;   // Basis points (100 = 1%)
          uint256 reputation;
      }

      mapping(address => Hub) public hubs;

      function registerHub(string endpoint, uint256 feeBps) external;
      function updateReputation(address hub, bool positive) external;
  }
  ```

- SHOULD track hub reputation (uptime, disputes, user ratings)

---

## 7. PROTOCOL SPECIFICATIONS

### 7.1 Channel Lifecycle

**Direct (Ledger) Channel:**

```
┌──────────────────────────────────────────────────────────────┐
│ Phase 1: PREFUNDING                                          │
├──────────────────────────────────────────────────────────────┤
│ Alice                                    Bob                 │
│   │                                       │                  │
│   │ CreateLedgerChannel(Bob, 100 ETH)    │                  │
│   ├──────────────────────────────────────►│                  │
│   │   ObjectivePayload{prefund request}  │                  │
│   │                                       │                  │
│   │◄─────── Sign prefund state ──────────┤                  │
│   │   State{turnNum: 0, outcome: [0, 0]} │                  │
│   │   + Bob.signature                     │                  │
│   │                                       │                  │
│   ├─────────► Sign prefund state ────────►│                  │
│   │   State{turnNum: 0} + Alice.signature│                  │
│   │                                       │                  │
│   ✅ Both have fully signed prefund state                   │
│   WaitingFor: MyTurnToFund (Alice first)                    │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ Phase 2: FUNDING                                             │
├──────────────────────────────────────────────────────────────┤
│ Alice                Ethereum              Bob               │
│   │                     │                   │                │
│   ├──► Deposit 100 ETH──┤                   │                │
│   │   tx: deposit(      │                   │                │
│   │     channelId,      │                   │                │
│   │     amount: 100     │                   │                │
│   │   )                 │                   │                │
│   │                     │                   │                │
│   │◄────── Deposited ───┤                   │                │
│   │   event             │                   │                │
│   │                     │                   │                │
│   │                     │◄── Deposit 100 ───┤                │
│   │                     │                   │                │
│   │                     ├──── Deposited ────►│                │
│   │                     │   event           │                │
│   │                     │                   │                │
│   ✅ On-chain holdings = 200 ETH                             │
│   WaitingFor: CompletePostfund                               │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ Phase 3: POSTFUNDING                                         │
├──────────────────────────────────────────────────────────────┤
│ Alice                                    Bob                 │
│   │                                       │                  │
│   │◄──── Sign postfund state ────────────┤                  │
│   │  State{turnNum: 1, outcome:[100,100]}│                  │
│   │  + Bob.signature                      │                  │
│   │                                       │                  │
│   ├────────► Sign postfund ──────────────►│                  │
│   │  State{turnNum: 1} + Alice.signature │                  │
│   │                                       │                  │
│   ✅ CHANNEL OPEN                                            │
│   WaitingFor: Nothing (objective complete)                   │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ Phase 4: OPERATION (Game Play)                               │
├──────────────────────────────────────────────────────────────┤
│ Alice                                    Bob                 │
│   │                                       │                  │
│   │ User action: "spawn unit"             │                  │
│   ├─────► State{turnNum: 2} ─────────────►│                  │
│   │  AppData: [msg1]                      │                  │
│   │  + Alice.signature                    │                  │
│   │                                       │                  │
│   │◄────── State{turnNum: 2} ────────────┤                  │
│   │  + Bob.signature                      │                  │
│   │                                       │                  │
│   │                    User action: "move"│                  │
│   │◄────── State{turnNum: 3} ────────────┤                  │
│   │  AppData: [msg1, msg2]                │                  │
│   │  + Bob.signature                      │                  │
│   │                                       │                  │
│   ├─────► State{turnNum: 3} ─────────────►│                  │
│   │  + Alice.signature                    │                  │
│   │                                       │                  │
│   ... hundreds of turns, all off-chain ...                   │
│                                                              │
│   Game ends: Alice wins                                      │
│   │                                       │                  │
│   │◄──── Final state ────────────────────┤                  │
│   │  State{                               │                  │
│   │    turnNum: 500,                      │                  │
│   │    outcome: [180, 20],  ← Alice won   │                  │
│   │    isFinal: true                      │                  │
│   │  }                                    │                  │
│   │  + Bob.signature                      │                  │
│   │                                       │                  │
│   ├────────► + Alice.signature ──────────►│                  │
│   │                                       │                  │
│   ✅ Both have final state                                   │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ Phase 5: DEFUNDING                                           │
├──────────────────────────────────────────────────────────────┤
│ Alice                Ethereum              Bob               │
│   │                     │                   │                │
│   ├──► Conclude ────────┤                   │                │
│   │   tx: conclude(     │                   │                │
│   │     finalState      │                   │                  │
│   │   )                 │                   │                │
│   │                     │                   │                │
│   │◄─── Concluded ──────┤                   │                │
│   │   event             │                   │                │
│   │                     │                   │                │
│   │                     ├──── Concluded ────►│                │
│   │                     │                   │                │
│   ├──► Withdraw 180 ────┤                   │                │
│   │                     │                   │                │
│   │                     │◄─── Withdraw 20 ──┤                │
│   │                     │                   │                │
│   ✅ CHANNEL CLOSED                                          │
└──────────────────────────────────────────────────────────────┘
```

**Virtual Channel (via Hub):**

```
┌──────────────────────────────────────────────────────────────┐
│ Prerequisites: Alice & Bob have ledger channels with Hub     │
│   Alice ←─[Ledger]─→ Hub ←─[Ledger]─→ Bob                  │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ Phase 1: VIRTUAL PREFUND                                     │
├──────────────────────────────────────────────────────────────┤
│ Alice              Hub                Bob                    │
│   │                 │                  │                     │
│   │ Match request   │                  │ Match request      │
│   ├────────────────►│◄─────────────────┤                     │
│   │                 │                  │                     │
│   │                 │ Coordinate 3-party signature           │
│   │◄──── Prefund ───┤──── Prefund ────►│                     │
│   │ State{turnNum:0}│ State{turnNum:0} │                     │
│   │                 │                  │                     │
│   ├──► + Alice.sig ─┤                  │                     │
│   │                 ├──► + Hub.sig ────┤                     │
│   │                 │                  ├──► + Bob.sig        │
│   │                 │◄─────────────────┤                     │
│   │◄────────────────┤                  │                     │
│   │                 │                  │                     │
│   ✅ All have prefund state (turnNum 0)                      │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ Phase 2: FUND LEDGERS                                        │
├──────────────────────────────────────────────────────────────┤
│ Update ledger channels with guarantees:                      │
│                                                              │
│ Ledger(Alice-Hub):                                           │
│   Before: [Alice: 100, Hub: 100]                            │
│   After:  [Alice: 90, Hub: 100, Guarantee: 10]              │
│                                                              │
│ Ledger(Hub-Bob):                                             │
│   Before: [Hub: 100, Bob: 100]                              │
│   After:  [Hub: 90, Bob: 100, Guarantee: 10]                │
│                                                              │
│ (Uses consensus channel proposals)                           │
│                                                              │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ Phase 3: VIRTUAL POSTFUND                                    │
├──────────────────────────────────────────────────────────────┤
│ Alice              Hub                Bob                    │
│   │                 │                  │                     │
│   │◄─── Postfund ───┤──── Postfund ───►│                     │
│   │ State{          │ State{           │                     │
│   │   turnNum: 1,   │   turnNum: 1,    │                     │
│   │   outcome:      │   outcome:       │                     │
│   │     [A:10,B:10] │     [A:10,B:10]  │                     │
│   │ }               │ }                │                     │
│   │                 │                  │                     │
│   ├──► All sign ────┤──────────────────┤                     │
│   │                 │                  │                     │
│   ✅ VIRTUAL CHANNEL OPEN (no on-chain tx!)                  │
│                                                              │
│   Hub can now exit (not needed for game play)                │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ Phase 4: GAME PLAY (2-party, Hub not involved)               │
├──────────────────────────────────────────────────────────────┤
│ Alice                                    Bob                 │
│   │                                       │                  │
│   │◄─────── States turnNum 2-500 ────────►│                  │
│   │   (exactly same as ledger channel)    │                  │
│   │                                       │                  │
│   ✅ Hub never sees these states                             │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ Phase 5: VIRTUAL DEFUND                                      │
├──────────────────────────────────────────────────────────────┤
│ Alice              Hub                Bob                    │
│   │                 │                  │                     │
│   │ CloseChannel()  │                  │                     │
│   ├────────────────►│◄─────────────────┤                     │
│   │                 │                  │                     │
│   │ Final: [A:15,B:5] (Alice won)      │                     │
│   │                 │                  │                     │
│   │ Update ledger channels:             │                     │
│   │                 │                  │                     │
│   │ Ledger(Alice-Hub):                 │                     │
│   │   [Alice: 95, Hub: 105]  ← Hub loses 5                  │
│   │                 │                  │                     │
│   │ Ledger(Hub-Bob):                   │                     │
│   │   [Hub: 95, Bob: 105]  ← Hub wins 5│                     │
│   │                 │                  │                     │
│   ✅ Net: Hub breaks even, Alice +5, Bob -5                  │
│   ✅ VIRTUAL CHANNEL CLOSED (still no on-chain tx!)          │
└──────────────────────────────────────────────────────────────┘
```

### 7.2 Message Format

**Channel State (on-chain compatible):**

```zig
pub const State = struct {
    // Fixed part (determines channel ID)
    participants: []Address,        // [Alice, Bob] or [Alice, Hub, Bob]
    channelNonce: u64,             // Unique per participant set
    appDefinition: Address,        // Smart contract address
    challengeDuration: u32,        // Seconds (e.g., 86400 = 1 day)

    // Variable part (changes each turn)
    appData: []const u8,           // Encoded message log
    outcome: Outcome,              // Token allocations
    turnNum: u64,                  // Monotonically increasing
    isFinal: bool,                 // True when channel closing

    pub fn channelId(self: State) [32]u8 {
        // Must match Solidity: keccak256(abi.encode(fixedPart))
        return keccak256(abiEncode(.{
            self.participants,
            self.channelNonce,
            self.appDefinition,
            self.challengeDuration,
        }));
    }

    pub fn hash(self: State) [32]u8 {
        // Must match Solidity: keccak256(abi.encode(variablePart))
        return keccak256(abiEncode(.{
            self.channelId(),
            self.appData,
            self.outcome,
            self.turnNum,
            self.isFinal,
        }));
    }
};
```

**Game Message (inside appData):**

```zig
pub const GameMessage = struct {
    id: [32]u8,              // keccak256(channelId || turnNum || type || payload)
    type: []const u8,        // "spawn_unit", "move_unit", "attack", etc.
    payload: json.Value,     // Type-specific data
    playerIndex: u8,         // 0 or 1 for 2-player
    timestamp: i64,          // Unix timestamp (ms)
};

// appData encoding:
// JSON: json.stringify([msg1, msg2, ...])
// or MessagePack for compactness
```

**Example appData content:**

```json
[
  {
    "id": "0xabc123...",
    "type": "spawn_unit",
    "payload": { "unitId": 1, "x": 5, "y": 3, "unitType": "warrior" },
    "playerIndex": 0,
    "timestamp": 1704067200000
  },
  {
    "id": "0xdef456...",
    "type": "move_unit",
    "payload": { "unitId": 1, "x": 6, "y": 3 },
    "playerIndex": 0,
    "timestamp": 1704067215000
  },
  {
    "id": "0x789abc...",
    "type": "attack",
    "payload": { "attacker": 1, "target": 2 },
    "playerIndex": 0,
    "timestamp": 1704067230000
  }
]
```

**Size estimates:**

- Per message: ~150-300 bytes (JSON)
- 100 messages: ~15-30 KB
- 1000 messages: ~150-300 KB
- Compression (gzip): ~40-60% reduction

### 7.3 State Structure

**Outcome Encoding:**

```zig
pub const Outcome = struct {
    assetAllocations: []AssetAllocation,

    pub const AssetAllocation = struct {
        asset: Address,           // 0x0 for ETH, token address for ERC20
        allocations: []Allocation,

        pub const Allocation = struct {
            destination: [32]u8,  // Participant or external address
            amount: u256,
        };
    };
};

// Example: 2-player game with ETH wagers
outcome = Outcome{
    .assetAllocations = &[_]AssetAllocation{
        AssetAllocation{
            .asset = Address.zero(),  // ETH
            .allocations = &[_]Allocation{
                Allocation{ .destination = alice.address, .amount = 100 },
                Allocation{ .destination = bob.address, .amount = 100 },
            },
        },
    },
};

// After Alice wins:
outcome = Outcome{
    .assetAllocations = &[_]AssetAllocation{
        AssetAllocation{
            .asset = Address.zero(),
            .allocations = &[_]Allocation{
                Allocation{ .destination = alice.address, .amount = 180 },
                Allocation{ .destination = bob.address, .amount = 20 },
            },
        },
    },
};
```

### 7.4 Consensus Mechanism

**2-Party Channels (Simple):**

- Each state requires **both signatures** to be valid
- Turn-taking: Player X signs odd turns, Player Y signs even turns
- Or: Free signing (either player can propose, both must sign)

**3+ Party Channels (Complex):**

- Virtual channels involve 3 parties: Alice, Intermediary, Bob
- Prefund/Postfund require **all signatures**
- Game states (turn 2+) only need Alice + Bob (Intermediary not involved)

**Signing protocol:**

```
1. Proposer creates new state (turnNum = current + 1)
2. Proposer signs state
3. Proposer sends to counterparty
4. Counterparty validates:
   a. turnNum increments by 1
   b. appData is valid (append-only, messages well-formed)
   c. Derive DB state, check no illegal moves
   d. Signature valid
5. Counterparty signs state
6. Counterparty sends back signature
7. Both have fully signed state
```

**Reject protocol:**

```
If counterparty finds invalid state:
1. Send rejection message
2. Halt channel (no further updates accepted)
3. Either:
   a. Negotiate resolution off-chain
   b. Submit last valid state on-chain (challenge)
```

### 7.5 Dispute Resolution

**Optimistic Model:**

- Assume players act honestly
- Only go on-chain if dispute

**Challenge Process:**

```
┌──────────────────────────────────────────────────────────────┐
│ Scenario: Bob disappears or refuses to sign final state     │
├──────────────────────────────────────────────────────────────┤
│ Alice                Ethereum              Bob               │
│   │                     │                   │                │
│   │ Submit challenge    │                   │                │
│   ├────────────────────►│                   │                │
│   │ tx: challenge(      │                   │                │
│   │   latestState,      │                   │                │
│   │   signatures        │                   │                │
│   │ )                   │                   │                │
│   │                     │                   │                │
│   │◄── ChallengeReg ───┤                   │                │
│   │   event             │                   │                │
│   │                     │                   │                │
│   │                     │                   │                │
│   │          ⏰ Challenge period (24 hours)                   │
│   │                     │                   │                │
│   │                     │    Bob can respond│                │
│   │                     │◄──────────────────┤                │
│   │                     │ tx: checkpoint(   │                │
│   │                     │   newerState      │                │
│   │                     │ )                 │                │
│   │                     │                   │                │
│   │          If Bob responds: Alice must submit newer state  │
│   │          (Continue until timeout with no response)       │
│   │                     │                   │                │
│   │          ⏰ Timeout (no response from Bob)                │
│   │                     │                   │                │
│   │ Finalize            │                   │                │
│   ├────────────────────►│                   │                │
│   │ tx: conclude()      │                   │                │
│   │                     │                   │                │
│   │◄─── Concluded ──────┤                   │                │
│   │                     │                   │                │
│   ├──► Withdraw ────────┤                   │                │
│   │                     │                   │                │
│   ✅ Alice receives funds per last valid state               │
└──────────────────────────────────────────────────────────────┘
```

**Key properties:**

- **Challenge period:** Gives Bob time to respond (e.g., 24 hours)
- **Checkpoint:** Bob can submit newer state to overrule Alice's challenge
- **Finalize:** After timeout, latest unchallenged state becomes final
- **Griefing prevention:** Losing party may lose collateral if challenge frivolous

**Cost analysis:**

- **Happy path:** 0 gas (all off-chain)
- **Cooperative close:** ~100K gas (~$5-20)
- **Dispute (1 challenge):** ~200K gas (~$10-40)
- **Dispute (multiple rounds):** ~50K gas per checkpoint (~$3-10 each)

---

## 8. IMPLEMENTATION ROADMAP

**Implementation Philosophy:** Documentation-Driven, Test-Driven Development

We adopt a rigorous development methodology:

1. **Documentation First:** Write specs, ADRs, and API docs before code
2. **Tests Second:** Write failing tests that define success criteria
3. **Implementation Third:** Write code to pass tests
4. **Validation Fourth:** Code review, performance testing, security review

**Planning Framework:**

- **Phase Templates:** Each phase follows `docs/phase-template.md` structure
- **ADR Documentation:** Architectural decisions documented per `docs/adrs/0000-adrs.md`
- **Phase Prompts:** Detailed phase plans in `.claude/commands/N_phase_*.md`
- **Validation Gates:** Each phase has explicit success criteria and exit gates

**Deliverables per Phase:**

- ✅ **Documentation:** Architecture docs, API specs, ADRs
- ✅ **Tests:** Unit tests (90%+ coverage), integration tests, benchmarks
- ✅ **Code:** Implementation passing all tests
- ✅ **Validation:** Code review, performance validation, demo

**ADRs to Create Across Phases:**

- **ADR-0001:** Event Sourcing for State Management (Phase 1)
- **ADR-0002:** Zig as Implementation Language (Phase 1)
- **ADR-0003:** Message Serialization Format (Phase 1)
- **ADR-0004:** WASM Runtime Choice (Phase 2)
- **ADR-0005:** Snapshot Optimization Strategy (Phase 2)
- **ADR-0006:** PGlite Integration Approach (Phase 2)
- **ADR-0007:** Virtual Channel Routing (Phase 3)
- **ADR-0008:** Hub Economics and Fee Structure (Phase 3)
- **ADR-0009:** Multi-Chain Deployment Strategy (Phase 4)
- **ADR-0010:** Developer SDK Architecture (Phase 5)

---

### Phase 1: Event Sourcing Foundation & Core Engine (Months 1-3)

**Phase Document:** `.claude/commands/1_phase_1_event_sourcing.md`

**Goal:** Minimal viable state channel engine in Zig

**Deliverables:**

1. **Event loop & objective management**

   - Single-threaded event dispatcher
   - DirectFund/DirectDefund objectives
   - Event store (in-memory for now)

2. **State & signature handling**

   - State structure (op-stack compatible)
   - secp256k1 signing/verification (via Zabi)
   - ABI encoding for hashing

3. **P2P networking (basic)**

   - TCP transport (no libp2p yet)
   - Manual peer connection (IP + port)
   - Message serialization (JSON)

4. **Chain service**

   - Ethereum RPC client (JSON-RPC over HTTP)
   - Event listening (polling, no WebSocket yet)
   - Transaction submission (deposit, challenge, withdraw)

5. **Smart contracts**

   - Implement standard state channel contracts (NitroAdjudicator, ForceMove, MultiAssetHolder)
   - Deploy to local testnet (Hardhat)
   - TrivialApp (accepts all transitions) for testing

6. **Testing**
   - Unit tests for core types (State, Signature, Objective)
   - Integration test: 2 nodes open/close ledger channel
   - Test against local blockchain


### Event Surface Area

**Complete specification:** [docs/architecture/event-types.md](../docs/architecture/event-types.md)

The event store defines **20 events** across 4 domains as the sole source of truth for all state transitions:

| Domain              | Events | Description                                                  |
| ------------------- | ------ | ------------------------------------------------------------ |
| **Objective Lifecycle** | 5      | `objective-created`, `objective-approved`, `objective-rejected`, `objective-cranked`, `objective-completed` |
| **Channel State**       | 5      | `channel-created`, `state-signed`, `state-received`, `state-supported-updated`, `channel-finalized` |
| **Chain Bridge**        | 6      | `deposit-detected`, `allocation-updated`, `challenge-registered`, `challenge-cleared`, `channel-concluded`, `withdraw-completed` |
| **Messaging**           | 4      | `message-sent`, `message-received`, `message-acked`, `message-dropped` |

**Event ID Derivation:**
```
event_id = keccak256("ev1|" + event_name + "|" + canonical_json(payload))
```

- **Canonical JSON:** Sorted keys, no whitespace, UTF-8 encoding, deterministic serialization
- **Schemas:** JSON Schema 2020-12 definitions in `schemas/events/*.schema.json`
- **Zig Types:** Union type in `src/event_store/events.zig` with per-event validation
- **Tests:** 50+ tests with golden vectors in `testdata/events/`, >90% coverage

**Causal Rules:**
Each event specifies preconditions and postconditions enforcing state invariants:

- **state-signed:** `turn_num = prev.turn_num + 1`, `signer ∈ participants`, signature valid
- **state-supported-updated:** `supported_turn > prev_supported_turn`, `num_signatures ≥ threshold`
- **challenge-registered:** `turn_num_record ≥ supported_turn`, finalization timer started

**Versioning:**
Events include `event_version` field (currently `1`) for schema evolution. Forward-compatible migration via version-aware deserializers.

**Milestone:** Two Zig nodes can open a ledger channel, exchange signed states, close cooperatively.

**Success criteria:**

- [ ] Nodes exchange 100 state updates in <1 second
- [ ] 0% data loss (all messages delivered)
- [ ] Dispute resolution works (on-chain challenge/timeout)

---

### Phase 2: Game Framework (Months 4-6)

**Goal:** Event-sourcing + WASM derivation + PGlite integration

**Deliverables:**

1. **WASM runtime integration**

   - wasmer or wasmtime bindings
   - Load WASM modules
   - Call `reduce()` function
   - Memory limits & timeouts

2. **PGlite integration**

   - Embed PGlite (WASM build)
   - Initialize DB from schema
   - Execute SQL from WASM reducer
   - Serialize/deserialize DB state

3. **Event store (durable)**

   - Replace in-memory store with RocksDB
   - Append-only event log per objective/channel
   - Snapshot optimization (store DB state periodically)
   - Event replay for recovery

4. **Message log encoding**

   - Encode game messages in `State.AppData`
   - Validate message structure (well-formed JSON)
   - Derive DB state from message log
   - Cache derived state (invalidate on new message)

5. **Sample game: Rock-Paper-Scissors**

   - WASM reducer in Rust/Zig
   - Commit-reveal scheme (hash commitments)
   - Payout based on outcome
   - Test via CLI

6. **Smart contract: MessageLogApp**
   - Validates message format (not full derivation)
   - Checks turn-taking
   - Checks message appended (not rewritten)
   - Deploy to testnet

**Milestone:** Two players can play Rock-Paper-Scissors via state channel, with WASM-derived winner determination.

**Success criteria:**

- [ ] RPS game completes in <5 seconds (including reveals)
- [ ] Message log < 1KB for full game
- [ ] Derived state matches both players' local computation
- [ ] Cheating attempt detected (invalid move rejected)

---

### Phase 3: Hub Infrastructure (Months 7-9)

**Goal:** Virtual channels + hub-based matchmaking

**Deliverables:**

1. **VirtualFund/VirtualDefund objectives**

   - 3-party protocol implementation
   - Guarantee management in ledger channels

2. **Consensus channel (ledger updates)**

   - Leader/follower proposal system
   - Sign ledger state updates

3. **Hub service**

   - HTTP API for match requests
   - Matchmaking queue (pair compatible players)
   - Virtual channel coordination
   - Fee collection logic

4. **Hub registry (on-chain)**

   - Solidity contract for hub listing
   - Reputation tracking
   - Hub discovery via registry

5. **libp2p integration**

   - Replace TCP with libp2p (zen-eth/zig-libp2p)
   - Peer discovery (may need forking for maturity)
   - NAT traversal

6. **Performance optimization**
   - Parallel message processing (where safe)
   - Connection pooling
   - Message batching
   - DB query optimization (indexes)

**Milestone:** Hub facilitates 100 concurrent virtual channels between players, with <100ms setup time.

**Success criteria:**

- [ ] Virtual channel setup: <100ms
- [ ] Hub uptime: >99.9%
- [ ] Hub can handle 1000+ concurrent channels
- [ ] Fee collection works (hub earns revenue)

---

### Phase 4: Production Game (Months 10-12)

**Goal:** Viral D&D-style game on mainnet

**Deliverables:**

1. **Game design**

   - Core gameplay loop (hybrid combat/exploration)
   - Progression system (XP, loot, character builds)
   - Match duration: 30-60 minutes
   - Spectator mode (replay message log)

2. **WASM game logic**

   - Complex reducer (unit movement, combat, fog of war)
   - PostgreSQL schema (units, items, map, player stats)
   - Victory conditions
   - Anti-cheat (validate all moves)

3. **Frontend (web)**

   - SvelteKit or Next.js
   - 2D isometric view (or simple 3D)
   - Connect wallet (viem + wagmi)
   - Real-time state updates (WebSocket to node)

4. **Matchmaking UI**

   - Browse hubs
   - Create match request (stake amount)
   - Wait for opponent
   - Enter game

5. **Deployment**

   - Deploy contracts to Ethereum mainnet + L2s
   - Run hub infrastructure (AWS/GCP with autoscaling)
   - Monitor/alerting (Prometheus + Grafana)
   - Analytics (user behavior, match outcomes)

6. **Security audit**
   - Smart contract audit (external firm)
   - WASM reducer review
   - P2P protocol analysis
   - Economic attack vectors

**Milestone:** 1000 players play the game on mainnet, with <1% dispute rate and positive user feedback.

**Success criteria:**

- [ ] 1K+ monthly active users
- [ ] <1% of games result in on-chain dispute
- [ ] No loss of funds bugs
- [ ] Avg game latency <100ms
- [ ] Viral coefficient >1.0 (users invite friends)

---

### Phase 5: Developer Platform (Months 13-15)

**Goal:** Enable external developers to build games

**Deliverables:**

1. **SDK/Framework**

   - Zig library for state channel games
   - Rust library for WASM reducers
   - Boilerplate templates (chess, poker, racing)
   - Code-gen for DB schema → reducer stubs

2. **Documentation**

   - Architecture guide
   - Protocol tutorial
   - WASM reducer API reference
   - Example games (annotated source)

3. **Developer tools**

   - Local testnet setup (one command)
   - Debugger (step through message log)
   - Profiler (WASM execution time per message)
   - Validator (check reducer determinism)

4. **Hub operator guide**

   - Setup instructions
   - Economic model calculator
   - Monitoring playbook
   - Troubleshooting

5. **App store / registry**
   - On-chain registry of games
   - Frontend to browse/launch games
   - Reputation system (user ratings)

**Milestone:** 10 external developers deploy games, generating 10K+ matches/month.

**Success criteria:**

- [ ] 10+ games deployed by external devs
- [ ] Documentation rated 8+/10 by developers
- [ ] SDK reduces time-to-first-game from weeks → days
- [ ] 5+ independent hubs operating

---

## 9. TECHNICAL DECISIONS & RATIONALE

### Why Zig Over Go?

**Go-nitro uses Go. Why switch to Zig?**

1. **WASM generation**

   - **Zig:** 10-100x smaller WASM (no runtime, no GC)
   - **Go:** 2-10MB WASM (includes goroutine scheduler, GC)
   - **Impact:** Game reducers must be small for fast loading

2. **Performance**

   - **Zig:** No GC pauses (predictable latency)
   - **Go:** GC can cause 10-100ms pauses
   - **Impact:** Games need <10ms message processing

3. **Memory control**

   - **Zig:** Explicit allocators (arena for temp data, GPA for long-lived)
   - **Go:** Hidden allocation (hard to optimize)
   - **Impact:** Embedded systems (e.g., mobile nodes) need tight memory

4. **C interop**

   - **Zig:** Seamless `@cImport()` (no CGO overhead)
   - **Go:** CGO is slow (10x overhead per call)
   - **Impact:** PGlite, secp256k1, libp2p all use C libraries

5. **Comptime**
   - **Zig:** Zero-cost abstractions via comptime
   - **Go:** Runtime reflection or code-gen
   - **Impact:** Type-safe serialization without runtime cost

**Trade-offs:**

- ❌ Zig ecosystem smaller (fewer libraries)
- ❌ Zig compiler changes frequently (pre-1.0)
- ❌ Manual memory management (more bugs possible)
- ✅ But: Worth it for performance + WASM size

### Why Event Sourcing?

**Traditional implementations store state snapshots. Why use events?**

1. **Audit trail**

   - **Snapshots:** Can't explain how state was reached
   - **Events:** Full history preserved
   - **Impact:** Debugging bugs, proving fairness

2. **Flexibility**

   - **Snapshots:** Changing logic requires state migration
   - **Events:** Replay with new derivation function
   - **Impact:** Game updates don't break old channels

3. **Compact representation**

   - **Snapshots:** State grows with game complexity (O(entities))
   - **Events:** Log grows with actions taken (O(turns))
   - **Impact:** 1000-turn chess game: 50KB events vs 384 bytes snapshot
     - (But chess is special - simple state. Complex games favor events)

4. **Natural for games**
   - Games are already event-driven (player actions)
   - Message log mirrors gameplay
   - Easy to replay for spectators

**Trade-offs:**

- ❌ Derivation cost (must replay events)
- ✅ But: Cache derived state, only re-derive on new message
- ❌ Doesn't scale forever (long-running channels)
- ✅ But: Games are ephemeral (30 min - 3 hours)

### Why PGlite?

**Why PostgreSQL for game state?**

1. **Expressiveness**

   - SQL is powerful for relational data (units, items, relationships)
   - Developers know SQL
   - Complex queries (range attacks, fog of war) easy

2. **Full-featured**

   - PGlite is full PostgreSQL (not a subset)
   - Indexes, triggers, transactions all work
   - No "gotchas" vs production Postgres

3. **Embedded**
   - No separate process (no IPC overhead)
   - WASM build (runs in-process)
   - Small (~3MB bundle)

**Alternatives considered:**

- **SQLite:** Lighter, but less powerful (no JSONB, limited indexes)
- **Custom structs:** Fastest, but least expressive
- **Decision:** Start with PGlite, optimize later if needed

**Trade-offs:**

- ❌ Overhead vs custom structs (10-100x slower)
- ✅ But: <10ms per message is acceptable
- ❌ WASM PGlite immature (may hit bugs)
- ✅ But: Can fall back to native PostgreSQL

### Why Transparent Derivation (No ZK Proofs)?

**User said:** "We don't need to prove anything, anyone can derive the game state themselves."

**Rationale:**

1. **Simplicity**

   - No ZK circuit development (months of work)
   - No proof generation (seconds per proof)
   - No verifier gas costs ($10-100 per proof)

2. **Transparency**

   - Message log is public (after channel closes)
   - Spectators can replay to verify fairness
   - Disputes resolved by inspection (not cryptography)

3. **Performance**

   - WASM execution: <10ms per message
   - ZK proof generation: seconds per game state
   - **1000x faster**

4. **Good enough for games**
   - Games are low-stakes (<$1000 wagers typical)
   - Both players see all moves (hard to cheat)
   - Disputes rare (players want to finish game)

**When ZK would be needed:**

- High-stakes poker (hide cards until end)
- Competitive e-sports (millions in prizes)
- Regulatory compliance (provable fairness)

**Decision:** Start transparent, add ZK option in Phase 5 if demand exists.

---

## 10. SECURITY CONSIDERATIONS

### Threat Model

**Adversaries:**

1. **Malicious player** - Tries to cheat (invalid moves, double-spend)
2. **Malicious hub** - Steals funds, censors matches
3. **Network attacker** - MitM, DoS, eclipse attacks
4. **Smart contract exploit** - Reentrancy, overflow, logic bugs

**Assets to protect:**

1. **Funds** - ETH/tokens locked in channels
2. **Game integrity** - Fair outcomes
3. **Privacy** - Game states hidden during play
4. **Availability** - Players can always exit

### Attack Vectors & Mitigations

**A1: Invalid Move**

- **Attack:** Alice sends `move_unit` to impossible position
- **Mitigation:** Bob's node runs WASM reducer, detects illegal move, rejects state
- **Fallback:** If Bob signed invalid state, he can dispute on-chain (show previous valid state)

**A2: Message Rewriting**

- **Attack:** Alice tries to remove previous messages from log
- **Mitigation:** State signatures commit to full message log (hash includes appData)
- **Detection:** Bob sees turnNum increased but appData shorter → reject

**A3: Double-Spend (Two Final States)**

- **Attack:** Alice signs two different final states (one with Bob, one on-chain)
- **Mitigation:** Bob immediately submits his final state on-chain if dispute
- **Resolution:** On-chain contract accepts highest turnNum with valid signatures

**A4: Hub Steals Funds**

- **Attack:** Hub tries to claim virtual channel funds without proper close
- **Mitigation:** Virtual channel guarantees are locked in ledger channels
- **Protection:** Alice/Bob can challenge hub on-chain with signed virtual state

**A5: Hub Censorship**

- **Attack:** Hub refuses to facilitate virtual channel close
- **Mitigation:** Alice/Bob can cooperate to close ledger channels (kick out hub)
- **Escape hatch:** Direct ledger channel close returns all funds

**A6: Griefing (Forced On-Chain Dispute)**

- **Attack:** Bob refuses to sign final state, forcing Alice to challenge on-chain
- **Mitigation:** Challenge period (e.g., 24 hours) allows Bob to respond
- **Cost:** Alice pays gas (~$10-40), but wins funds
- **Deterrent:** Bob's reputation damaged (future players avoid)

**A7: Eclipse Attack (P2P)**

- **Attack:** Attacker isolates Alice's node (block messages from Bob)
- **Mitigation:** Alice detects no response from Bob within timeout
- **Fallback:** Alice initiates on-chain challenge
- **Future:** Multi-path routing (messages via multiple hubs)

**A8: Smart Contract Bugs**

- **Risk:** Reentrancy, overflow, logic errors
- **Mitigation:** Use audited state channel contracts (minimal modifications)
- **Verification:** External audit before mainnet deployment
- **Monitoring:** Watch for unexpected on-chain activity

**A9: WASM Reducer Non-Determinism**

- **Attack:** Reducer produces different results for same inputs
- **Mitigation:** Sandbox (no system time, no random, no I/O)
- **Testing:** Fuzz testing (run reducer 1000x, check consistency)
- **Detection:** If Alice and Bob disagree on state, flag for investigation

**A10: DoS (Message Spam)**

- **Attack:** Malicious player floods counterparty with invalid messages
- **Mitigation:** Rate limiting (max 100 messages/second)
- **Backpressure:** Reject new messages if queue full
- **Banning:** Blacklist peer after N invalid messages

### Security Best Practices

1. **Validate everything**

   - Check signatures before processing
   - Validate state transitions (turnNum, appData append-only)
   - Run WASM reducer before signing

2. **Fail closed**

   - If validation fails, reject state
   - If counterparty misbehaves, halt channel
   - If uncertain, challenge on-chain

3. **Minimize trust**

   - Don't trust hub (funds secured by smart contract)
   - Don't trust counterparty (validate all moves)
   - Trust blockchain (canonical source of truth)

4. **Monitor & alert**

   - Watch for unexpected challenges
   - Alert if hub unresponsive
   - Track dispute rate (>5% indicates problem)

5. **Escape hatches**
   - Always allow unilateral on-chain exit
   - Timeout mechanism (if counterparty disappears)
   - Fund recovery (if all else fails)

---

## 11. PERFORMANCE TARGETS

### Latency

| Operation                        | Target | Notes                        |
| -------------------------------- | ------ | ---------------------------- |
| Local state update               | <1ms   | Sign + store event           |
| P2P message delivery             | <50ms  | LAN: <10ms, Internet: <100ms |
| WASM derivation (per message)    | <10ms  | Cached DB state              |
| Full game derivation (1000 msgs) | <5s    | Cold start (no cache)        |
| Virtual channel setup            | <100ms | 3-party coordination         |
| Ledger channel open              | ~15s   | 2 on-chain txs (block time)  |

### Throughput

| Metric                       | Target    | Notes                            |
| ---------------------------- | --------- | -------------------------------- |
| Messages per channel         | 1000+/sec | Limited by WASM execution        |
| Concurrent channels per node | 100+      | Memory bound (~10MB per channel) |
| Concurrent channels per hub  | 10,000+   | Hub is stateless for game play   |
| Matches per hub per hour     | 1000+     | Setup: 100ms, Play: 30 min       |

### Resource Usage

| Resource           | Per Channel | Per Node (100 channels)       |
| ------------------ | ----------- | ----------------------------- |
| Memory             | 10 MB       | 1 GB                          |
| Disk (events)      | 1 MB/hour   | 100 MB/hour                   |
| CPU (idle)         | <1%         | <10%                          |
| CPU (active game)  | 10-50%      | N/A (channels not concurrent) |
| Network (gameplay) | 10 KB/s     | 1 MB/s                        |

### Scalability

**Node limits:**

- 1000 channels per node (10 GB RAM)
- 10 GB/day event storage (compressed)
- 100 Mbps network (100+ concurrent games)

**Hub limits:**

- 100,000 registered players
- 10,000 concurrent matches
- 1M matches/month

**Global network:**

- 100 hubs
- 10M players
- 100M matches/month

---

## 12. OPEN QUESTIONS

1. **PGlite maturity:** If PGlite WASM has bugs, do we:

   - Fork and fix?
   - Fall back to native PostgreSQL (via pg.zig)?
   - Build custom in-memory DB?

2. **libp2p or custom:** zen-eth/zig-libp2p is pre-release. Do we:

   - Fork and stabilize?
   - Wait for maturity (delay Phase 3)?
   - Build custom P2P (simpler but less features)?

3. **Message encoding:** JSON (readable) vs MessagePack (compact). Decision:

   - Start JSON (easier debugging)
   - Switch to MessagePack if size becomes issue

4. **Snapshot frequency:** How often to snapshot DB state?

   - Every 100 messages? (balance replay cost vs storage)
   - Adaptive (snapshot when derivation >1s)?

5. **Hub economics:** What fee structure works?

   - Percentage (2-5%)?
   - Fixed per game ($0.10)?
   - Subscription ($10/month unlimited)?

6. **Multi-hub routing:** Phase 5 feature or drop?

   - Adds complexity (path finding, multi-party protocols)
   - Benefit unclear (most players connect to 1 hub)

7. **Mobile support:** Can Zig node run on iOS/Android?

   - Zig compiles to ARM
   - But: App store restrictions on background processes
   - Alternative: Thin client (node runs on server)

8. **Game spectating:** How to stream game state to spectators?

   - WebSocket push (message log updates)?
   - HTTP poll (query derived state)?
   - P2P (spectators join gossip network)?

9. **Anti-cheat:** What if reducer has bugs (allows illegal moves)?

   - Version WASM (players reject old versions)?
   - On-chain governance (vote to deprecate buggy versions)?
   - Bug bounty program?

10. **Mainnet or L2 first:** Deploy to:
    - Ethereum mainnet (expensive but maximum security)?
    - Arbitrum/Optimism (cheaper, good UX)?
    - Both (multi-chain from day 1)?

---

## 13. REFERENCES & PRIOR ART

### State Channels

- **Nitro Protocol:** https://docs.statechannels.org/
  - State channel protocol specification
  - Objective pattern, consensus channels, virtual funding
- **Lightning Network:** https://lightning.network/
  - Payment channels, routing, hub topology
  - Differences: Payments vs games, HTLC vs state channels
- **Raiden Network:** https://raiden.network/
  - Ethereum payment channels
  - Similar virtual channel concept

### Event Sourcing

- **Martin Fowler - Event Sourcing:** https://martinfowler.com/eaaDev/EventSourcing.html
- **CQRS pattern:** https://martinfowler.com/bliki/CQRS.html
- **Kafka / Event streaming:** https://kafka.apache.org/

### WASM & Determinism

- **Zig WASM target:** https://ziglang.org/documentation/master/#WebAssembly
- **wasmer / wasmtime:** WASM runtimes
- **Deterministic execution:** Critical for consensus
  - No syscalls (time, random, I/O)
  - Sandbox enforced

### PostgreSQL Embedded

- **PGlite:** https://pglite.dev/
  - PostgreSQL compiled to WASM
  - Runs in browser or Node.js
- **pg.zig:** https://github.com/karlseguin/pg.zig
  - Native Zig PostgreSQL client

### Zig Libraries

- **Zabi:** https://github.com/Raiden1411/zabi
  - Ethereum ABI encoding, secp256k1, Keccak256
- **http.zig:** https://github.com/karlseguin/http.zig
  - High-performance HTTP server
- **zig-libp2p:** https://github.com/zen-eth/zig-libp2p
  - libp2p (pre-release, Ethereum-focused)

### Smart Contracts

- **Nitro Adjudicator:** `/packages/nitro-protocol/contracts/NitroAdjudicator.sol`
- **ForceMove:** Force move games pattern
- **Virtual channels paper:** https://magmo.com/force-move-games.pdf

### Games on Blockchain

- **Dark Forest:** zkSNARK-based strategy game (Ethereum)
- **Axie Infinity:** Play-to-earn (Ethereum sidechain)
- **Loot:** On-chain game items (Ethereum)
- **Influence:** Space strategy (StarkNet)

---

**END OF DOCUMENT**
