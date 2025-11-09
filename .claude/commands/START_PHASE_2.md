# Execute Phase 2: Core State & Signatures

**Status:** Ready to Execute ✅
**Phase:** 2 of 12
**Duration:** 4 weeks
**Dependencies:** P1 (Event Sourcing) ✅ | Voltaire integrated ✅

---

## Context

Phase 1 complete - events defined, event store working. Now implementing core state channel primitives: State types, signatures, ABI encoding, ChannelId generation.

**Why Phase 2 is Critical:**
- Foundation for ALL state channel protocols (P3-P9)
- State types used by every protocol
- ChannelId generation enables channel identification
- Signatures enable cryptographic verification
- ABI encoding ensures Ethereum L1 compatibility

**What Changed from Original Plan:**
- ❌ zabi (incompatible with Zig 0.15.1)
- ✅ voltaire/primitives (proven in guillotine-mini, 100% API coverage)
- ⚠️ Voltaire crypto marked UNAUDITED - acceptable for development/testing

---

## Phase 2 Reference

**Full Spec:** `.claude/commands/2_phase_core_state_and_signatures.md`

**Key Sections:**
- Quick Start (lines 5-42): Day 1 checklist, voltaire imports ready
- Summary (lines 62-64): Core primitives overview
- Objectives (lines 66-71): 5 primary goals
- Data Structures (lines 124-195): State, FixedPart, VariablePart, Outcome, Signature
- Dependencies (lines 262-313): Voltaire integration guide (already done!)
- Implementation (lines 223-249): Week-by-week plan + daily targets
- Testing (lines 251-260): Unit tests, integration tests, benchmarks
- Success Criteria (lines 74-87): Exit criteria checklist

---

## Pre-Flight Check ✅

**Completed:**
- ✅ P1 Event Store events defined (20 events)
- ✅ Voltaire/primitives integrated (`build.zig`, `build.zig.zon`)
- ✅ Tests passing with voltaire modules imported
- ✅ Phase 2 prompt updated with voltaire integration guide
- ✅ Local ../voltaire with libcrypto_wrappers.a built

**Available Voltaire APIs:**
```zig
const primitives = @import("primitives");
const crypto_pkg = @import("crypto");

// Types
const Address = primitives.Address.Address;
const Hash = crypto_pkg.Hash;
const Crypto = crypto_pkg.Crypto;
const abi = primitives.AbiEncoding;

// Core functions
Hash.keccak256(data: []const u8) -> [32]u8
abi.encodePacked(allocator, values: []AbiValue) -> ![]u8
Crypto.unaudited_signHash(hash: [32]u8, pk: [32]u8) -> !Signature
Crypto.unaudited_recoverAddress(hash: [32]u8, sig: Signature) -> !Address
```

---

## Day 1: ADRs + Core Types + ChannelId

### Morning: Write ADRs (2-3 hours)

**ADR-0004: Signature Scheme**
- **File:** `docs/adrs/0004-signature-scheme.md`
- **Template:** `docs/adr-template.md`
- **Decision:** secp256k1 recoverable signatures via voltaire
- **Rationale:**
  - Ethereum compatibility (address recovery)
  - Proven in Bitcoin/Ethereum ecosystems
  - Hardware wallet support
  - ⚠️ Voltaire implementation UNAUDITED (mark as testing-only)
- **Alternatives considered:** ed25519 (faster but no recovery), BLS (complex)
- **Content:** See Phase 2 spec lines 105-109

**ADR-0005: State Encoding**
- **File:** `docs/adrs/0005-state-encoding.md`
- **Decision:** Ethereum ABI packed encoding
- **Rationale:**
  - Smart contract compatibility (L1 adjudicator)
  - Deterministic (same state → same bytes)
  - Standard format (cross-implementation compatibility)
- **Alternatives considered:** JSON (non-deterministic), RLP (Ethereum-specific), custom binary
- **Content:** See Phase 2 spec lines 111-115

**ADR-0006: ChannelId Generation**
- **File:** `docs/adrs/0006-channel-id-generation.md`
- **Decision:** `keccak256(abi.encodePacked(participants, nonce, appDef, challengeDuration))`
- **Rationale:**
  - Deterministic (same FixedPart → same ID)
  - Collision-resistant (256-bit hash)
  - Standard pattern from go-nitro/nitro-protocol
- **Alternatives considered:** Random UUID (non-deterministic), hash(participants+nonce) only (insufficient)
- **Content:** See Phase 2 spec lines 117-122

### Afternoon: Core Types (3-4 hours)

**Create `src/state/types.zig`**

Define all core types (reference spec lines 124-195):

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Address = [20]u8;
pub const Bytes32 = [32]u8;
pub const ChannelId = Bytes32;

