# Channels

**Event-sourced state channels in Zig** - Instant, verifiable, ephemeral applications inheriting Ethereum security without blockchain cost/latency.

## What This Is

State channel infrastructure for high-throughput applications (games, collaborative sessions, interactive media). Not for DeFi or permanent storage.

**Target performance:** <100ms finality, zero marginal cost for off-chain updates, provable fairness via transparent state derivation.

## Core Innovation: Event Sourcing

**Message logs as source of truth** (not snapshots).

Traditional channels store opaque state snapshots. This system stores ordered message logs, derives state deterministically via WASM execution. Anyone can replay message log to verify correctness - no crypto proofs needed.

**Benefits:**
- Complete audit trail (time-travel debugging)
- Transparent state derivation (verifiable by anyone)
- Compact on-chain representation (logs smaller than full state)
- Rich querying via embedded PostgreSQL

## Technology Stack

- **Language:** Zig 0.15+ (no GC, explicit control, small WASM output)
- **Storage:** RocksDB (append-optimized LSM) + PostgreSQL (PGlite WASM for derived state)
- **Network:** TCP → libp2p (production)
- **Blockchain:** Ethereum/L2 (reuses go-nitro contracts)
- **WASM:** wasmer runtime (deterministic, sandboxed execution)
- **Serialization:** JSON → MessagePack (events), ABI-packed (state)

## Development Approach

**Prompt-driven, phased implementation:**
- 12 phases over 12-18 months
- Each phase independently valuable/testable
- Doc→Test→Code methodology (ADRs → specs → tests → implementation)
- Prompts versioned in `.claude/commands/` - discover issues → update prompts → regenerate code → rebase

**Current phase:** Phase 1 (Event Sourcing Infrastructure)

**Phases:**
1. Event sourcing foundation
2. Core state & signatures
3. DirectFund protocol
4. Durable persistence (RocksDB)
5. DirectDefund protocol
6. P2P networking
7. Chain service (Ethereum)
8. Consensus channels
9. Virtual fund/defund
10. Payment channels
11. WASM state derivation
12. Production hardening

## Reference Implementation

Based on **go-nitro** (Magmo/Statechannels team). Preserves Objective/Crank pattern, WaitingFor enumeration, multi-layered architecture. Improves with event sourcing, Zig performance, tagged unions, binary serialization.

## Key Documentation

- `docs/prd.md` - Complete product requirements
- `docs/phase-template.md` - Structure for all phases
- `docs/adrs/` - Architectural decision records
- `.claude/commands/0_plan_phases.md` - Master planning prompt
- `.claude/commands/N_phase_*.md` - Individual phase prompts

## Getting Started

Install dependencies:
```bash
bun install
```

Run:
```bash
bun run index.ts
```

Build Zig:
```bash
zig build
```

Test Zig:
```bash
zig build test
```

---

*This project uses Bun (fast all-in-one JavaScript runtime) and Zig for systems programming.*
