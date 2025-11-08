# Learning Paths

This guide provides curated reading sequences for different personas working with the event-sourced state channels project.

---

## For New Contributors

**Goal:** Understand what we're building and why

1. **[README.md](../README.md)** - Project overview, core innovation (event sourcing), 12-phase roadmap
2. **[docs/prd.md](prd.md) §1-3** - Executive summary, problem statement, solution overview
3. **[docs/context.md](context.md)** - Prior art: Why existing solutions (Nitro, Perun, Arbitrum, Optimism) shaped our approach
4. **[.claude/commands/README.md](../.claude/commands/README.md)** - Phase timeline, dependency graph, critical path
5. **[docs/adrs/0000-adrs.md](adrs/0000-adrs.md)** - How we document architectural decisions
6. **[CLAUDE.md](../CLAUDE.md)** - Development workflow, coding conventions, prompt-driven development

**Time:** 2-3 hours reading

**Outcome:** Can explain project vision, understand our methodology, ready to explore specific areas

---

## For Implementers (Starting Phase N)

**Goal:** Understand what to build and how to build it

### Before Any Phase:

1. **[CLAUDE.md](../CLAUDE.md)** - Zig conventions, TDD approach, error handling, test structure
2. **[docs/fuzz-tests.md](fuzz-tests.md)** - How to write and run fuzz tests in Zig 0.15+
3. **[docs/phase-template.md](phase-template.md)** - Structure of phase documents (objectives, architecture, validation gates)
4. **[docs/adr-template.md](adr-template.md)** - How to read/write architectural decision records

### For Your Specific Phase:

5. **`.claude/commands/N_phase_*.md`** - Your phase specification (read completely)
6. **[docs/prd.md](prd.md)** - Sections referenced by your phase (usually §4-7)
7. **[docs/adrs/README.md](adrs/README.md)** - ADRs created by your phase
8. **Individual ADR docs** - Read each ADR your phase creates/depends on
9. **[docs/architecture/](architecture/)** - Relevant architecture docs for your phase
10. **Prior phase docs** - Review phases your phase depends on

### Phase-Specific Paths:

**Phase 1 (Event Sourcing):**
- [.claude/commands/1_phase_1_event_sourcing.md](../.claude/commands/1_phase_1_event_sourcing.md)
- [.claude/commands/START_PHASE_1.md](../.claude/commands/START_PHASE_1.md) - Week-by-week execution guide
- [docs/prd.md](prd.md) §4.1 Event Sourcing, §4.2 Message Logs
- [docs/context.md](context.md) - Event Sourcing section (PGlite, ElectricSQL, Replicache, state channel patterns)
- [docs/architecture/event-types.md](architecture/event-types.md) - Complete event catalog you'll implement
- [docs/adrs/README.md](adrs/README.md) - ADR-0001 (strategy), ADR-0002 (serialization), ADR-0003 (in-memory)

**Phase 2 (State & Signatures):**
- [.claude/commands/2_phase_core_state_and_signatures.md](../.claude/commands/2_phase_core_state_and_signatures.md)
- [docs/prd.md](prd.md) §4.4 State Encoding, §7.3 State Structure
- [docs/context.md](context.md) - Nitro/Perun state channel patterns
- Phase 1 recap (event sourcing foundation)
- ADR-0004 (signature scheme), ADR-0005 (state encoding)

**Phase 3 (DirectFund Protocol):**
- [.claude/commands/3_phase_directfund_protocol.md](../.claude/commands/3_phase_directfund_protocol.md)
- [docs/prd.md](prd.md) §7.1 Channel Lifecycle, §5.5 Objective/Crank Pattern
- [docs/context.md](context.md) - Nitro Objective pattern, Perun funding
- Phase 1+2 recap (events, state, signatures)
- ADR-0006 (objective/crank), ADR-0007 (side effects)

