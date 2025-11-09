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
- WaitingFor matches proven FSM states
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
pub const Objective = union(ObjectiveType) {
    DirectFund: DirectFundObjective,
    DirectDefund: void,
    VirtualFund: void,
    VirtualDefund: void,

    pub fn crank(self: *Objective, event: ObjectiveEvent, a: Allocator) !CrankResult;
};

pub const DirectFundObjective = struct {
    id: ObjectiveId,
    channel_id: ChannelId,
    status: ObjectiveStatus,
    my_index: u8,  // Which participant are we (0-indexed)

    // Channel parameters
    fixed: FixedPart,
    funding_outcome: Outcome,

    // Protocol state tracking - one slot per participant
    prefund_signatures: []?Signature,
    postfund_signatures: []?Signature,
    deposits_detected: []bool,

    allocator: Allocator,

    // Helper functions must be public for tests
    pub fn allPrefundSigned(self: DirectFundObjective) bool;
    pub fn allPostfundSigned(self: DirectFundObjective) bool;
    pub fn allDepositsDetected(self: DirectFundObjective) bool;
    pub fn isMyTurnToDeposit(self: DirectFundObjective) bool;
    pub fn generatePrefundState(self: DirectFundObjective, a: Allocator) !State;
    pub fn generatePostfundState(self: DirectFundObjective, a: Allocator) !State;
};

pub const CrankResult = struct {
    side_effects: []SideEffect,
    waiting_for: WaitingFor,

    pub fn deinit(self: CrankResult, a: Allocator) void;
};

pub const WaitingFor = union(enum) {
    nothing,
    approval,           // Waiting for policymaker approval
    complete_prefund,   // Waiting for all prefund signatures
    my_turn_to_fund,    // Waiting for our turn to deposit on-chain
    complete_funding,   // Waiting for all deposits to appear on-chain
    complete_postfund,  // Waiting for all postfund signatures

    pub fn isBlocked(self: WaitingFor) bool;
};

pub const SideEffect = union(enum) {
    send_message: Message,
    submit_tx: Transaction,
    emit_event: EmittedEvent,  // NOTE: Renamed to avoid collision with ObjectiveEvent

    pub fn deinit(self: SideEffect, a: Allocator) void;
    pub fn clone(self: SideEffect, a: Allocator) !SideEffect;
};
```

## APIs

```zig
// Crank objective with event
pub fn crank(self: *Objective, event: ObjectiveEvent, a: Allocator) !CrankResult {
    return switch (self.*) {
        .DirectFund => |*obj| try obj.crank(event, a),
        else => unreachable,
    };
}

// Create DirectFund objective
pub fn init(
    objective_id: ObjectiveId,
    my_index: u8,
    fixed: FixedPart,
    funding_outcome: Outcome,
    a: Allocator,
) !DirectFundObjective {
    const n = fixed.participants.len;
    const prefund_sigs = try a.alloc(?Signature, n);
    @memset(prefund_sigs, null);
    const postfund_sigs = try a.alloc(?Signature, n);
    @memset(postfund_sigs, null);
    const deposits = try a.alloc(bool, n);
    @memset(deposits, false);
    const cid = try channel_id.channelId(fixed, a);

    return DirectFundObjective{
        .id = objective_id,
        .channel_id = cid,
        .status = .Unapproved,
        .my_index = my_index,
        .fixed = try fixed.clone(a),
        .funding_outcome = try funding_outcome.clone(a),
        .prefund_signatures = prefund_sigs,
        .postfund_signatures = postfund_sigs,
        .deposits_detected = deposits,
        .allocator = a,
    };
}
```

## Implementation

**W1:** Docs (ADRs, Objective design, DirectFund spec)
**W2:** Objective interface + DirectFund data structures
**W3:** Crank impl (prefund, deposit, postfund logic)
**W4:** Mocks + integration tests + validation

**Tasks:** T1: Objective interface (M) | T2: WaitingFor (S) | T3: DirectFund data (M) | T4: Prefund crank (L) | T5: Deposit detection (M) | T6: Postfund crank (L) | T7: Mock chain (M) | T8: Mock messages (M) | T9: Integration (L) | T10: Unit tests (L)

**Path:** T1→T2→T3→T4→T5→T6→T9

### Critical Implementation Details

**Zig 0.15 ArrayList Usage:**
```zig
// IMPORTANT: Use AlignedManaged in Zig 0.15+
const array_list = std.array_list;
var effects = array_list.AlignedManaged(SideEffect, null).init(a);
```

**Deposit Sequencing:**
Deposits must occur in participant index order:
```zig
pub fn isMyTurnToDeposit(self: DirectFundObjective) bool {
    // Deposit in order of participant index
    for (self.deposits_detected, 0..) |deposited, i| {
        if (i < self.my_index and !deposited) return false;  // Wait for earlier participants
        if (i == self.my_index and !deposited) return true;  // Our turn!
    }
    return false; // Already deposited
}
```

**Turn Number Formulas:**
```zig
// Prefund: turn 0, empty outcome
const prefund_turn = 0;

