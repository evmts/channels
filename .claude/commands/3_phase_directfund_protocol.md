# P3: DirectFund Protocol

**Meta:** P3 | Deps: P1, P2 | Owner: Core

## Summary

First complete protocol - DirectFund (prefund→deposit→postfund). Establishes Objective/Crank pattern (pure FSM). Critical - all protocols build on this pattern. Without DirectFund, cannot open funded channels. Preserves proven Objective architecture + event sourcing integration.

## Objectives

- OBJ-1: Objective interface with Crank pure functions
- OBJ-2: DirectFund protocol (prefund/deposit/postfund flow)
- OBJ-3: WaitingFor state computation (declarative blocking)
- OBJ-4: Side effect emission (messages, chain txs)
- OBJ-5: Mock chain/message services for testing

## Success Criteria

**Done when:**
- Objective interface: Crank, Update, SideEffects types
- DirectFund completes: Prefund→Deposit→Postfund 100%
- WaitingFor matches go-nitro states
- Side effects emit (messages + txs) 100% cov
- Perf: <1s setup 100 channels
- 100+ tests, 90%+ cov
- 2 ADRs approved (Objective pattern, SideEffect dispatch)
- Docs + demo live

**Exit gates:** Tests pass, integration (2 nodes fund channel), code review (2+)

## Architecture

**Components:** Objective (FSM interface), DirectFundObjective (funding impl), Crank (pure state transition), SideEffects (messages/txs to dispatch)

**Flow:**
```
CreateChannel → Objective{Prefund} → Crank() → {SendPrefund}
→ ReceivePrefund → Crank() → {Deposit}
→ DetectDeposit → Crank() → {SendPostfund}
→ ReceivePostfund → Crank() → {Complete}
```

## ADRs

**ADR-0006: Objective/Crank Pattern**
- Q: State machine design?
- Opts: A) Explicit FSM | B) Flowchart | C) Actor
- Rec: B (proven flowchart pattern)
- Why: Flexible, restartable, proven vs ⚠️ learning curve (ok worth it)

**ADR-0007: Side Effect Dispatch**
- Q: How execute effects?
- Opts: A) Direct | B) Queue | C) Event
- Rec: Return for engine dispatch
- Why: Pure objectives, testable vs ⚠️ indirect (ok engine simple)

## Data Structures

```zig
pub const Objective = struct {
    id: ObjectiveId,
    type: ObjectiveType,
    status: Status,
    data: ObjectiveData,

    pub fn crank(self: *Objective, input: Event) !CrankResult;
};

pub const DirectFundObjective = struct {
    channel: Channel,
    prefund_state: ?SignedState,
    postfund_state: ?SignedState,
    deposits_detected: bool,
};

pub const CrankResult = struct {
    updated: Objective,
    side_effects: []SideEffect,
    waiting_for: WaitingFor,
};

pub const WaitingFor = union(enum) {
    nothing,
    complete_prefund,
    my_turn_to_fund,
    complete_funding,
    complete_postfund,
};

pub const SideEffect = union(enum) {
    send_message: Message,
    submit_tx: Transaction,
};
```

## APIs

```zig
// Crank objective with event
pub fn crank(obj: *Objective, event: Event, a: Allocator) !CrankResult {
    return switch (obj.type) {
        .DirectFund => try crankDirectFund(obj, event, a),
    };
}

// Create DirectFund objective
pub fn createDirectFund(
    participants: []Address,
    nonce: u64,
    outcome: Outcome,
    a: Allocator
) !Objective;
```

## Implementation

**W1:** Docs (ADRs, Objective design, DirectFund spec)
**W2:** Objective interface + DirectFund data structures
**W3:** Crank impl (prefund, deposit, postfund logic)
**W4:** Mocks + integration tests + validation

**Tasks:** T1: Objective interface (M) | T2: WaitingFor (S) | T3: DirectFund data (M) | T4: Prefund crank (L) | T5: Deposit detection (M) | T6: Postfund crank (L) | T7: Mock chain (M) | T8: Mock messages (M) | T9: Integration (L) | T10: Unit tests (L)

**Path:** T1→T2→T3→T4→T5→T6→T9

## Testing

**Unit:** 100+ tests, 90%+ cov
- Prefund state transitions correct
- Deposit triggers postfund
- Postfund completes objective
- WaitingFor accurate each state

**Integration:**
- 2-party fund channel end-to-end
- Alice creates → exchange prefund → both deposit → exchange postfund → channel ready

## Dependencies

**Req:** P1 (EventStore), P2 (State/Sig)
**External:** Mock chain service (P7 preview)

## Risks

|Risk|P|I|Mitigation|
|--|--|--|--|
|Crank logic complex|M|M|TDD, state diagrams, extensive tests|
|Side effect dispatch unclear|M|M|ADR early, prototype engine|
|Mock services insufficient|L|L|Keep simple, real impl P6/P7|

## Deliverables

**Code:** `src/objectives/{objective,directfund}.zig`, tests
**Docs:** ADR-0006/0007, `docs/protocols/directfund.md`
**Val:** 90%+ cov, integration passes, demo

## Validation Gates

- G1: ADRs approved, Objective API designed, mocks ready
- G2: Code review (2+), tests pass
- G3: Integration passes, performance OK
- G4: Demo complete, P4/P5 unblocked

## Refs

**Phases:** P1 (Events), P2 (State)
**ADRs:** 0006 (Objective), 0007 (SideEffects)
**External:** State channel protocol patterns, flowchart-based FSM design

## Example

```zig
const obj = try objectives.createDirectFund(
    &[_]Address{alice, bob},
    nonce,
    outcome,
    allocator
);

// Crank with prefund received
const result = try obj.crank(Event{ .state_received = prefund }, allocator);

// Dispatch effects
for (result.side_effects) |effect| {
    switch (effect) {
        .send_message => |msg| try p2p.send(msg),
        .submit_tx => |tx| try chain.submit(tx),
    }
}
```