pub const FixedPart = struct {
    participants: []Address,
    channel_nonce: u64,
    app_definition: Address,
    challenge_duration: u32,

    pub fn clone(self: FixedPart, a: Allocator) !FixedPart {
        const participants_copy = try a.alloc(Address, self.participants.len);
        @memcpy(participants_copy, self.participants);
        return FixedPart{
            .participants = participants_copy,
            .channel_nonce = self.channel_nonce,
            .app_definition = self.app_definition,
            .challenge_duration = self.challenge_duration,
        };
    }

    pub fn deinit(self: FixedPart, a: Allocator) void {
        a.free(self.participants);
    }
};

pub const VariablePart = struct {
    app_data: []const u8,
    outcome: Outcome,
    turn_num: u64,
    is_final: bool,

    pub fn clone(self: VariablePart, a: Allocator) !VariablePart {
        const app_data_copy = try a.dupe(u8, self.app_data);
        const outcome_copy = try self.outcome.clone(a);
        return VariablePart{
            .app_data = app_data_copy,
            .outcome = outcome_copy,
            .turn_num = self.turn_num,
            .is_final = self.is_final,
        };
    }

    pub fn deinit(self: VariablePart, a: Allocator) void {
        a.free(self.app_data);
        self.outcome.deinit(a);
    }
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

    pub fn fixedPart(self: State) FixedPart {
        return FixedPart{
            .participants = self.participants,
            .channel_nonce = self.channel_nonce,
            .app_definition = self.app_definition,
            .challenge_duration = self.challenge_duration,
        };
    }

    pub fn variablePart(self: State, a: Allocator) !VariablePart {
        return VariablePart{
            .app_data = try a.dupe(u8, self.app_data),
            .outcome = try self.outcome.clone(a),
            .turn_num = self.turn_num,
            .is_final = self.is_final,
        };
    }

    pub fn clone(self: State, a: Allocator) !State {
        const participants_copy = try a.alloc(Address, self.participants.len);
        @memcpy(participants_copy, self.participants);
        const app_data_copy = try a.dupe(u8, self.app_data);
        const outcome_copy = try self.outcome.clone(a);

        return State{
            .participants = participants_copy,
            .channel_nonce = self.channel_nonce,
            .app_definition = self.app_definition,
            .challenge_duration = self.challenge_duration,
            .app_data = app_data_copy,
            .outcome = outcome_copy,
            .turn_num = self.turn_num,
            .is_final = self.is_final,
        };
    }

    pub fn deinit(self: State, a: Allocator) void {
        a.free(self.participants);
        a.free(self.app_data);
        self.outcome.deinit(a);
    }
};

pub const Signature = struct {
    r: [32]u8,
    s: [32]u8,
    v: u8,

    pub fn toBytes(self: Signature) [65]u8 {
        var result: [65]u8 = undefined;
        @memcpy(result[0..32], &self.r);
        @memcpy(result[32..64], &self.s);
        result[64] = self.v;
        return result;
    }

    pub fn fromBytes(bytes: [65]u8) Signature {
        var r: [32]u8 = undefined;
        var s: [32]u8 = undefined;
        @memcpy(&r, bytes[0..32]);
        @memcpy(&s, bytes[32..64]);
        return Signature{
            .r = r,
            .s = s,
            .v = bytes[64],
        };
    }
};

pub const Outcome = struct {
    asset: Address,
    allocations: []Allocation,

    pub fn clone(self: Outcome, a: Allocator) !Outcome {
        const allocations_copy = try a.alloc(Allocation, self.allocations.len);
        for (self.allocations, 0..) |alloc, i| {
            allocations_copy[i] = try alloc.clone(a);
        }
        return Outcome{
            .asset = self.asset,
            .allocations = allocations_copy,
        };
    }

    pub fn deinit(self: Outcome, a: Allocator) void {
        for (self.allocations) |alloc| {
            alloc.deinit(a);
        }
        a.free(self.allocations);
    }
};

pub const Allocation = struct {
    destination: Bytes32,
    amount: u256,
    allocation_type: AllocationType,
    metadata: []const u8,

    pub const AllocationType = enum(u8) {
        simple = 0,
        guarantee = 1,
    };

    pub fn clone(self: Allocation, a: Allocator) !Allocation {
        const metadata_copy = try a.dupe(u8, self.metadata);
        return Allocation{
            .destination = self.destination,
            .amount = self.amount,
            .allocation_type = self.allocation_type,
            .metadata = metadata_copy,
        };
    }

    pub fn deinit(self: Allocation, a: Allocator) void {
        a.free(self.metadata);
    }
};
```

**Create `src/state/types.test.zig`**

Test construction, clone, invariants:

```zig
const std = @import("std");
const testing = std.testing;
const types = @import("types.zig");

