# Architecture Documentation

Design documents describing the system architecture of the event-sourced state channels implementation.

---

## Overview

This directory contains detailed architecture specifications that complement the [PRD](../prd.md). While the PRD describes **what** we're building and **why**, these docs describe **how** the system is designed and **how** components interact.

**Relationship to Other Docs:**
- **[PRD](../prd.md)**: High-level requirements and system architecture (§5)
- **[ADRs](../adrs/)**: Architectural decisions with rationale and trade-offs
- **Phase docs**: Implementation plans that reference these architecture docs
- **Context**: [context.md](../context.md) provides prior art that informed these designs

---

## Documents

### Event Sourcing

**[event-types.md](event-types.md)** - Event Catalog (Phase 1+)
- **Purpose:** Complete event surface area for the system
- **Content:** 20 events across 4 domains (Objective Lifecycle, Channel State, Chain Bridge, Messaging)
- **Key Features:**
  - Event schemas with JSON examples
  - Causal rules and ordering constraints
  - ID derivation via keccak256
  - Canonical JSON serialization
  - Validation rules
  - Versioning strategy
- **Implementation:** Maps to `src/event_store/events.zig`
- **Testing:** Includes golden test vectors
- **Related ADRs:** [0001](../adrs/README.md) (event sourcing strategy), [0002](../adrs/README.md) (serialization), [0003](../adrs/README.md) (in-memory log)
- **Phase:** [Phase 1](./.claude/commands/1_phase_1_event_sourcing.md)

---

## Future Architecture Docs

As phases progress, additional architecture docs will be created:

### Planned (Phase 2+):

**state-channels.md** - State Channel Architecture
- Channel state structure
- Signature schemes (secp256k1)
- ABI encoding for on-chain compatibility
- State transitions and consensus rules
- Related: [Phase 2](../../.claude/commands/2_phase_core_state_and_signatures.md), ADR-0004, ADR-0005

**objective-crank.md** - Objective/Crank Pattern
- Objective state machines
- Crank execution model
- Side effect handling
- Protocol composition
- Related: [Phase 3](../../.claude/commands/3_phase_directfund_protocol.md), ADR-0006, ADR-0007

**persistence.md** - Durable Persistence Architecture
- RocksDB backend design
- Event log persistence
- Snapshot strategy
- Crash recovery protocol
- Related: [Phase 4](../../.claude/commands/4_phase_durable_persistence.md), ADR-0008, ADR-0009

**messaging.md** - P2P Messaging Architecture
- Transport layer (TCP)
- Message codec (MessagePack)
- Routing and delivery guarantees
- Connection management
- Related: [Phase 6](../../.claude/commands/6_phase_p2p_networking.md), ADR-0010, ADR-0011

**chain-integration.md** - Chain Service Architecture
- Ethereum RPC client
- Event listener design
- Confirmation depth handling
- Reorg handling
- Related: [Phase 7](../../.claude/commands/7_phase_chain_service.md), ADR-0012

**ledger-channels.md** - Consensus Channel Architecture
- Ledger channel design
- Leader/follower protocol
- Proposal ordering
- Guarantee locking
- Related: [Phase 8](../../.claude/commands/8_phase_consensus_channels.md), ADR-0013, ADR-0014

**virtual-channels.md** - Virtual Channel Architecture
- 3-party virtual channel protocol
- Multi-hop routing
- Intermediary guarantees
- Defunding coordination
- Related: [Phase 9](../../.claude/commands/9_phase_virtualfund_defund.md), ADR-0015

**wasm-derivation.md** - WASM Derivation Architecture
- WASM runtime selection
- Determinism enforcement
- PGlite integration
- State derivation engine
- Fault proof generation
- Related: [Phase 11](../../.claude/commands/11_phase_wasm_derivation.md), ADR-0016, ADR-0017

---

## Documentation Standards

Architecture docs follow these guidelines:

### Structure

Each architecture doc should include:

1. **Overview**: What this doc covers, why it exists
2. **Context**: Related ADRs, phases, PRD sections
3. **Design**: Core design with diagrams
4. **Component Specifications**: Detailed component descriptions
5. **Interactions**: How components interact (sequence diagrams helpful)
6. **Data Structures**: Key types, schemas, formats
7. **Algorithms**: Critical algorithms with pseudocode
8. **Trade-offs**: Design choices and their implications
9. **Implementation Notes**: Zig-specific considerations, gotchas
10. **Testing Strategy**: How to test this architecture
11. **References**: Links to code, tests, ADRs, related docs

### Cross-References

- **Link to ADRs**: Reference ADRs that justify design decisions
- **Link to PRD sections**: Map to requirements in [PRD](../prd.md)
- **Link to phases**: Reference phase docs that implement this architecture
- **Link to implementation**: Point to `src/` files that implement the design
- **Link to tests**: Point to test files that validate the design
- **Link to context**: Reference prior art from [context.md](../context.md)

### Diagrams

Use Mermaid for diagrams:
- Component diagrams for structure
- Sequence diagrams for interactions
- State diagrams for state machines
- Flow charts for algorithms

### Code Examples

Include Zig code snippets for:
- Key type definitions
- Critical algorithms
- Usage patterns
- Test examples

---

## Navigation

**For implementers:** Start with the architecture doc for your current phase, then read related ADRs

**For architects:** Read all architecture docs to understand complete system design

**For reviewers:** Use architecture docs to verify implementation matches design

**Quick links:**
- [PRD §5 System Architecture](../prd.md) - High-level architecture overview
- [ADR Index](../adrs/README.md) - All architectural decisions
- [Phase Index](../../.claude/commands/README.md) - Implementation timeline
- [Learning Paths](../LEARNING_PATHS.md) - Guided reading sequences

---

*Architecture docs created during phase implementation as part of [prompt-driven development](../../CLAUDE.md). Each phase adds/updates relevant architecture docs.*