**Phase 4 (Durable Persistence):**
- [.claude/commands/4_phase_durable_persistence.md](../.claude/commands/4_phase_durable_persistence.md)
- [docs/prd.md](prd.md) §4.2 Event Storage, §6.1.3 Crash Recovery
- Phase 1 recap (in-memory event log)
- ADR-0008 (RocksDB), ADR-0009 (snapshot frequency)

**Phase 5 (DirectDefund Protocol):**
- [.claude/commands/5_phase_directdefund_protocol.md](../.claude/commands/5_phase_directdefund_protocol.md)
- [docs/prd.md](prd.md) §7.1.4 Channel Closing
- Phase 2+3 recap (state, signatures, DirectFund)

**Phase 6 (P2P Networking):**
- [.claude/commands/6_phase_p2p_networking.md](../.claude/commands/6_phase_p2p_networking.md)
- [docs/prd.md](prd.md) §6.2 Messaging Layer, §7.2 Message Format
- [docs/context.md](context.md) - Nitro/Perun P2P transport
- Phase 2+3 recap (message signing)
- ADR-0010 (P2P transport), ADR-0011 (message codec)

**Phase 7 (Chain Service):**
- [.claude/commands/7_phase_chain_service.md](../.claude/commands/7_phase_chain_service.md)
- [docs/prd.md](prd.md) §6.5 Chain Integration, §7.4 Consensus Rules
- Phase 2+3 recap (on-chain state verification)
- ADR-0012 (confirmation depth)

**Phase 8 (Consensus Channels):**
- [.claude/commands/8_phase_consensus_channels.md](../.claude/commands/8_phase_consensus_channels.md)
- [docs/prd.md](prd.md) §7.4 Consensus Channels, §5.5.3 Ledger Pattern
- [docs/context.md](context.md) - Nitro ledger channels, Perun sub-channels
- Phase 2+3+5+7 recap (full channel lifecycle)
- ADR-0013 (proposal ordering), ADR-0014 (guarantee locking)

**Phase 9 (VirtualFund/Defund):**
- [.claude/commands/9_phase_virtualfund_defund.md](../.claude/commands/9_phase_virtualfund_defund.md)
- [docs/prd.md](prd.md) §7.5 Virtual Channels
- [docs/context.md](context.md) - Perun virtual channels, Raiden mediated transfers
- Phase 3+5+8 recap (objectives, ledgers)
- ADR-0015 (multi-hop routing)

**Phase 10 (Payments):**
- [.claude/commands/10_phase_payments.md](../.claude/commands/10_phase_payments.md)
- [docs/prd.md](prd.md) §6.3.3 Payment Applications
- Phase 9 recap (virtual channels)

**Phase 11 (WASM Derivation):**
- [.claude/commands/11_phase_wasm_derivation.md](../.claude/commands/11_phase_wasm_derivation.md)
- [docs/prd.md](prd.md) §4.3 WASM Apps, §6.3 Application Layer
- [docs/context.md](context.md) - Arbitrum Nitro (WASM), Optimism Cannon, Deterministic WASM (WAVM)
- Phase 1+2+9 recap (event sourcing, state derivation, virtual channels)
- ADR-0016 (WASM runtime), ADR-0017 (determinism)

**Phase 12 (Production Hardening):**
- [.claude/commands/12_phase_production_hardening.md](../.claude/commands/12_phase_production_hardening.md)
- All previous phases
- [docs/prd.md](prd.md) §9 Success Metrics

**Time per phase:** 1-2 hours background reading, then ongoing during implementation

**Outcome:** Understand phase context, dependencies, validation criteria before writing code

---

## For Architects / Design Reviewers

**Goal:** Understand system design, review architectural decisions

1. **[README.md](../README.md)** - High-level overview
2. **[docs/prd.md](prd.md)** - Complete requirements (all sections)
   - §4: Core Concepts (event sourcing, message logs, WASM, PGlite, hubs)
   - §5: System Architecture (components, data flow, patterns)
   - §6: Functional Requirements (engine, messaging, WASM, contracts, P2P, hubs)
   - §7: Protocol Specifications (lifecycle, messages, state, consensus, virtual channels)