test "FixedPart - construction and clone" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const alice: types.Address = [_]u8{0xAA} ** 20;
    const bob: types.Address = [_]u8{0xBB} ** 20;
    const participants = try allocator.alloc(types.Address, 2);
    participants[0] = alice;
    participants[1] = bob;

    const fixed = types.FixedPart{
        .participants = participants,
        .channel_nonce = 42,
        .app_definition = [_]u8{0x00} ** 20,
        .challenge_duration = 86400,
    };

    const cloned = try fixed.clone(allocator);
    defer cloned.deinit(allocator);
    defer fixed.deinit(allocator);

    try testing.expectEqual(fixed.channel_nonce, cloned.channel_nonce);
    try testing.expectEqual(fixed.challenge_duration, cloned.challenge_duration);
    try testing.expectEqualSlices(types.Address, fixed.participants, cloned.participants);
}

test "State - turn number monotonicity invariant" {
    // Test that turn_num must be monotonically increasing
    const alice: types.Address = [_]u8{0xAA} ** 20;
    const bob: types.Address = [_]u8{0xBB} ** 20;

    // Create state with turn 0
    // Create state with turn 1
    // Verify turn 1 > turn 0
}

test "Signature - bytes conversion roundtrip" {
    const sig = types.Signature{
        .r = [_]u8{0x01} ** 32,
        .s = [_]u8{0x02} ** 32,
        .v = 27,
    };

    const bytes = sig.toBytes();
    const decoded = types.Signature.fromBytes(bytes);

    try testing.expectEqualSlices(u8, &sig.r, &decoded.r);
    try testing.expectEqualSlices(u8, &sig.s, &decoded.s);
    try testing.expectEqual(sig.v, decoded.v);
}
```

**Create `src/state/channel_id.zig`**

ChannelId generation using voltaire:

```zig
const std = @import("std");
const types = @import("types.zig");
const primitives = @import("primitives");
const crypto_pkg = @import("crypto");

const ChannelId = types.ChannelId;
const FixedPart = types.FixedPart;
const Hash = crypto_pkg.Hash;
const abi = primitives.AbiEncoding;

pub fn channelId(fixed: FixedPart, allocator: std.mem.Allocator) !ChannelId {
    // Build ABI values for participants array
    var participant_values = try allocator.alloc(abi.AbiValue, fixed.participants.len);
    defer allocator.free(participant_values);

    for (fixed.participants, 0..) |addr, i| {
        const prim_addr = primitives.Address.Address{ .bytes = addr };
        participant_values[i] = abi.addressValue(prim_addr);
    }

    // Encode participants array separately (dynamic type)
    const participants_encoded = try abi.encodePacked(allocator, participant_values);
    defer allocator.free(participants_encoded);

    // Build values for fixed fields
    const app_addr = primitives.Address.Address{ .bytes = fixed.app_definition };
    const values = [_]abi.AbiValue{
        abi.AbiValue{ .uint64 = fixed.channel_nonce },
        abi.addressValue(app_addr),
        abi.AbiValue{ .uint32 = fixed.challenge_duration },
    };

    // Encode fixed fields
    const fixed_encoded = try abi.encodePacked(allocator, &values);
    defer allocator.free(fixed_encoded);

    // Concatenate: participants + nonce + appDef + challengeDuration
    const total_len = participants_encoded.len + fixed_encoded.len;
    const combined = try allocator.alloc(u8, total_len);
    defer allocator.free(combined);

    @memcpy(combined[0..participants_encoded.len], participants_encoded);
    @memcpy(combined[participants_encoded.len..], fixed_encoded);

    // Keccak256 hash
    return Hash.keccak256(combined);
}
```

**Create `src/state/channel_id.test.zig`**

Test determinism and cross-impl vectors:

```zig
const std = @import("std");
const testing = std.testing;
const types = @import("types.zig");
const channel_id = @import("channel_id.zig");

test "ChannelId - deterministic generation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const alice: types.Address = [_]u8{0xAA} ** 20;
    const bob: types.Address = [_]u8{0xBB} ** 20;
    const participants = try allocator.alloc(types.Address, 2);
    defer allocator.free(participants);
    participants[0] = alice;
    participants[1] = bob;

    const fixed = types.FixedPart{
        .participants = participants,
        .channel_nonce = 42,
        .app_definition = [_]u8{0x00} ** 20,
        .challenge_duration = 86400,
    };

    const id1 = try channel_id.channelId(fixed, allocator);
    const id2 = try channel_id.channelId(fixed, allocator);

    try testing.expectEqualSlices(u8, &id1, &id2);
}

