# Project: Event-Sourced State Channels in Zig

**Building:** WASM-based state channel implementation for op-stack with event sourcing as core innovation. Event log = source-of-truth (vs snapshots). Enables audit trails, time-travel debugging, provable state derivation.

**Reference:** `docs/` contains PRD, architecture, planning framework.

**Methodology:** Doc→Test→Code. Phases planned via prompts (`.claude/commands/N_phase_*.md`). Prompts versioned+committed. When implementation reveals issues: update prompt→regenerate code→git rebase.

**Key Docs:**
- `docs/prd.md` - Complete product requirements
- `docs/context.md` - Prior art and research (state channels, rollups, event sourcing)
- `docs/LEARNING_PATHS.md` - Guided reading sequences for different personas
- `docs/phase-template.md` - Structure for all phases
- `docs/adr-template.md` - Architectural decision record structure
- `docs/adrs/0000-adrs.md` - ADR methodology
- `docs/architecture/` - Design documents (event-types.md, etc.)
- `docs/fuzz-tests.md` - Zig fuzz testing guide (Linux/Docker)
- `.claude/commands/0_plan_phases.md` - Master planning prompt
- `.claude/commands/README.md` - Phase index and dependency graph

---

## Communication

**Style:** Radio dispatcher. Brief even at expense of grammar/complete sentences. Pack max info into min text. Concise efficient communication.

---

## Bun (TypeScript/Frontend)

Default Bun over Node.js:
- `bun <file>` not `node`/`ts-node`
- `bun test` not `jest`/`vitest`
- `bun build` not `webpack`/`esbuild`
- `bun install` not `npm`/`pnpm`/`yarn`
- `bun run <script>` not `npm run`
- Bun auto-loads .env (no dotenv)

---

## Zig

**Version Issues:** Training data uses Zig 0.14, we use 0.15+. Breaking changes: I/O reader/writer interfaces, Array interface. When blocked: check std lib code in homebrew.

**Tests:** Separate files: `foo.zig` + `foo.test.zig`. Add all tests to `root.zig` so they run. See [fuzz testing guide](docs/fuzz-tests.md) for fuzzing.

**Errors:** Always handle. Never swallow (incl allocation). Panic/unreachable only if codepath impossible.

---

## Persistence & Alignment

Prefer failing doing it our way over simpler path. Rather learn from failed attempt than try shortcut we won't use. Use learnings→improve prompt→retry clean context.

---

## Context Passing

Consistently create new context windows. When done: eagerly suggest prompt for next agent compressing useful context.

**Remove:** Useless details
**Include:** Essential context
**Compress:** Repetitive info→specify pattern
**Follow:** Context passing protocol on auto-compact

---

## TDD

Always verify via TDD or test-after. Tests committed, drive commit history.

---

## Prompt-Driven Development

**Prompts = Code:** Version, review, improve prompts in `.claude/commands/`

**Regeneration workflow:**
1. Execute phase
2. Discover issues/learnings
3. Update prompts (planning, phase-specific)
4. Regenerate code/tests/docs
5. Git rebase to apply retroactively

**When:** Wrong assumptions, better approach, new ADR, dep change, missed perf target

**Result:** Prompts improve over time, code regenerated from improved specs
