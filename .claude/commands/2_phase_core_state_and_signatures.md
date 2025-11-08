# P2: Core State & Signatures

**Meta:** P2 | Deps: P1 | Owner: Core

## Summary

Channel state primitives: State/FixedPart/VariablePart structures, secp256k1 signatures, ABI encoding, ChannelId generation. Foundation for all protocols - without state types, cannot represent/verify channel updates. Preserves go-nitro proven model, replaces strings with tagged unions, integrates event sourcing.

## Objectives

- OBJ-1: State/FixedPart/VariablePart + ABI encoding
- OBJ-2: secp256k1 sign/verify with recovery
- OBJ-3: Keccak256 (Ethereum-compatible)
- OBJ-4: ChannelId generation (matches go-nitro)
- OBJ-5: Emit events for state operations

## Success Criteria

**Done when:**
- Types defined: State, FixedPart, VariablePart, Outcome, Signature
- ABI encoding byte-identical to go-nitro
- ChannelId 100% match to go-nitro vectors
- Signature verify + pubkey recovery 100% correct
- State hash deterministic
- Events emit for all ops (100% cov)
- Perf: <10ms P95 sign+verify
- 60+ tests, 90%+ cov
- 2 ADRs approved (sig scheme, ABI encoding)
- Docs + demo

**Exit gates:** Tests pass, cross-impl match, benchmarks met, code review (2+)

## Architecture

**Components:**
```
Protocol Layer (P3+)
  ↓ uses State types
State Module: State, Signature, Outcome
  → ABI Encoding / Hashing (Ethereum-compat)
  ↓ emits events
EventStore (P1)
```

**Flow:** Create State → ChannelId=hash(FixedPart) → ABI encode → Keccak256 → Sign → Emit StateSigned → Receive → Verify recovery → Emit StateVerified

## ADRs

**ADR-0004: Signature Scheme**
- Q: Which sig scheme?
- Opts: A) secp256k1 recoverable | B) ed25519 | C) BLS
- Rec: A
- Why: Ethereum compat, address recovery, proven, HW wallet vs ⚠️ slower than ed25519 (ok <5ms)

**ADR-0005: State Encoding**
- Q: Encoding format?
- Opts: A) Ethereum ABI packed | B) JSON | C) Custom binary | D) RLP
- Rec: A
- Why: Contract compat, deterministic, go-nitro match vs ⚠️ complex (padding rules)

**ADR-0006: ChannelId Generation**
- Q: How compute ID?
- Opts: A) Hash(FixedPart) | B) Random UUID | C) Hash(Participants, Nonce)
- Rec: A (full FixedPart)
- Why: Deterministic, go-nitro compat, prevents collisions
- Formula: `Keccak256(abi.encode(participants, nonce, appDef, challengeDuration))`

## Data Structures

```zig
pub const Address = [20]u8;
pub const Bytes32 = [32]u8;
pub const ChannelId = Bytes32;

pub const FixedPart = struct {
    participants: []Address,
    channel_nonce: u64,
    app_definition: Address,
    challenge_duration: u32,

    pub fn channelId(self: FixedPart, a: Allocator) !ChannelId;
    pub fn clone(self: FixedPart, a: Allocator) !FixedPart;
};

pub const VariablePart = struct {
    app_data: []const u8,
    outcome: Outcome,
    turn_num: u64,
    is_final: bool,

    pub fn clone(self: VariablePart, a: Allocator) !VariablePart;
};

pub const State = struct {
    // Fixed
    participants: []Address,
    channel_nonce: u64,
    app_definition: Address,
    challenge_duration: u32,
    // Variable
    app_data: []const u8,
    outcome: Outcome,
    turn_num: u64,
    is_final: bool,

    pub fn fixedPart(self: State) FixedPart;
    pub fn variablePart(self: State, a: Allocator) !VariablePart;
    pub fn channelId(self: State, a: Allocator) !ChannelId;
    pub fn hash(self: State, a: Allocator) !Bytes32;
    pub fn sign(self: State, a: Allocator, pk: [32]u8) !Signature;
    pub fn recoverSigner(self: State, a: Allocator, sig: Signature) !Address;
    pub fn clone(self: State, a: Allocator) !State;
};

pub const Signature = struct {
    r: [32]u8,
    s: [32]u8,
    v: u8,

    pub fn toBytes(self: Signature) [65]u8;
    pub fn fromBytes(bytes: [65]u8) Signature;
};

pub const Outcome = struct {
    asset: Address,
    allocations: []Allocation,

    pub fn clone(self: Outcome, a: Allocator) !Outcome;
};

pub const Allocation = struct {
    destination: Bytes32,
    amount: u256,
    allocation_type: AllocationType,
    metadata: []const u8,

    pub const AllocationType = enum(u8) { simple, guarantee };
    pub fn clone(self: Allocation, a: Allocator) !Allocation;
};
```

