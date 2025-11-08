# Phase Template

<phase-metadata>
**Phase:** N | **Name:** [Name] | **Status:** Planning/InProgress/Complete/Blocked | **Deps:** Phase X,Y or None | **Duration:** N wk | **Owner:** [Team]
</phase-metadata>

## 1. Summary

<summary>
Single paragraph: What accomplished + Why important + How fits roadmap + Consequence if skipped
Template: "Phase N establishes [WHAT] enabling [WHY]. Critical: [REASON]. Without: [CONSEQUENCE]."
</summary>

## 2. Objectives & Success

<objectives>
**Goals (3-5, measurable, action verbs):**
- OBJ-1: Implement X
- OBJ-2: Design Y
- OBJ-3: Document Z
</objectives>

<success-criteria>
|Criterion|Validation|Owner|Target|
|--|--|--|--|
|Types defined|Code review+docs|Lead|15+ types|
|Serialization|Unit tests|Eng|100% pass|
|Perf|Benchmark|Eng|<100ms|

**Exit (ALL req'd):** Tests pass (unit+integration, 90%+ cov), code review (2+), docs reviewed, perf benchmarks met, ADRs approved, demo done
</success-criteria>

## 3. Architecture

<architecture>
**Components:** A: [Responsibility]; B: [Responsibility]
**Flow:** `A→B: [msg] → C: [event]`
**Diagram:** [Link]
</architecture>

<architectural-decisions>
**ADRs needed:**
1. ADR-XXX: [Title] | Q: [?] | Opts: A/B/C | Rec: B | Why: [reason]
2. ADR-YYY: [Title] | Q: [?] | Opts: ... | Rec: ... | Why: ...
</architectural-decisions>

<data-structures>
```zig
pub const Type = struct { field: FieldType, };
```
**Invariants:** [Must be true]; **Constraints:** [Enforced how]
</data-structures>

<apis>
```zig
pub fn method(self: *Self, param: Type) !Return {...}
```
**Principles:** Explicit errors/alloc/cleanup, type-safe
</apis>

## 4. Implementation

<work-breakdown>
|Task|Desc|Est|Deps|
|--|--|--|--|
|T1|[Action]|S/M/L/XL|None|

**Est:** S=1-4h, M=1-2d, L=3-5d, XL=1-2wk | **Path:** T1→T2→T5→T9
</work-breakdown>

<implementation-sequence>
**W1:** Docs (arch/ADRs/API/examples)
**W2:** Tests (specs/failing tests TDD/scenarios/benchmarks)
**W3-4:** Code (implement→pass/refactor/doc/optimize)
**W5:** Validate (review/perf/security/demo)
</implementation-sequence>

## 5. Testing

<unit-tests>
**Cov:** 90%+ | **Types:** Happy path, errors, boundary, properties
```zig
test "desc" { // concrete code }
```
</unit-tests>

<integration-tests>
**Scenarios:** Multi-component, concurrency, persistence (crash/restart), performance (throughput/latency/mem)
</integration-tests>

<test-fixtures>
```zig
pub const TestData = struct { pub fn sample() T {...} };
// Mocks: MockStore, MockChain, MockMsg
```
</test-fixtures>

## 6. Documentation

<code-docs>
**Req:** All public funcs/types documented, complex algos explained, examples per API
**Format:** `/// Desc. Example: ```code``` Returns: X. Errors: Y.`
</code-docs>

<arch-docs>
**Create:** `docs/architecture/[topic].md` covering: overview, rationale, how works, examples, diagrams
</arch-docs>

<api-docs>
**Gen:** `zig doc` | **Manual:** API ref, usage, best practices, troubleshooting
</api-docs>

## 7. Dependencies

<dependencies>
**Required:** Phase X provides Y; Phase Z provides W | **External:** Zig 0.13+, libs [versions], tools
</dependencies>

<optional-deps>
**Nice:** [Improves X], [Enables Y]
</optional-deps>

## 8. Risks

<technical-risks>
|Risk|Prob|Impact|Mitigation|
|--|--|--|--|
|[Tech risk]|L/M/H|L/M/H|[Prevention/handling]|
</technical-risks>

<schedule-risks>
|Risk|Prob|Impact|Mitigation|
|Underest complexity|M|M|20% buffer, scope cut|
|Blocked deps|L|H|Parallel workstreams|
</schedule-risks>

## 9. Deliverables

<deliverables>
**Code:** `src/module/*.zig` + tests
**Docs:** ADR-XXX, `docs/{architecture,api}/[topic].md`
**Val:** Coverage report, perf bench, demo
</deliverables>

## 10. Validation

<validation-gates>
**G1 (Design→Code):** ADRs approved, API reviewed, test strategy OK
**G2 (During):** 2+ reviewers, no criticals, cov met
**G3 (Pre-Done):** CI green, perf met, integration OK
**G4 (Accept):** Demo, deliverables in, docs pub, sign-off
</validation-gates>

<acceptance>
**When:** All success criteria + gates + deliverables + no blockers + next phase ready
**Rollback:** Doc learnings, update future phases, revert if needed, revise
</acceptance>

## 11. Lessons (Post)

<lessons-learned>
**Well:** [1], [2] | **Improve:** [1], [2] | **Challenges:** [1]: Solution | **Impact:** Phase X change | **Metrics:** Plan vs actual (duration/scope/cov/perf)
</lessons-learned>

## Refs

<references>
**Templates & Frameworks:**
- [ADR Template](adr-template.md) - Structure for architectural decisions
- [Phase Template](phase-template.md) - This template (for reference)
- [Planning Methodology](../.claude/commands/0_plan_phases.md) - How phases are generated

**Project Context:**
- [PRD](prd.md) - Product requirements (§4 Core Concepts, §5 Architecture, §6-7 specific requirements)
- [Context](context.md) - Prior art (state channels, rollups, event sourcing patterns from Nitro, Perun, Arbitrum, etc.)
- [Learning Paths](LEARNING_PATHS.md) - Guided reading for implementers

**Architecture & Decisions:**
- [Architecture Docs](architecture/) - Design documents (event-types.md, etc.)
- [ADR Index](adrs/README.md) - All architectural decisions mapped to phases
- Specific ADRs: [ADR-XXX], [ADR-YYY] (replace with actual ADRs for this phase)

**Testing & Implementation:**
- [Fuzz Tests Guide](fuzz-tests.md) - Zig fuzz testing (Linux/Docker)
- [CLAUDE.md](../CLAUDE.md) - Coding conventions, TDD approach, Zig 0.15+ notes

**Dependencies:**
- Prior phases: [Phase X](../.claude/commands/X_phase_*.md), [Phase Y](../.claude/commands/Y_phase_*.md)
- External: [Papers, specs, implementations]

**Related Code:**
- Implementation: `src/module/*.zig`
- Tests: `src/module/*.test.zig`
</references>

<example>
```zig
// Usage of deliverables
```
</example>
