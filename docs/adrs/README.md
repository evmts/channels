# Architectural Decision Records (ADR) Index

**Project:** Event-Sourced State Channels in Zig
**ADR Methodology:** Documented in [0000-adrs.md](./0000-adrs.md)
**Total ADRs Planned:** 17
**Status:** Planning

---

## ADR Overview

| # | Title | Phase | Status | Date |
|---|-------|-------|--------|------|
| [0000](./0000-adrs.md) | ADR Methodology | Meta | Approved | 2025-11-07 |
| **0001** | Event Sourcing Strategy | P1 | Planned | TBD |
| **0002** | Event Serialization Format | P1 | Planned | TBD |
| **0003** | In-Memory Event Log for Phase 1 | P1 | Planned | TBD |
| **0004** | Signature Scheme (secp256k1) | P2 | Planned | TBD |
| **0005** | State Encoding (ABI-compatible) | P2 | Planned | TBD |
| **0006** | Objective/Crank Pattern | P3 | Planned | TBD |
| **0007** | Side Effect Dispatch | P3 | Planned | TBD |
| **0008** | Event Store Backend (RocksDB) | P4 | Planned | TBD |
| **0009** | Snapshot Frequency | P4 | Planned | TBD |
| **0010** | P2P Transport Protocol | P6 | Planned | TBD |
| **0011** | Message Codec | P6 | Planned | TBD |
| **0012** | Chain Event Confirmation Depth | P7 | Planned | TBD |
| **0013** | Consensus Proposal Ordering | P8 | Planned | TBD |
| **0014** | Guarantee Locking Semantics | P8 | Planned | TBD |
| **0015** | Multi-hop Routing Strategy | P9 | Planned | TBD |
| **0016** | WASM Runtime Selection | P11 | Planned | TBD |
| **0017** | Determinism Enforcement | P11 | Planned | TBD |

---

## Phase 1: Event Sourcing Foundation

### **ADR-0001: Event Sourcing Strategy**

**Decision:** Use event sourcing as primary state management strategy

**Context:**
- Need to store state channel data durably
- Options: Snapshots (traditional), Event sourcing, Hybrid

**Options:**
- **A) Snapshots:** Store latest state only (traditional approach)
- **B) Event Sourcing:** Store events, derive state
- **C) Hybrid:** Snapshots + recent events

**Decision:** B (Event Sourcing) with snapshots as optimization

**Rationale:**
- ✅ Complete audit trail for debugging
- ✅ Time-travel to any historical state
- ✅ Transparent state derivation (verifiable)
- ✅ Natural fit for state machines
- ⚠️ Reconstruction cost (mitigated by caching/snapshots)

**Consequences:**
- Event log is source of truth, not snapshots
- All state changes modeled as events
- Reconstruction must be deterministic
- Snapshots are optimization, not requirement

**Status:** Planned (Phase 1, Week 1)

---

### **ADR-0002: Event Serialization Format**

**Decision:** Use JSON for Phase 1, reconsider binary formats in Phase 4

**Context:**
- Need to serialize events to disk/memory
- Options: JSON, MessagePack, Custom binary, Cap'n Proto

**Options:**
- **A) JSON:** Human-readable, debuggable
- **B) MessagePack:** Binary, compact
- **C) Custom Binary:** Maximum efficiency
- **D) Cap'n Proto:** Zero-copy deserialization

**Decision:** A (JSON) initially, reconsider at Phase 4

**Rationale:**
- ✅ Easy debugging (cat event log and read)
- ✅ Zig has good JSON support (`std.json`)
- ✅ Schema evolution easier
- ⚠️ Larger than binary (acceptable for Phase 1)
- ⚠️ Slower parsing (acceptable for <10K events)

**Decision Point:** If logs >100MB or parsing >1s, switch to MessagePack

**Status:** Planned (Phase 1, Week 1)

---

### **ADR-0003: In-Memory Event Log for Phase 1**

**Decision:** Use in-memory ArrayList for Phase 1, migrate to RocksDB in Phase 4

**Context:**
- Where to store events in Phase 1?
- Options: In-memory, RocksDB, SQLite

**Options:**
- **A) In-memory ArrayList:** Simple, fast
- **B) RocksDB:** Durable from start
- **C) SQLite:** Queryable

**Decision:** A (In-memory) for Phase 1