**Invariants:**
- ChannelId deterministic
- Turns monotonic: `state[n+1].turn_num > state[n].turn_num`
- Participants ordered: `participants[i]` signs turns `i mod len`
- Sig valid: `recoverSigner(state, sig) in participants`
- Final immutable: `is_final == true` → no updates

## APIs

```zig
// Sign Ethereum message (prefix + rehash + sign)
pub fn signEthereumMessage(hash: Bytes32, pk: [32]u8) !Signature;

// Recover address from signature
pub fn recoverEthereumMessageSigner(hash: Bytes32, sig: Signature) !Address;

// ABI encode tuple
pub fn abiEncode(a: Allocator, values: anytype) ![]u8;

// Emit events
pub fn emitStateSigned(store: *EventStore, state: State, sig: Signature, a: Allocator) !void;
pub fn emitStateReceived(store: *EventStore, state: State, sig: Signature, from: Address, a: Allocator) !void;
```

## Implementation

**W1:** ADRs, core types (State/FixedPart/VariablePart), ChannelId generation
**W2:** secp256k1 integration, ABI encoding
**W3:** State hashing, sign/verify, unit tests
**W4:** Cross-impl test vs go-nitro, event integration, benchmarks, demo

**Tasks:**
- T1: Define structs (S, P0)
- T2: Define Outcome/Allocation/Signature (S, P0)
- T3: ChannelId generation (M, P0)
- T4: State hashing (L, P0)
- T5: secp256k1 lib integration (M, P0)
- T6: Sign creation (M, P0)
- T7: Verify/recovery (M, P0)
- T8: ABI encoding (L, P0)
- T9: Event emission (M, P1)
- T10-13: Tests, benchmarks, ADRs, docs

**Path:** T1→T3→T4→T5→T6→T7→Cross-impl test

## Testing

**Unit:** 60+ tests, 90%+ cov
- ChannelId deterministic
- State hash deterministic
- Sig roundtrip correct
- ABI encoding byte-match
- Event emission complete

**Integration:**
- Full lifecycle: Create → Sign → Verify → Emit → Reconstruct
- Cross-impl: Our encoding matches go-nitro byte-for-byte

**Benchmarks:**
- ChannelId: <1ms
- State hash: <2ms
- Sign+verify: <10ms P95

## Dependencies

**Req:** P1 (EventStore), Zig 0.15+, zabi (secp256k1 + Keccak256)

## Risks

|Risk|P|I|Mitigation|
|--|--|--|--|
|ABI encoding bugs|M|H|Cross-test vs go-nitro, contract vectors|
|Sig verify wrong recovery|M|H|Test vs ethers.js, proven lib|
|Keccak256 incorrect|L|H|Use tested lib (zabi)|
|secp256k1 integration complex|M|M|2 days allocated, test thoroughly|

## Deliverables

**Code:** `src/state/{types,channel_id,hash}.zig`, `src/crypto/signature.zig`, `src/abi/encoder.zig`, tests
**Docs:** ADR-0004/0005, arch docs (state structure, signatures, ABI), API ref
**Val:** 90%+ cov, cross-impl match, benchmarks met

## Validation Gates

- G1: ADRs approved, API designed, zabi integrated
- G2: Code review (2+), tests pass, 90%+ cov
- G3: Cross-impl passes, benchmarks met, events work
- G4: Demo complete, docs published, P3 unblocked

## Refs

**Phases:** P1 (Events)
**ADRs:** 0004 (Sig), 0005 (ABI), 0006 (ChannelId)
**External:** go-nitro `channel/state/state.go`, Ethereum ABI spec, EIP-191, secp256k1 spec

## Example

```zig
// Create state
const state = State{
    .participants = &[_]Address{alice, bob},
    .channel_nonce = 42,
    .app_definition = app,
    .challenge_duration = 86400,
    .app_data = &[_]u8{},
    .outcome = outcome,
    .turn_num = 0,
    .is_final = false,
};

// ChannelId
const id = try state.channelId(allocator);

// Sign
const sig = try state.sign(allocator, alice_key);

// Verify
const addr = try state.recoverSigner(allocator, sig);
const valid = std.mem.eql(u8, &addr, &alice);
```
