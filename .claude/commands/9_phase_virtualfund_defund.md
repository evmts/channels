# P9: VirtualFund/Defund

**Meta:** P9 | Deps: P3, P5, P8 | Owner: Core

## Summary

Virtual channels - 3-party channels (Alice-Hub-Bob) requiring no on-chain txs beyond initial ledgers. Enables multi-hop payments, scalable channel networks. Critical innovation: Guarantees in ledger channels secure virtual channel, eliminating per-channel on-chain cost. Most complex protocol - coordinates 3 parties, manages guarantees across 2 ledgers. Preserves proven VirtualFund pattern + event sourcing.

## Objectives

- OBJ-1: VirtualFundObjective (3-party coordination)
- OBJ-2: Guarantee locking in ledgers (Alice-Hub, Hub-Bob)
- OBJ-3: Virtual channel state management (no on-chain)
- OBJ-4: VirtualDefundObjective (remove guarantees, close virtual)
- OBJ-5: Multi-hop support (Alice-Hub-Bob-Carol chains)

## Success Criteria

**Done when:**
- Virtual fund completes (3-party setup) 100%
- Guarantees locked correctly (exact amounts)
- No on-chain txs (except ledgers) 0 for virtual
- Virtual defund completes (guarantees released)
- Perf: <30s setup 100 virtual channels
- 100+ tests, 90%+ cov
- ADR approved (multi-hop routing)
- Docs + demo

**Exit gates:** Tests pass, integration (Alice-Hub-Bob fund/defund)

## Architecture

**Components:** VirtualFundObjective (3-party coordinator), VirtualDefundObjective (3-party teardown), IntermediaryRole (hub manages both ledgers), EndpointRole (Alice/Bob single ledger)

**Flow (Alice-Hub-Bob funding):**
```
Alice → CreateVirtual → ProposeHub
→ Hub → LockGuarantees(Alice-Hub ledger, Hub-Bob ledger) → ProposeAlice + ProposeBob
→ Alice/Bob → AcceptProposals → VirtualReady
```

**Defunding:**
```
Alice → ProposeDefund → Hub
→ Hub → RemoveGuarantees(both ledgers) → Alice/Bob
→ Alice/Bob → Accept → VirtualClosed
```

## ADRs

**ADR-0015: Multi-hop Routing**
- Q: How route through intermediaries?
- Opts: A) Source routing | B) Onion | C) Path finding
- Rec: A (source routing P9), defer complex routing P12
- Why: Simpler, explicit, works hub topology vs ⚠️ limited (ok for v1)

## Data Structures

```zig
pub const VirtualFundObjective = struct {
    virtual_channel: Channel,
    left_ledger: ChannelId,  // Alice-Hub
    right_ledger: ChannelId, // Hub-Bob
    role: ParticipantRole,
    prefund_complete: bool,
    guarantees_locked: bool,
    postfund_complete: bool,
};

pub const ParticipantRole = enum {
    alice,      // Left endpoint
    hub,        // Intermediary
    bob,        // Right endpoint
};

pub const VirtualDefundObjective = struct {
    virtual_channel_id: ChannelId,
    left_ledger: ChannelId,
    right_ledger: ChannelId,
    role: ParticipantRole,
    final_state: ?SignedState,
    guarantees_removed: bool,
};
```

## APIs

```zig
// Create virtual channel (Alice initiates)
pub fn createVirtualChannel(
    alice: Address,
    bob: Address,
    hub: Address,
    outcome: Outcome,
    a: Allocator
) !Objective;

// Hub locks guarantees
pub fn lockGuaranteesForVirtual(
    hub: *Hub,
    virtual_id: ChannelId,
    alice_amount: u256,
    bob_amount: u256,
    a: Allocator
) !void;

// Defund virtual
pub fn defundVirtualChannel(virtual_id: ChannelId, a: Allocator) !Objective;
```

## Implementation

**W1:** Docs (ADRs), virtual fund design, role definitions
**W2:** Endpoint impl, basic 3-party coordination
**W3:** Intermediary impl, guarantee management
**W4:** Defund impl, integration tests, validation

**Tasks:** T1: VirtualFund/Defund objectives (M) | T2: Endpoint role (L) | T3: Intermediary role (L) | T4: Guarantee coordination (L) | T5: 3-party message exchange (M) | T6: VirtualDefund impl (L) | T7: Multi-hop preview (M) | T8: Integration (XL) | T9: Performance (M)

**Path:** T1→T2→T3→T4→T5→T6→T8

## Testing

**Unit:** 100+ tests
- Alice initiates virtual
- Hub locks guarantees both ledgers
- 3-party coordination correct

**Integration:**
- Alice-Hub-Bob virtual channel full lifecycle
- Fund ledgers → create virtual → no on-chain txs → defund virtual → guarantees removed

## Dependencies

**Req:** P3 (DirectFund), P5 (DirectDefund), P8 (Consensus for guarantees)
**External:** P6 (P2P for 3-party coordination)

## Risks

|Risk|P|I|Mitigation|
|--|--|--|--|
|3-party coordination complex|H|H|Extensive integration tests, FSM diagrams|
|Guarantee locking races|M|H|Careful sequencing, P8 tests reused|
|Hub failure scenarios|M|H|Test hub crash during funding, recovery|
|Multi-hop routing bugs|M|M|Limit 1-hop initially, defer complex|
|Performance worse than expected|M|M|Benchmark early, optimize message rounds|

## Deliverables

**Code:** `src/objectives/{virtualfund,virtualdefund}.zig`, role impls, tests
**Docs:** ADR-0015, `docs/architecture/virtual-channels.md`
**Val:** 90%+ cov, integration passes (full lifecycle)

## Validation Gates

- G1: ADR approved, virtual fund designed, roles clear
- G2: Code review, 3-party coordination works
- G3: Integration passes (fund + defund)
- G4: Docs complete, P10 unblocked

## Refs

**Phases:** P3 (DirectFund), P5 (DirectDefund), P8 (Consensus)
**ADRs:** 0015 (Multi-hop)
**External:** Virtual channel protocols, multi-hop state channel research

## Example

```zig
// Alice creates virtual to Bob via Hub
const virtual_id = try alice.createVirtualChannel(
    .to = bob_addr,
    .via = &[_]Address{hub_addr},
    .outcome = outcome,
);

// Hub auto locks guarantees when receives proposal
// Alice/Bob exchange states
// Virtual ready with no on-chain txs

// Later: defund
try alice.defundVirtualChannel(virtual_id);
```