3. **[docs/context.md](context.md)** - Complete prior art review
   - State channels: Nitro, Perun, Counterfactual, Raiden
   - Rollups: Arbitrum Nitro, Optimism Cannon, Truebit
   - ZK: Mina, RISC Zero, zkWASM
   - Event sourcing: PGlite, ElectricSQL, Replicache
4. **[docs/adrs/README.md](adrs/README.md)** - All planned architectural decisions
5. **Individual ADR docs** - Read approved ADRs (currently just ADR-0001+)
6. **[docs/architecture/](architecture/)** - All architecture documents
7. **[.claude/commands/README.md](../.claude/commands/README.md)** - Phase dependency graph, critical path analysis
8. **Phase docs** - Read phases in dependency order to understand system buildup

**Time:** 6-8 hours initial reading, then ongoing

**Outcome:** Can review ADRs, evaluate architecture decisions, understand trade-offs, contribute to design

---

## For AI Assistants / Prompt Engineers

**Goal:** Understand prompt-driven development workflow and project constraints

1. **[CLAUDE.md](../CLAUDE.md)** - Complete instructions (communication style, Bun/Zig conventions, prompt-driven methodology)
2. **[.claude/commands/0_plan_phases.md](../.claude/commands/0_plan_phases.md)** - Master planning prompt, regeneration workflow
3. **[docs/phase-template.md](phase-template.md)** - Phase document structure
4. **[docs/adr-template.md](adr-template.md)** - ADR structure
5. **[docs/prd.md](prd.md) §1-5** - Core requirements and architecture
6. **[.claude/commands/README.md](../.claude/commands/README.md)** - Phase index and dependencies
7. **Sample phase doc** - e.g., [.claude/commands/1_phase_1_event_sourcing.md](../.claude/commands/1_phase_1_event_sourcing.md)
8. **Sample ADR** - When written (currently planning stage)

**Time:** 2-3 hours

**Outcome:** Can execute phases, write/improve prompts, regenerate code from updated specs, follow project methodology

---

## For Security Reviewers (Phase 12+)

**Goal:** Audit implementation security, identify vulnerabilities

1. **[docs/prd.md](prd.md)** - Complete requirements
   - §7: Protocol specs (threat model)
   - §6.4: Smart contract requirements
   - §6.5: Chain integration (reorg handling)
2. **[docs/context.md](context.md)** - Prior vulnerabilities
   - State channel exploits (reentrancy, griefing, commitment scheme attacks)
   - Rollup issues (determinism breaks, prover/verifier gaps)
3. **[docs/adrs/README.md](adrs/README.md)** - Security-critical ADRs
   - ADR-0004 (signature scheme)
   - ADR-0012 (confirmation depth)
   - ADR-0017 (WASM determinism)
4. **Implementation:** All `src/` code, especially:
   - `src/event_store/` - Event sourcing integrity
   - `src/protocols/` - Protocol state machines
   - `src/crypto/` - Signature verification
   - `src/chain/` - On-chain interaction
   - `src/wasm/` - Sandboxing, determinism
5. **[.claude/commands/12_phase_production_hardening.md](../.claude/commands/12_phase_production_hardening.md)** - Security audit checklist

**Time:** Weeks (full audit)

**Outcome:** Security assessment, vulnerability report, hardening recommendations

---

## Quick Reference by Task

**"I want to understand event sourcing in this project":**
- [docs/prd.md](prd.md) §4.1, §4.2
- [docs/context.md](context.md) Event Sourcing section
- [docs/architecture/event-types.md](architecture/event-types.md)
- [.claude/commands/1_phase_1_event_sourcing.md](../.claude/commands/1_phase_1_event_sourcing.md)