**Rationale:**
- ✅ Simplest implementation for validation
- ✅ Fast development iteration
- ✅ Easier testing (no disk I/O)
- ✅ Phase 1 focus: prove event sourcing works
- ⚠️ Data lost on crash (acceptable for testing)

**Migration:** Phase 4 replaces with RocksDB (same interface)

**Status:** Planned (Phase 1, Week 1)

---

## Phase 2: Core State & Signatures

### **ADR-0004: Signature Scheme (secp256k1)**

**Decision:** Use secp256k1 with recoverable signatures (Ethereum standard)

**Context:**
- Need to sign state for agreement
- Must be Ethereum-compatible for on-chain verification

**Options:**
- **A) secp256k1 recoverable:** Ethereum standard, address recovery
- **B) ed25519:** Faster, requires explicit pubkeys
- **C) BLS:** Aggregatable, not Ethereum-compatible

**Decision:** A (secp256k1 recoverable)

**Rationale:**
- ✅ Ethereum compatibility (on-chain verification)
- ✅ Address recovery (compact signatures)
- ✅ Proven security, widespread use
- ✅ Hardware wallet support
- ⚠️ Slower than ed25519 (acceptable: <5ms)

**Implementation:** Use zabi library for secp256k1 + Keccak256

**Format:** 65 bytes (r=32, s=32, v=1)

**Status:** Planned (Phase 2, Week 1)

---

### **ADR-0005: State Encoding (ABI-compatible)**

**Decision:** Use Ethereum ABI packed encoding

**Context:**
- Need deterministic encoding for hashing
- Must match Solidity `abi.encode()` for on-chain validation

**Options:**
- **A) Ethereum ABI (packed):** Contract-compatible
- **B) JSON:** Human-readable, non-deterministic
- **C) Custom binary:** Efficient, incompatible
- **D) RLP:** Ethereum alternative

**Decision:** A (Ethereum ABI packed encoding)

**Rationale:**
- ✅ Smart contracts use `abi.encode()` - must match
- ✅ Deterministic (same state → same bytes)
- ✅ State channel compatible
- ✅ Well-specified (Solidity ABI spec)
- ⚠️ Complex implementation

**Validation:** Cross-test with state channel test vectors

**Status:** Planned (Phase 2, Week 1)

---

## Phase 3: DirectFund Protocol

### **ADR-0006: Objective/Crank Pattern**

**Decision:** Use flowchart-based state machines (Objective/Crank pattern)

**Context:**
- Need protocol state machine design
- Options: Explicit FSM, Flowchart (proven pattern), Actor model

**Options:**
- **A) Explicit FSM:** Defined states/transitions
- **B) Flowchart:** Implicit states, pure Crank function
- **C) Actor model:** Message passing

**Decision:** B (Flowchart/Crank pattern - proven in state channel implementations)

**Rationale:**
- ✅ Flexible, handles complex flows
- ✅ Restartable (pure functions)
- ✅ Proven in production
- ✅ WaitingFor computed from state
- ⚠️ Less explicit than FSM (mitigated by docs)

**Pattern:**
```zig
pub fn crank(objective: Objective, event: Event) !CrankResult {
    // Pure function: (Objective, Event) → (Objective', SideEffects, WaitingFor)
}
```

**Status:** Planned (Phase 3, Week 1)

---

### **ADR-0007: Side Effect Dispatch**

**Decision:** Objectives return side effects, Engine dispatches

**Context:**
- How do objectives execute effects (send messages, submit txs)?
- Options: Direct execution, Queue, Return for dispatch

**Options:**
- **A) Direct execution:** Objective calls P2P/Chain directly
- **B) Queue:** Objectives push to queue
- **C) Return for dispatch:** Pure objectives, Engine executes

**Decision:** C (Return side effects for Engine dispatch)

**Rationale:**
- ✅ Pure objectives (testable without mocks)
- ✅ Separation of concerns
- ✅ Engine controls ordering/execution
- ✅ Matches proven patterns

**Side Effects:**
```zig
pub const SideEffect = union(enum) {
    send_message: Message,
    submit_tx: Transaction,
    trigger_crank: ObjectiveId,
};
```

**Status:** Planned (Phase 3, Week 1)

---

## Phase 4: Durable Persistence

### **ADR-0008: Event Store Backend (RocksDB)**