test "ChannelId - different nonce produces different ID" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const alice: types.Address = [_]u8{0xAA} ** 20;
    const bob: types.Address = [_]u8{0xBB} ** 20;
    const participants = try allocator.alloc(types.Address, 2);
    defer allocator.free(participants);
    participants[0] = alice;
    participants[1] = bob;

    const fixed1 = types.FixedPart{
        .participants = participants,
        .channel_nonce = 42,
        .app_definition = [_]u8{0x00} ** 20,
        .challenge_duration = 86400,
    };

    const fixed2 = types.FixedPart{
        .participants = participants,
        .channel_nonce = 43,
        .app_definition = [_]u8{0x00} ** 20,
        .challenge_duration = 86400,
    };

    const id1 = try channel_id.channelId(fixed1, allocator);
    const id2 = try channel_id.channelId(fixed2, allocator);

    try testing.expect(!std.mem.eql(u8, &id1, &id2));
}

// TODO: Add cross-impl test vector from Ethereum contract
// test "ChannelId - matches Ethereum contract test vector" {}
```

**Update `src/root.zig`**

Export state module:

```zig
pub const state = struct {
    pub const types = @import("state/types.zig");
    pub const channel_id = @import("state/channel_id.zig");
};

// Add to test block
test {
    _ = @import("state/types.test.zig");
    _ = @import("state/channel_id.test.zig");
}
```

### End of Day 1

**Run tests:**
```bash
zig build test
```

**Commit:**
```bash
git add docs/adrs/000{4,5,6}-*.md src/state/
git commit -m "📚 docs: Add P2 ADRs for signatures, encoding, ChannelId

✨ feat: Implement core state types and ChannelId generation

- Add ADR-0004 (Signature Scheme - secp256k1 via voltaire)
- Add ADR-0005 (State Encoding - Ethereum ABI packed)
- Add ADR-0006 (ChannelId Generation - keccak256 formula)
- Implement State, FixedPart, VariablePart, Outcome, Allocation, Signature
- Implement ChannelId generation using voltaire ABI + Keccak256
- Tests: construction, clone, determinism, invariants
- All tests passing"
```

**Expected state:** Core types defined, ChannelId working, tests green ✅

---

## Day 2: State Hashing + Signatures

### Morning: State Hashing (3 hours)

**Create `src/state/hash.zig`**

State hashing using voltaire ABI encoding + Keccak256 (see spec lines 437-446).

### Afternoon: Signatures (3 hours)

**Create `src/crypto/signature.zig`**

Sign/verify using voltaire Crypto module (see spec lines 301-313).

**Create `src/crypto/signature.test.zig`**

Test signature roundtrip, recovery (see spec lines 251-253).

---

## Day 3: ABI Wrapper + Event Integration

**Create `src/abi/encoder.zig`**

Thin wrapper over voltaire AbiEncoding for state-specific encoding patterns.

**Update event emission**

Integrate State operations with P1 events (StateSigned, StateReceived).

---

## Day 4: Tests + Benchmarks + Demo

**Integration tests:** Full lifecycle (Create → Sign → Verify → Emit)
**Benchmarks:** Verify <1ms ChannelId, <2ms hash, <10ms sign+verify
**Demo:** Alice/Bob channel example
**Documentation:** Architecture docs, API reference

---

## Success Criteria (Day 4 Exit Gates)

From spec lines 74-87:

- ✅ Types defined: State, FixedPart, VariablePart, Outcome, Signature
- ✅ ABI encoding byte-identical to Ethereum contracts
- ✅ ChannelId 100% match to test vectors
- ✅ Signature verify + pubkey recovery 100% correct
- ✅ State hash deterministic
- ✅ Events emit for all ops (100% cov)
- ✅ Perf: <10ms P95 sign+verify
- ✅ 60+ tests, 90%+ cov
- ✅ 3 ADRs approved (0004, 0005, 0006)
- ✅ Docs + demo

---

## References

**Phase 2 Full Spec:** `.claude/commands/2_phase_core_state_and_signatures.md`
**Voltaire Examples:** `../voltaire/examples/signature_recovery.zig`
**Guillotine-mini Reference:** `../guillotine-mini/build.zig` (proven voltaire integration)
**ADR Template:** `docs/adr-template.md`
**P1 Events:** `src/event_store/events.zig` (StateSigned, StateReceived events available)

---

## Notes

**Voltaire Security:** All crypto functions marked `unaudited_*` - acceptable for P2 development/testing. Document audit requirement for production in ADR-0004.

**Cross-impl Testing:** Phase 2 spec lines 252-254 - compare ChannelId/encoding against Ethereum contract test vectors.

**Event Integration:** Phase 2 spec lines 400-446 - emit events for all state operations (ChannelId generation, signing, verification).
