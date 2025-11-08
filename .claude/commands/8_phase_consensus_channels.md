# P8: Consensus Channels

**Meta:** P8 | Deps: P2, P3, P5, P7 | Owner: Core

## Summary

Consensus channels (ledger channels) - leader/follower updates, proposal queues, guarantee management for virtual channels. Critical for P9 (VirtualFund) - virtual channels require ledger guarantees. Preserves proven leader/follower model + event sourcing. More complex than DirectFund due to asymmetric roles and concurrent proposals.

## Objectives

- OBJ-1: Leader/follower channel model (asymmetric updates)
- OBJ-2: Proposal queue (ordered processing)
- OBJ-3: Guarantee management (add/remove for virtual)
- OBJ-4: Concurrent proposals (queue + sequence)
- OBJ-5: Integrate with DirectFund/Defund (ledger lifecycle)

## Success Criteria

**Done when:**
- Leader proposes correctly (valid state)
- Follower countersigns 100%
- Proposal queue ordered correctly
- Guarantees add/remove (correct locking)
- Perf: <5s for 100 proposals
- 80+ tests, 90%+ cov
- 2 ADRs approved (proposal ordering, guarantee locking)
- Docs + demo

**Exit gates:** Tests pass, integration (ledger updates for virtual)

## Architecture

**Components:** ConsensusChannel (leader or follower role), ProposalQueue (ordered pending), GuaranteeManager (track virtual locks), LeaderChannel (generate proposals), FollowerChannel (countersign)

**Flow (Leader):**
```
AddGuarantee → CreateProposal → Sign → Send → WaitCountersig
→ ReceiveCountersigned → UpdateChannel → Emit GuaranteeAdded
```

**Flow (Follower):**
```
ReceiveProposal → Validate → Sign → Send → UpdateChannel
```

## ADRs

**ADR-0013: Proposal Ordering**
- Q: How order proposals?
- Opts: A) Trust leader | B) Sequence numbers | C) Queue+sort
- Rec: C (queue with sequence)
- Why: Robust, handles out-of-order vs ⚠️ complex (ok worth it)

**ADR-0014: Guarantee Locking**
- Q: When lock funds?
- Opts: A) At prefund | B) At postfund | C) First propose
- Rec: B (at postfund)
- Why: Matches proven patterns, funded channel vs ⚠️ delayed (ok safe)

## Data Structures

```zig
pub const ConsensusChannel = union(enum) {
    leader: LeaderChannel,
    follower: FollowerChannel,

    pub fn propose(self: *Self, change: Proposal) !SignedState;
    pub fn receive(self: *Self, proposal: SignedState) !?SignedState;
};

pub const LeaderChannel = struct {
    channel: Channel,
    proposal_queue: ProposalQueue,
    guarantees: GuaranteeManager,

    pub fn addGuarantee(self: *Self, target: ChannelId, amount: u256) !SignedState;
    pub fn removeGuarantee(self: *Self, target: ChannelId) !SignedState;
};

pub const FollowerChannel = struct {
    channel: Channel,
    last_proposal: ?SignedState,

    pub fn receiveProposal(self: *Self, proposal: SignedState) !SignedState;
};

pub const GuaranteeManager = struct {
    guarantees: HashMap(ChannelId, Guarantee),

    pub fn add(self: *Self, target: ChannelId, amount: u256) !void;
    pub fn remove(self: *Self, target: ChannelId) !void;
    pub fn isLocked(self: *Self, target: ChannelId) bool;
};
```

## APIs

```zig
// Create leader channel
pub fn createLeaderChannel(channel: Channel, a: Allocator) !ConsensusChannel;

// Add guarantee (leader proposes)
pub fn addGuarantee(
    self: *LeaderChannel,
    target: ChannelId,
    amount: u256,
    a: Allocator
) !SignedState;

// Receive + countersign (follower)
pub fn receiveProposal(
    self: *FollowerChannel,
    proposal: SignedState,
    a: Allocator
) !SignedState;
```

## Implementation

**W1:** Docs (ADRs), consensus design, guarantee manager
**W2:** Leader/follower impl, proposal queue
**W3:** Validation logic, concurrent proposal handling
**W4:** Integration tests, VirtualFund preview, validation

**Tasks:** T1: ConsensusChannel types (M) | T2: GuaranteeManager (M) | T3: ProposalQueue (M) | T4: LeaderChannel (L) | T5: FollowerChannel (L) | T6: Validation (M) | T7: VirtualFund preview (M) | T8: Concurrent tests (L) | T9: Integration (L)

**Path:** T1→T2→T3→T4→T5→T6→T8→T9

## Testing

**Unit:** 80+ tests
- Leader proposes guarantee addition
- Follower countersigns valid proposal
- Proposal queue maintains order
- Guarantees locked correctly

**Integration:**
- Ledger channel updates for virtual funding
- Alice-Hub and Hub-Bob ledgers → add guarantees for virtual channel

## Dependencies

**Req:** P2 (State), P3 (Objectives), P5 (Defund), P7 (Chain for funding)

## Risks

|Risk|P|I|Mitigation|
|--|--|--|--|
|Proposal ordering bugs|M|H|Extensive concurrent tests, sequence validation|
|Guarantee locking races|M|H|Careful FSM, unit tests|
|Leader/follower confusion|L|M|Clear API separation, type system|
|Virtual fund integration complex|M|M|Defer full to P9, test stubs|

## Deliverables

**Code:** `src/channel/{consensus_channel,leader,follower,guarantees}.zig`, tests
**Docs:** ADR-0013/0014, `docs/architecture/consensus-channels.md`
**Val:** 90%+ cov, integration passes

## Validation Gates

- G1: ADRs approved, consensus channel designed
- G2: Code review, proposal queue works
- G3: Integration passes (guarantee add/remove)
- G4: Docs complete, P9 unblocked

## Refs

**Phases:** P2 (State), P3 (Objectives), P5 (Defund), P7 (Chain)
**ADRs:** 0013 (Proposal ordering), 0014 (Guarantee locking)
**External:** State channel consensus patterns, ledger channel designs

## Example

```zig
// Leader adds guarantee
var leader = try createLeaderChannel(ledger, allocator);
const proposal = try leader.addGuarantee(virtual_id, 50, allocator);

// Send to follower
try p2p.sendMessage(follower_addr, Message{ .propose_state = proposal });

// Follower countersigns
var follower = try createFollowerChannel(ledger, allocator);
const countersigned = try follower.receiveProposal(proposal, allocator);
```
