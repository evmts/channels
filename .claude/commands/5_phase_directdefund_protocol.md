# P5: DirectDefund Protocol

**Meta:** P5 | Deps: P2, P3 | Owner: Core

## Summary

Symmetric closing protocol for funded channels. Finalize (exchange final state), conclude (submit to adjudicator), withdraw (transfer assets). Critical for lifecycle completion - without defund, assets locked forever. Simpler than DirectFund (no deposit detection), builds on P3 Objective pattern.

## Objectives

- OBJ-1: DirectDefundObjective (finalize→conclude→withdraw)
- OBJ-2: Final state exchange (is_final=true, signed by both)
- OBJ-3: On-chain conclusion tx submission
- OBJ-4: Withdrawal after finalization
- OBJ-5: Handle cooperative close (happy path) + force close (dispute)

## Success Criteria

**Done when:**
- Finalization completes (exchange final states) 100%
- Conclusion tx submits (correct calldata to adjudicator)
- Withdrawal successful (exact balance transfer)
- Cooperative close <500ms
- Force close handles challenge/timeout
- 50+ tests, 90%+ cov
- Docs + demo

**Exit gates:** Tests pass, integration (close end-to-end)

## Architecture

**Components:** DirectDefundObjective (closing FSM), FinalState (is_final=true construction), Conclusion (on-chain tx gen), Withdrawal (asset transfer)

**Flow:**
```
ProposeClose → CreateFinalState → ExchangeSigs
→ SubmitConclusion → WaitForFinalization → Withdraw → Complete
```

**Alternative (Force Close):**
```
Unresponsive → Challenge → Wait(timeout) → Conclude → Withdraw
```

## Data Structures

```zig
pub const DirectDefundObjective = struct {
    channel: Channel,
    final_state: ?SignedState,
    conclusion_tx: ?Transaction,
    finalized_on_chain: bool,
    withdrawn: bool,
};
```

## APIs

```zig
// Create defund objective
pub fn createDirectDefund(
    channel_id: ChannelId,
    final_outcome: Outcome,
    a: Allocator
) !Objective;

// Generate conclusion tx
pub fn generateConclusionTx(
    final_state: SignedState,
    a: Allocator
) !Transaction;
```

## Implementation

**W1:** DirectDefund objective + final state + crank logic
**W2:** Conclusion tx gen + withdrawal + testing + validation

**Tasks:** T1: Define objective (S) | T2: Final state creation (M) | T3: Defund crank (M) | T4: Conclusion tx (M) | T5: Withdrawal (M) | T6: Test cooperative (M) | T7: Test force (M) | T8: Integration (L)

**Path:** T1→T2→T3→T4→T5→T6→T8

## Testing

**Unit:** 50+ tests
- Final state exchange completes
- Conclusion tx correct calldata
- Withdrawal exact amounts

**Integration:**
- Alice/Bob close cooperatively
- Exchange final sigs → submit conclusion → withdraw → balances correct

## Dependencies

**Req:** P2 (State), P3 (Objective pattern)
**External:** Mock chain for tx submission

## Risks

|Risk|P|I|Mitigation|
|--|--|--|--|
|Conclusion tx encoding wrong|M|H|Cross-test reference implementations, validate ABI|
|Withdrawal timing issues|L|M|Test finalization scenarios|
|Force close complex|M|M|Defer P7 integration, test thoroughly|

## Deliverables

**Code:** `src/objectives/directdefund.zig`, tests
**Docs:** `docs/protocols/directdefund.md`
**Val:** 90%+ cov, integration passes

## Validation Gates

- G1: Defund API designed, conclusion tx format specified
- G2: Code review, tests pass
- G3: Integration passes (cooperative close)
- G4: Docs complete, P8 unblocked

## Refs

**Phases:** P2 (State), P3 (Objective)
**ADRs:** 0006 (Objective)
**External:** State channel defund protocols, op-stack compatible contracts (NitroAdjudicator pattern)

## Example

```zig
// Close channel
const obj = try objectives.createDirectDefund(
    channel_id,
    final_outcome,
    allocator
);

// Crank with final state received
const result = try obj.crank(Event{ .state_received = final }, allocator);

// Submit conclusion
for (result.side_effects) |effect| {
    if (effect == .submit_tx) try chain.submit(effect.submit_tx);
}
```
