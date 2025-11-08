# ADR-NNNN: [Title]

<adr-metadata>
**Status:** Proposed/Accepted/Deprecated/Superseded | **Date:** YYYY-MM-DD | **Deciders:** [Names] | **Related:** ADR-XXX | **Phase:** N
</adr-metadata>

## Context

<context>
**Problem:** [Arch problem/challenge]
**Constraints:** [Technical/business/timeline]
**Assumptions:** [What assuming]
**Affected:** [Who/what impacted]

**Ex:** Store channel data. go-nitro: snapshots (BuntDB). Our vision: audit trails, time-travel debug, provable derivation. Snapshots lose history→hard debug, unverifiable.
</context>

## Drivers

<drivers>
**Top 3-5 factors (prioritized):**
Performance, DevEx, Maintainability, Compat, Security, Cost, TTM

**Ex:** Debuggability (replay transitions), Auditability (3rd party verify), Perf (<100ms reconstruct), Storage (unbounded growth), Compat (Nitro contracts)
</drivers>

## Options

<options>
### Opt 1: [Name]
**Desc:** [Approach] | **Pros:** ✅ [1], ✅ [2] | **Cons:** ❌ [1], ❌ [2] | **Effort:** S/M/L/XL
```zig
// Code showing approach
```

### Opt 2: [Name]
**Desc:** ... | **Pros/Cons:** ... | **Effort:** ...

### Comparison
|Criterion (wt)|Opt1|Opt2|Opt3|
|--|--|--|--|
|Perf (10)|8→80|6→60|9→90|
|Debug (9)|10→90|5→45|7→63|
|**Total**|**239**|**206**|**210**|
</options>

## Decision

<decision>
**Choose:** [Option X: specific approach]
**Why:** Best satisfies drivers | Trade-offs accepted | Right choice given constraints

**Ex:** Event sourcing via append-only log (Opt 1). Provides debuggability+auditability (core value prop). Accept: storage overhead+reconstruction cost. Mitigate: snapshotting (optimization not source-of-truth).
</decision>

## Consequences

<consequences>
**Pos:** ✅ Full audit trail, ✅ Time-travel debug, ✅ Provable derivation
**Neg:** ❌ Storage overhead, ❌ Reconstruction cost
**Mitigate:** Storage→Snapshot+Prune (periodic, prune old, compress) | Reconstruction→Cache+Snapshot (cache mem, invalidate on new, start from latest snap)
</consequences>

## Implementation

<implementation>
**Structure:** `src/module/file.zig`
```zig
pub const Interface = struct {...};
```
**Tests:** Unit (serial), integration (replay), perf (reconstruct), stress (large logs)
**Docs:** `docs/{architecture,api,tutorials}/[topic].md`
**Migration:** [Steps if changing existing]
</implementation>

## Validation

<validation>
**Metrics:** Write >1000 ev/s, reconstruct <100ms/1000ev, storage <10MB/ch/24h, dev sat+
**Monitor:** Log size, reconstruct perf (P50/P95/P99), alert >200ms, cache hit rate
**Review:** 3mo (perf/opt?), 6mo (devex/abstraction?), 12mo (still holds?)
**Revise if:** Bottleneck >100ms P95, storage over budget, new tech (ZK proofs), req change
</validation>

## Related

<related>
**Deps:** ADR-XXXX (depends), ADR-YYYY (informs) | **Supersedes:** ADR-ZZZZ | **See:** Phase N, External (go-nitro ADR, paper)
</related>

<references>
[Papers], [Prior art], [Discussions], [Benchmarks]
</references>

<changelog>
- YYYY-MM-DD: Initial (Proposed)
- YYYY-MM-DD: Review update (Accepted)
- YYYY-MM-DD: Deprecated (superseded ADR-XXXX)
</changelog>