// Postfund: turn = (n * 2) - 1 where n = participants.len
const postfund_turn = (fixed.participants.len * 2) - 1;  // e.g., 3 for 2-party
```

**Deposit Detection Logic:**
```zig
.deposit_detected => |dd| {
    const depositor_idx = try self.findParticipantIndex(dd.depositor);
    self.deposits_detected[depositor_idx] = true;

    // Check if it's now our turn to deposit
    if (!self.deposits_detected[self.my_index] and self.isMyTurnToDeposit()) {
        const deposit_tx = try self.generateDepositTx(a);
        try effects.append(.{ .submit_tx = deposit_tx });
    }

    // If all deposits detected, generate and send postfund
    if (self.allDepositsDetected() and self.postfund_signatures[self.my_index] == null) {
        // ... generate postfund, sign, send to peers
    }
},
```

**Memory Ownership:**
- `otherParticipants()` allocates slice - ownership transfers to SideEffect
- Do NOT defer free the peers slice after appending to effects
- Tests must clone states for events and defer cleanup:
```zig
const state_clone = try state.clone(a);
defer state_clone.deinit(a);
const result = try obj.crank(.{ .state_received = .{ .state = state_clone, ... } }, a);
```

## Testing

**Unit:** 100+ tests, 90%+ cov
- Prefund state transitions correct
- Deposit triggers postfund
- Postfund completes objective
- WaitingFor accurate each state
- Helper functions public for test access

**Integration:**
- 2-party fund channel end-to-end
- Alice creates → exchange prefund → both deposit → exchange postfund → channel ready

**Critical Test Pattern:**
Each participant must receive their own deposit_detected event:
```zig
// Alice emits deposit tx
const tx = result.side_effects[0].submit_tx;
try chain.submitDeposit(tx, alice_obj.channel_id, alice_addr);

// Alice must detect her own deposit
{
    const result = try alice_obj.crank(
        .{ .deposit_detected = .{
            .channel_id = alice_obj.channel_id,
            .depositor = alice_addr,
            .amount = 1000,
        } },
        a,
    );
    defer result.deinit(a);
}