**Decision:** Use RocksDB for durable event storage

**Context:**
- Need persistent event log (Phase 1 was in-memory)
- Options: RocksDB, SQLite, Custom

**Options:**
- **A) RocksDB:** Embedded, LSM tree, fast writes
- **B) SQLite:** Embedded, queryable, B-tree
- **C) Custom:** Maximum control

**Decision:** A (RocksDB)

**Rationale:**
- ✅ Embedded (no separate server)
- ✅ LSM tree optimized for append-only
- ✅ Proven (used widely)
- ✅ Zig bindings available
- ⚠️ More complex than SQLite (acceptable)

**Trade-offs:**
- RocksDB: Faster writes, no queries
- SQLite: Slower writes, queryable

**Append-only workload favors RocksDB**

**Status:** Planned (Phase 4, Week 1)

---

### **ADR-0009: Snapshot Frequency**

**Decision:** Snapshot every 1000 events initially

**Context:**
- When to create snapshots for fast startup?
- Options: Every N events, Adaptive, On objective completion

**Options:**
- **A) Every N events:** Simple, predictable
- **B) Adaptive (time-based):** Optimize when slow
- **C) On completion:** Natural boundaries

**Decision:** A (Every 1000 events)

**Rationale:**
- ✅ Simple implementation
- ✅ Predictable behavior
- ✅ Reasonable trade-off (1000 events ~100ms)
- Can adjust N based on profiling

**Future:** Consider adaptive if needed

**Status:** Planned (Phase 4, Week 1)

---

## Phase 6: P2P Networking

### **ADR-0010: P2P Transport Protocol**

**Decision:** Use raw TCP for Phase 6, defer libp2p to Phase 12

**Context:**
- How do nodes communicate?
- Options: TCP, libp2p, QUIC

**Options:**
- **A) Raw TCP:** Simple, low-level
- **B) libp2p:** Full-featured, NAT traversal
- **C) QUIC:** Modern, faster

**Decision:** A (TCP) initially

**Rationale:**
- ✅ Simplest implementation
- ✅ Defer NAT traversal complexity
- ✅ Zig std.net support
- ⚠️ No NAT traversal (use relay/VPN for Phase 6)

**Migration:** Upgrade to libp2p in Phase 12 for production

**Status:** Planned (Phase 6, Week 1)

---

### **ADR-0011: Message Codec**

**Decision:** Use MessagePack for message serialization

**Context:**
- How to serialize P2P messages?
- Options: JSON, MessagePack, Protobuf

**Options:**
- **A) JSON:** Human-readable
- **B) MessagePack:** Compact, fast
- **C) Protobuf:** Strongly typed, verbose

**Decision:** B (MessagePack)

**Rationale:**
- ✅ Compact (smaller than JSON)
- ✅ Fast (faster than JSON)
- ✅ Zig library available
- ✅ Schema-less (flexible)

**Trade-off:** Less debuggable than JSON (acceptable)

**Status:** Planned (Phase 6, Week 1)

---

## Phase 7: Chain Service

### **ADR-0012: Chain Event Confirmation Depth**

**Decision:** Require 12 block confirmations before trusting events

**Context:**
- When to trust on-chain events (deposits, conclusions)?
- Options: 0 blocks, 1 block, 12 blocks

**Options:**
- **A) 0 blocks:** Immediate, risky
- **B) 1 block:** Fast, some reorg risk
- **C) 12 blocks:** Safe, industry standard

**Decision:** C (12 blocks)

**Rationale:**
- ✅ Reorg safety (12 blocks rarely reorg)
- ✅ Matches industry standard (exchanges use 12+)
- ✅ Prevents double-spend attacks
- ⚠️ Slower (12 blocks ~2.5 minutes on Ethereum)

**Configurable:** Allow override for testing (0 blocks on local chains)

**Status:** Planned (Phase 7, Week 1)

---

## Phase 8: Consensus Channels

### **ADR-0013: Consensus Proposal Ordering**

**Decision:** Use proposal queue with sequence numbers

**Context:**
- How to order concurrent ledger channel proposals?
- Options: Trust leader, Sequence numbers, Queue+sort

**Options:**
- **A) Trust leader:** Leader determines order
- **B) Sequence numbers only:** Detect out-of-order
- **C) Queue + sequence:** Robust, handle OOO