**"I want to understand state channels":**
- [docs/prd.md](prd.md) §7 (all subsections)
- [docs/context.md](context.md) State Channel Protocols section
- [.claude/commands/3_phase_directfund_protocol.md](../.claude/commands/3_phase_directfund_protocol.md)
- [.claude/commands/8_phase_consensus_channels.md](../.claude/commands/8_phase_consensus_channels.md)

**"I want to understand WASM derivation":**
- [docs/prd.md](prd.md) §4.3, §6.3
- [docs/context.md](context.md) Deterministic WASM section, Arbitrum Nitro, Optimism Cannon
- [.claude/commands/11_phase_wasm_derivation.md](../.claude/commands/11_phase_wasm_derivation.md)

**"I want to see the roadmap":**
- [README.md](../README.md) Development Roadmap section
- [.claude/commands/README.md](../.claude/commands/README.md) - Detailed phase breakdown with timeline
- [docs/prd.md](prd.md) §8 Implementation Roadmap

**"I want to write a test":**
- [CLAUDE.md](../CLAUDE.md) Zig section, TDD section
- [docs/fuzz-tests.md](fuzz-tests.md)
- [docs/phase-template.md](phase-template.md) §5 Testing Strategy

**"I want to write/review an ADR":**
- [docs/adrs/0000-adrs.md](adrs/0000-adrs.md) - Methodology
- [docs/adr-template.md](adr-template.md) - Template
- [docs/adrs/README.md](adrs/README.md) - Index of planned ADRs

**"I want to improve a phase prompt":**
- [CLAUDE.md](../CLAUDE.md) Prompt-Driven Development section
- [.claude/commands/0_plan_phases.md](../.claude/commands/0_plan_phases.md) - Planning methodology
- [docs/phase-template.md](phase-template.md) - Expected structure

---

## Navigation Tips

- **Relative links work in GitHub/editors:** All docs use relative markdown links
- **Start broad, go deep:** README → PRD → specific phase/ADR
- **Follow the dependency graph:** [.claude/commands/README.md](../.claude/commands/README.md) shows which phases build on others
- **Templates explain structure:** phase-template.md and adr-template.md clarify what each section means
- **Context is optional but valuable:** context.md provides "why" for many decisions, read when you want deeper understanding
- **Tests tell truth:** When docs conflict with code, read tests in `src/**/*.test.zig` and `testdata/`

---

## Document Index

### Root
- [README.md](../README.md) - Project overview
- [CLAUDE.md](../CLAUDE.md) - AI assistant instructions

### Core Documentation
- [docs/prd.md](prd.md) - Product requirements (3140 lines, comprehensive)
- [docs/context.md](context.md) - Prior art and research
- [docs/fuzz-tests.md](fuzz-tests.md) - Zig fuzz testing guide

### Templates
- [docs/phase-template.md](phase-template.md) - Phase document structure
- [docs/adr-template.md](adr-template.md) - ADR structure

### Architecture
- [docs/architecture/](architecture/) - Design documents
  - [event-types.md](architecture/event-types.md) - Event catalog for Phase 1+

### ADRs
- [docs/adrs/](adrs/) - Architectural decision records
  - [0000-adrs.md](adrs/0000-adrs.md) - ADR methodology
  - [README.md](adrs/README.md) - ADR index (17 planned)

### Phase Planning
- [.claude/commands/](../.claude/commands/) - Phase specifications
  - [0_plan_phases.md](../.claude/commands/0_plan_phases.md) - Planning methodology
  - [README.md](../.claude/commands/README.md) - Phase index with dependency graph
  - [START_PHASE_1.md](../.claude/commands/START_PHASE_1.md) - Phase 1 execution guide
  - [1_phase_1_event_sourcing.md](../.claude/commands/1_phase_1_event_sourcing.md) through [12_phase_production_hardening.md](../.claude/commands/12_phase_production_hardening.md) - Individual phase specs

---

*This guide maintained as part of prompt-driven development. Update when documentation structure changes.*