// Then Bob detects Alice's deposit
{
    const result = try bob_obj.crank(
        .{ .deposit_detected = .{
            .channel_id = bob_obj.channel_id,
            .depositor = alice_addr,
            .amount = 1000,
        } },
        a,
    );
    defer result.deinit(a);
    // Bob should now emit his deposit tx
}
```

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

---

## CONTEXT FROM PHASE 1 (Objective Events)

**Phase 1 Status:** Objective lifecycle events defined ✅

### Objective Events to Emit

Phase 1 defined **5 objective lifecycle events** to integrate with DirectFund protocol:

**Events to Use:**
- [`objective-created`](../../schemas/events/objective-created.schema.json) - When DirectFund objective spawned
- [`objective-approved`](../../schemas/events/objective-approved.schema.json) - After policymaker approves funding
- [`objective-cranked`](../../schemas/events/objective-cranked.schema.json) - Each time Crank() executes
- [`objective-completed`](../../schemas/events/objective-completed.schema.json) - When funding reaches Postfund complete
- [`objective-rejected`](../../schemas/events/objective-rejected.schema.json) - If funding fails/rejected

**State Transition Events (from Phase 1):**
- `state-signed` - When generating prefund/postfund states
- `state-received` - When receiving counterparty's states
- `deposit-detected` - When chain service observes deposit

**Implementation Files:**
- Event types: [src/event_store/events.zig](../../src/event_store/events.zig)
- Event schemas: [schemas/events/objective-*.schema.json](../../schemas/events/)
- Event catalog: [docs/architecture/event-types.md](../../docs/architecture/event-types.md)

### Integration Pattern for DirectFund

**Objective Creation:**
```zig
pub fn createDirectFund(
    participants: []Address,
    nonce: u64,
    outcome: Outcome,
    event_store: *EventStore,
    allocator: Allocator
) !*DirectFundObjective {
    const obj_id = ObjectiveId.generate();
    const channel_id = try FixedPart.channelId(...);
    
    // Emit objective-created event
    try event_store.append(Event{
        .objective_created = .{
            .event_version = 1,
            .timestamp_ms = @intCast(std.time.milliTimestamp()),
            .objective_id = obj_id,
            .objective_type = .DirectFund,
            .channel_id = channel_id,
            .participants = participants,
        },
    });
    
    return DirectFundObjective{
        .id = obj_id,
        .channel_id = channel_id,
        .status = .Unapproved,
        // ...
    };
}
```

**Crank Execution:**
```zig
pub fn crank(
    self: *DirectFundObjective,
    event_store: *EventStore,
    allocator: Allocator
) !CrankResult {
    const side_effects = try self.computeSideEffects(allocator);
    
    // Emit objective-cranked event
    try event_store.append(Event{
        .objective_cranked = .{
            .event_version = 1,
            .timestamp_ms = @intCast(std.time.milliTimestamp()),
            .objective_id = self.id,
            .side_effects_count = @intCast(side_effects.len),
            .waiting = self.waitingFor() != .None,
        },
    });
    
    return CrankResult{
        .updated_objective = self,
        .side_effects = side_effects,
    };
}
```

**Objective Completion:**
```zig
if (self.status == .Complete) {
    try event_store.append(Event{
        .objective_completed = .{
            .event_version = 1,
            .timestamp_ms = @intCast(std.time.milliTimestamp()),
            .objective_id = self.id,
            .success = true,
            .final_channel_state = try self.getPostfundHash(allocator),
        },
    });
}
```

### Event-Driven Protocol Flow

**Traditional snapshot approach:** Objective updates internal state, returns side effects

**Event-sourced approach (our implementation):**
1. Objective receives event (e.g., `state-received`)
2. Crank computes next state + side effects (pure function)
3. **Emit `objective-cranked` event** documenting transition
4. Return side effects for dispatch
5. Side effect execution triggers new events (e.g., `message-sent`)

**Audit trail:** Can replay all `objective-*` events to reconstruct funding flow

### Validation Using Event History

DirectFund validation can query event log:
```zig
pub fn validate(self: *DirectFundObjective, ctx: ValidationContext) !void {
    // Check if already completed
    const events = try ctx.getObjectiveEvents(self.id);
    for (events) |evt| {
        if (evt == .objective_completed) return error.AlreadyCompleted;
    }
    
    // Verify state progression
    const state_events = try ctx.getChannelEvents(self.channel_id);
    const prefund_count = countStatesSigned(state_events, 0); // turn 0
    const postfund_count = countStatesSigned(state_events, 3); // turn 3
    
    if (self.status == .Postfund and postfund_count < 2) {
        return error.InsufficientSignatures;
    }
}
```

### Files to Reference

**Phase 1 deliverables:**
- Objective events: [schemas/events/objective-*.schema.json](../../schemas/events/)
- State events: [schemas/events/state-*.schema.json](../../schemas/events/)
- Chain events: [schemas/events/deposit-detected.schema.json](../../schemas/events/deposit-detected.schema.json)
- Event types: [src/event_store/events.zig](../../src/event_store/events.zig)

**Phase 2 deliverables (when complete):**
- State types for prefund/postfund generation
- Signature creation for signed states

**Don't re-implement:**
- Event type definitions (use existing Event union)
- Event emission (use EventStore.append from Phase 1b)

**Do implement:**
- DirectFundObjective type
- Crank() logic (FSM transitions)
- SideEffect computation
- WaitingFor state logic

---

**Context Added:** 2025-11-08  
**Dependencies:** Phase 1 (events ✅), Phase 1b (EventStore - pending), Phase 2 (State/Sig - pending)