**Decision:** C (Queue with sequence numbers)

**Rationale:**
- ✅ Robust to network reordering
- ✅ Handles out-of-order delivery
- ✅ Sequence numbers detect issues
- ⚠️ More complex (acceptable)

**Note:** State channels use turn numbers for sequencing

**Status:** Planned (Phase 8, Week 1)

---

### **ADR-0014: Guarantee Locking Semantics**

**Decision:** Lock guarantees at postfund (after ledger funded)

**Context:**
- When to lock guarantees for virtual channels?
- Options: At prefund, At postfund, First proposal

**Options:**
- **A) At prefund:** Early locking
- **B) At postfund:** After funded
- **C) First proposal:** On-demand

**Decision:** B (At postfund)

**Rationale:**
- ✅ Standard behavior
- ✅ Ledger channel funded (guarantees backed by real assets)
- ✅ Clear semantics

**Consequence:** Virtual funding waits for ledger postfund

**Status:** Planned (Phase 8, Week 1)

---

## Phase 9: VirtualFund/Defund

### **ADR-0015: Multi-hop Routing Strategy**

**Decision:** Use source routing for Phase 9, defer complex routing

**Context:**
- How to route through multiple hubs?
- Options: Source routing, Onion routing, Path finding

**Options:**
- **A) Source routing:** Explicit path specified
- **B) Onion routing:** Privacy-preserving
- **C) Path finding:** Automatic discovery

**Decision:** A (Source routing)

**Rationale:**
- ✅ Simplest for Phase 9
- ✅ Explicit control
- ✅ Works for hub topology
- ⚠️ Defer complex routing to Phase 12

**Example:** Alice specifies path: Alice → Hub1 → Hub2 → Bob

**Status:** Planned (Phase 9, Week 1)

---

## Phase 11: WASM Derivation

### **ADR-0016: WASM Runtime Selection**

**Decision:** Use wasmer for WASM execution

**Context:**
- Which WASM runtime to embed?
- Options: wasmer, wasmtime, custom

**Options:**
- **A) wasmer:** Mature, C API, Zig bindings
- **B) wasmtime:** Rust-native, fewer bindings
- **C) Custom:** Maximum control

**Decision:** A (wasmer)

**Rationale:**
- ✅ Better C API for Zig interop
- ✅ Zig bindings available
- ✅ Proven in production
- ✅ JIT compilation available

**Status:** Planned (Phase 11, Week 1)

---

### **ADR-0017: Determinism Enforcement**

**Decision:** Sandbox WASM execution (no time/random/IO)

**Context:**
- How to ensure reducers are deterministic?
- Options: Sandbox, WASI subset, Pure Zig only

**Options:**
- **A) Sandbox:** Disable time/random/IO
- **B) WASI subset:** Allow some syscalls
- **C) Pure Zig:** No WASM, compile Zig reducers

**Decision:** A (Sandbox - disable non-deterministic operations)

**Rationale:**
- ✅ Strongest guarantee
- ✅ Provable determinism
- ✅ Prevents accidental violations
- ⚠️ More restrictive (acceptable for reducers)

**Enforcement:** WASM runtime configured to reject non-deterministic calls

**Status:** Planned (Phase 11, Week 1)

---

## ADR Methodology

All ADRs follow the structure defined in [0000-adrs.md](./0000-adrs.md):

1. **Title:** Short, descriptive
2. **Status:** Proposed / Accepted / Deprecated / Superseded
3. **Context:** Problem statement, constraints
4. **Decision:** Chosen option
5. **Consequences:** Trade-offs, implications
6. **Alternatives:** Other options considered

**ADR Lifecycle:**
- **Planned:** Identified, not yet written
- **Proposed:** Draft ADR under review
- **Accepted:** Approved, guiding implementation
- **Deprecated:** No longer valid
- **Superseded:** Replaced by newer ADR

---

## References

- **ADR Methodology:** [0000-adrs.md](./0000-adrs.md)
- **Phase Planning:** [.claude/commands/README.md](../../.claude/commands/README.md)
- **ADR Template:** [adr-template.md](../adr-template.md)

---

**Last Updated:** 2025-11-08
**ADR Count:** 17 planned (1 approved, 16 planned)
**Next:** Write ADRs 0001-0003 in Phase 1, Week 1
