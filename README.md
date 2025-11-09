# Channels

**Event-sourced state channels in Zig** - Instant, verifiable, ephemeral applications inheriting Ethereum security without blockchain cost/latency.

## Planning

We always plan before implementing. Our plans should be concise and really easy to read and audit quickly. Concise, use bullets, don't use complete sentences if not necessary, and be ruthlessly straight forward.

Our plans should never include time estimates.

## What This Is

State channel infrastructure for high-throughput applications (games, collaborative sessions, interactive media). Not for DeFi or permanent storage.

**Target performance:** <100ms finality, zero marginal cost for off-chain updates, provable fairness via transparent state derivation.

## Use Cases

Event-sourced state channels excel for **bounded-duration, high-frequency interactions** between known parties.

### Full Onchain Games (FOCG)

- **Tactical RPGs/Strategy** - D&D-style combat, turn-based tactics, autobattlers (30-60 min matches, 100+ moves)
- **Real-time competitive** - Fighting games, racing, card battlers (<100ms latency, provably fair RNG)
- **Collaborative puzzle** - Escape rooms, co-op resource management (rich state, synchronous play)
- **High-skill competitions** - Chess/Go tournaments, poker (reputation on chain, verifiable match history)

### Frames (Farcaster Integration)

- **Quick-play games** - RPS, tic-tac-toe, word battles (30 sec - 5 min, single signature UX)
- **Social betting** - Prediction markets, "bet on this take" mini-markets (instant settlement, viral sharing)
- **Collaborative creation** - Shared drawing, music jams (full edit history, provable co-ownership)

### Token Mints (Novel Mechanisms)

- **Play-to-mint** - Complete game → mint NFT with embedded score/stats (gameplay = provenance)
- **Battle royale mints** - 100 players compete, placement determines trait rarity
- **Trait evolution** - NFT holders "train" tokens via channels (Pokemon-style stat gains, anti-cheat via WASM)
- **Collaborative worlds** - 1000 players build shared state, mint based on contribution metrics

### Autonomous Worlds / MUD Integration

- **Raid parties** - Persistent MUD world + ephemeral dungeon runs (30-60 min, loot written on close)
- **PvP arenas** - Ranked ladder on-chain, matches in channels (100+ matches/hour vs 10-20 pure on-chain)
- **Crafting sessions** - Complex crafting logic off-chain, verified items on-chain

### Prediction Markets & Betting

- **Live event betting** - Sports quarters, esports rounds (15-30 min windows, instant payout)
- **Micro-markets** - Sub-minute granularity, frequent updates (hub as market maker)

### Collaborative Work Sessions

- **Pair programming** - Shared editor, attributed edits, contributor stats on-chain
- **Design reviews** - Milestone-based payments triggered by channel events
- **Writing rooms** - Co-authoring with provable contribution → royalty split

**Why these work:** Known participants, bounded duration (mins-hours), high frequency (10-1000+ updates), instant finality, verifiable outcomes, privacy valuable.

**Anti-patterns:** DeFi (need composability), permanent storage, transactions with strangers, async/slow updates.

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
- **Blockchain:** Ethereum/L2 (op-stack compatible contracts)
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

## Implementation Approach

Built for **op-stack** L2s with WASM state derivation support. Follows state channel best practices: Objective/Crank pattern, WaitingFor enumeration, multi-layered architecture. Novel: event sourcing, Zig performance, tagged unions, binary serialization.

## Documentation Map

**New to the project?** Start here:

1. This README (you are here) - Overview and quick start
2. [docs/prd.md](docs/prd.md) - Product vision and complete requirements
3. [docs/LEARNING_PATHS.md](docs/LEARNING_PATHS.md) - Guided reading for different roles
4. [docs/context.md](docs/context.md) - Prior art (Nitro, Perun, Arbitrum, event sourcing patterns)

**Implementing a phase?** Read these:

- [.claude/commands/README.md](.claude/commands/README.md) - Phase roadmap and dependency graph
- [.claude/commands/N*phase*\*.md](.claude/commands/N_phase_*.md) - Your specific phase spec
- [docs/phase-template.md](docs/phase-template.md) - What each phase section means
- [docs/adrs/README.md](docs/adrs/README.md) - ADRs your phase creates/depends on
- [CLAUDE.md](CLAUDE.md) - Coding conventions and workflow

**Understanding architecture?** See:

- [docs/architecture/](docs/architecture/) - Design documents and component specs
- [docs/adrs/](docs/adrs/) - Architectural decisions with rationale
- [docs/prd.md](docs/prd.md) §5 - System architecture overview

**Writing tests?** Read:

- [CLAUDE.md](CLAUDE.md) - TDD approach and Zig conventions
- [docs/fuzz-tests.md](docs/fuzz-tests.md) - Zig fuzz testing guide (Linux/Docker)

**Working with AI?** Check:

- [CLAUDE.md](CLAUDE.md) - AI assistant instructions and prompt-driven methodology
- [.claude/commands/0_plan_phases.md](.claude/commands/0_plan_phases.md) - Planning approach
- [docs/phase-template.md](docs/phase-template.md) & [docs/adr-template.md](docs/adr-template.md) - Templates

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

Fuzz test (Linux/Docker only - see [fuzz testing guide](docs/fuzz-tests.md)):

```bash
zig build test --fuzz
```

---

_This project uses Bun (fast all-in-one JavaScript runtime) and Zig for systems programming._
