# P2: Core State & Signatures

**Meta:** P2 | Deps: P1 | Owner: Core
**Status:** Ready to Execute ✅

---

## Quick Start (Execute Day 1)

**Pre-flight:** Voltaire integrated ✅ | P1 events complete ✅ | Tests passing ✅

**⚠️ CRITICAL LEARNINGS FROM PHASE 1:**
Phase 1 cleanup revealed critical issues that MUST be avoided in Phase 2:
1. **Debug prints left in production code** → Add grep check before every commit
2. **Incomplete golden test vectors** → Generate actual hashes, not placeholders
3. **Missing event fields in tests** → Compile immediately after importing events
4. **Zig 0.15 ArrayList API differences** → Always pass allocator explicitly
5. **Memory ownership double-frees** → Only defer struct.deinit(), never both
6. **ValidationCtx stub pattern** → Use global test store to prevent scope issues

See detailed patterns in "Zig 0.15 Constraints & API Changes" section below.

**FIRST: Update Voltaire to latest:**
```bash
zig fetch --save=primitives https://github.com/evmts/primitives/archive/refs/heads/main.tar.gz
zig build test  # Verify integration still works
```

**Day 1 Checklist:**
1. Write ADR-0004 (Signature Scheme - secp256k1 recoverable + voltaire unaudited note)
2. Write ADR-0005 (State Encoding - Ethereum ABI packed)
3. Write ADR-0006 (ChannelId Generation - keccak256(abi.encodePacked(fixedPart)))
4. Create `src/state/types.zig` - State, FixedPart, VariablePart, Outcome, Allocation, Signature
5. Create `src/state/types.test.zig` - construction, clone, invariants
6. Create `src/state/channel_id.zig` - ChannelId generation using voltaire
7. Create `src/state/channel_id.test.zig` - determinism, cross-impl vectors
8. Update `src/root.zig` - export state module
9. **CRITICAL:** Remove any debug print statements before commit (grep check below)

**Pre-commit verification:**
```bash
# Must return no results
grep -r "std.debug.print" src/state/ --exclude="*.test.zig"

# Run tests
zig build test
```

**Voltaire imports ready:**
```zig
const primitives = @import("primitives");
const crypto_pkg = @import("crypto");
const Address = primitives.Address.Address;
const Hash = crypto_pkg.Hash;
const Crypto = crypto_pkg.Crypto;
const abi = primitives.AbiEncoding;
```

**File structure to create:**
```
src/
├── state/
│   ├── types.zig          # State, FixedPart, VariablePart, Outcome
│   ├── types.test.zig
│   ├── channel_id.zig     # ChannelId generation
│   └── channel_id.test.zig
├── crypto/               # (Day 2)
└── abi/                  # (Day 2-3)
```

**Expected outcome Day 1:**
- ✅ Voltaire updated to latest
- ✅ ADRs approved (0004, 0005, 0006)
- ✅ Core types defined with proper memory cleanup
- ✅ ChannelId working with correct encoding order
- ✅ Tests passing with no memory leaks
- ✅ **Debug output removed from production code** (grep verification passed)
- ✅ **Golden test vectors have actual hashes** (not placeholders)

---

## Day-by-Day Execution Plan

### Day 1: ADRs + Core Types + ChannelId

**Morning: Write ADRs (2-3 hours)**

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

**ADR-0005: State Encoding**
- **File:** `docs/adrs/0005-state-encoding.md`
- **Decision:** Ethereum ABI packed encoding
- **Rationale:**
  - Smart contract compatibility (L1 adjudicator)
  - Deterministic (same state → same bytes)
  - Standard format (cross-implementation compatibility)
- **Alternatives considered:** JSON (non-deterministic), RLP (Ethereum-specific), custom binary

**ADR-0006: ChannelId Generation**
- **File:** `docs/adrs/0006-channel-id-generation.md`
- **Decision:** `keccak256(abi.encodePacked(participants, nonce, appDef, challengeDuration))`
- **Rationale:**
  - Deterministic (same FixedPart → same ID)
  - Collision-resistant (256-bit hash)
  - Standard pattern from go-nitro/nitro-protocol
- **Alternatives considered:** Random UUID (non-deterministic), hash(participants+nonce) only (insufficient)

**Afternoon: Core Types (3-4 hours)**

**Create `src/state/types.zig`**

Define all core types:

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

Test construction, clone, invariants (see full test examples in Testing section below).

### ⚠️ CRITICAL: Memory Ownership Pattern

When testing structs that own allocated memory, follow this pattern:

```zig
test "example - struct owns allocated memory" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Allocate data
    const data = try allocator.dupe(u8, "test_value");

    // Create struct - transfers ownership to struct
    const s = MyStruct{
        .field = data,  // Struct now owns this memory
    };

    // CORRECT: Only defer struct.deinit()
    defer s.deinit(allocator);  // This will free 'data' internally

    // WRONG: defer allocator.free(data);  ← Double-free panic!
    // Reason: s.deinit() already frees it
}
```

**Structs with ownership in Phase 2:**
- `VariablePart.deinit(a)` frees `app_data` and calls `outcome.deinit(a)`
- `Allocation.deinit(a)` frees `metadata`
- `State.deinit(a)` frees `participants`, `app_data`, and calls `outcome.deinit(a)`
- `FixedPart.deinit(a)` frees `participants`
- `Outcome.deinit(a)` frees all `allocations` and their metadata

**Common double-free mistake:**
```zig
// ❌ WRONG - will panic with double-free
test "bad example - double free" {
    const data = try allocator.dupe(u8, "value");
    defer allocator.free(data);  // ❌ First free

    const s = MyStruct{ .field = data };
    defer s.deinit(allocator);   // ❌ Second free - PANIC!
}

// ✅ CORRECT - only free via struct
test "good example - single ownership" {
    const data = try allocator.dupe(u8, "value");
    const s = MyStruct{ .field = data };
    defer s.deinit(allocator);  // ✅ Struct owns and frees
    // NO defer allocator.free(data)
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

/// Generate deterministic ChannelId from FixedPart using Ethereum-compatible formula:
/// ChannelId = keccak256(abi.encodePacked(participants, nonce, appDef, challengeDuration))
///
/// This matches the Nitro Protocol and Ethereum L1 adjudicator contract.
/// Same FixedPart will always produce same ChannelId (deterministic).
/// 256-bit hash provides collision resistance.
pub fn channelId(fixed: FixedPart, allocator: std.mem.Allocator) !ChannelId {
    // Build array with all values: participants addresses + nonce + appDef + challengeDuration
    const num_values = fixed.participants.len + 3; // participants + 3 fixed fields
    var all_values = try allocator.alloc(abi.AbiValue, num_values);
    defer allocator.free(all_values);

    // Add each participant address individually
    for (fixed.participants, 0..) |addr, i| {
        const prim_addr = primitives.Address.Address{ .bytes = addr };
        all_values[i] = abi.addressValue(prim_addr);
    }

    // Add fixed fields after participants
    const app_addr = primitives.Address.Address{ .bytes = fixed.app_definition };
    all_values[fixed.participants.len] = abi.AbiValue{ .uint64 = fixed.channel_nonce };
    all_values[fixed.participants.len + 1] = abi.addressValue(app_addr);
    all_values[fixed.participants.len + 2] = abi.AbiValue{ .uint32 = fixed.challenge_duration };

    // Encode all values together
    const encoded = try abi.encodePacked(allocator, all_values);
    defer allocator.free(encoded);

    // Keccak256 hash
    return Hash.keccak256(encoded);
}
```

**Create `src/state/channel_id.test.zig`**

Test determinism and cross-impl vectors (see Testing section).

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

**End of Day 1:**

Run tests:
```bash
zig build test
```

Commit:
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

---

### Day 2: State Hashing + Signatures

**Morning: State Hashing (3 hours)**

**Create `src/state/hash.zig`**

State hashing using voltaire ABI encoding + Keccak256.

**Afternoon: Signatures (3 hours)**

**Create `src/crypto/signature.zig`**

Sign/verify using voltaire Crypto module.

**Create `src/crypto/signature.test.zig`**

Test signature roundtrip, recovery.

---

### Day 3: ABI Wrapper + Event Integration

**Create `src/abi/encoder.zig`**

Thin wrapper over voltaire AbiEncoding for state-specific encoding patterns.

**Update event emission**

Integrate State operations with P1 events (StateSigned, StateReceived).

---

### Day 4: Tests + Benchmarks + Demo

**Integration tests:** Full lifecycle (Create → Sign → Verify → Emit)
**Benchmarks:** Verify <1ms ChannelId, <2ms hash, <10ms sign+verify
**Demo:** Alice/Bob channel example
**Documentation:** Architecture docs, API reference

---

## Success Criteria (Day 4 Exit Gates)

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

### Pre-Commit Verification Checklist (MANDATORY)

**Run ALL checks before final commit:**

```bash
# 1. No debug prints in production code
grep -r "std.debug.print" src/state/ --exclude="*.test.zig"
# Expected: No results

grep -r "std.debug.print" src/crypto/ --exclude="*.test.zig"
# Expected: No results

grep -r "std.debug.print" src/abi/ --exclude="*.test.zig"
# Expected: No results

# 2. All tests pass
zig build test
# Expected: All tests passing

# 3. Golden vectors have actual hashes
grep -r "computed_by_test\|PLACEHOLDER\|TODO.*hash" testdata/
# Expected: No results

# 4. Event constructions have all required fields
zig build test 2>&1 | grep "missing field"
# Expected: No results (compilation succeeds)
```

**If ANY check fails, DO NOT commit. Fix issues first.**

---

## Zig 0.15 Constraints & API Changes

### ⚠️ CRITICAL: No Debug Prints in Production Code

**Rule:** NEVER use `std.debug.print` in production paths (`src/*/*.zig` except `*.test.zig`)

**Bad:**
```zig
// src/state/channel_id.zig
pub fn channelId(...) !ChannelId {
    const encoded = try abi.encodePacked(...);
    std.debug.print("Encoded: {any}\n", .{encoded});  // ❌ WRONG
    return Hash.keccak256(encoded);
}
```

**Good:**
```zig
// Only in test files if needed
test "channelId encoding" {
    if (builtin.mode == .Debug) {
        std.debug.print("Debug info\n", .{});  // ✅ OK in tests
    }
}
```

**Enforcement:** Final checklist before marking phase complete:
```bash
grep -r "std.debug.print" src/ --exclude="*.test.zig"  # Must return empty
```

### ArrayList API (0.14 vs 0.15)

Training data uses 0.14 syntax - **DO NOT use**:
```zig
var buffer = std.ArrayList(u8).init(allocator);  // ❌ Doesn't exist in 0.15
defer buffer.deinit();
return buffer.toOwnedSlice();
```

**Correct 0.15 syntax:**
```zig
var buffer = std.ArrayList(u8){};  // ✅ Correct
defer buffer.deinit(allocator);     // Pass allocator to deinit
return buffer.toOwnedSlice(allocator);  // Pass allocator
```

**All methods need allocator:** `append(alloc, ...)`, `appendSlice(alloc, ...)`, `deinit(alloc)`, `toOwnedSlice(alloc)`

### std.crypto native APIs

**std.crypto native:**
- `std.crypto.ecc.Secp256k1` - curve ops, basePoint
- `std.crypto.sign.ecdsa.EcdsaSecp256k1Sha256` - signing (NOT recovery)
- `std.crypto.hash.sha3.Keccak256` - Ethereum hash

**No recovery in stdlib** - need external lib (voltaire/primitives provides complete solution)

**u256:**
- Native: `u256` primitive (max u65535)
- Ethereum ABI: represent as `[32]u8` for encoding
- BigInt: `std.math.big.int.Managed` for arbitrary precision

**Rec:** Use voltaire/primitives (Ethereum ABI + secp256k1 recovery) - proven in guillotine-mini
**⚠️ Security:** Voltaire crypto marked UNAUDITED - use for testing/development, plan audit before production

## Summary

Channel state primitives: State/FixedPart/VariablePart structures, secp256k1 signatures, ABI encoding, ChannelId generation. Foundation for all protocols - without state types, cannot represent/verify channel updates. Preserves proven state channel model, replaces strings with tagged unions, integrates event sourcing.

## Objectives

- OBJ-1: State/FixedPart/VariablePart + ABI encoding
- OBJ-2: secp256k1 sign/verify with recovery
- OBJ-3: Keccak256 (Ethereum-compatible)
- OBJ-4: ChannelId generation (matches proven patterns)
- OBJ-5: Emit events for state operations

## Success Criteria

**Done when:**
- Types defined: State, FixedPart, VariablePart, Outcome, Signature
- ABI encoding byte-identical to reference implementations
- ChannelId 100% match to test vectors
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
- Why: Contract compat, deterministic, standard pattern vs ⚠️ complex (padding rules)

**ADR-0006: ChannelId Generation**
- Q: How compute ID?
- Opts: A) Hash(FixedPart) | B) Random UUID | C) Hash(Participants, Nonce)
- Rec: A (full FixedPart)
- Why: Deterministic, prevents collisions, standard pattern
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

// ⚠️ CRITICAL: ChannelId Encoding Order
// When generating ChannelId, encoding order MUST match Solidity:
//   keccak256(abi.encodePacked(participants, channelNonce, appDefinition, challengeDuration))
//
// In practice:
// 1. All participant addresses (20 bytes each, packed sequentially)
// 2. channel_nonce (uint64, 8 bytes)
// 3. app_definition (address, 20 bytes)
// 4. challenge_duration (uint32, 4 bytes)
//
// Order change breaks L1 adjudicator compatibility!

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

**STATUS:** Voltaire integrated ✅ | Ready for implementation

**W1:** ADRs, core types (State/FixedPart/VariablePart), ChannelId generation
**W2:** State hashing, sign/verify (using voltaire)
**W3:** Unit tests, event integration
**W4:** Cross-impl test vs reference implementations, benchmarks, demo

**Tasks:**
- T1: Write ADR-0004, 0005, 0006 (S, P0)
- T2: Define structs in src/state/types.zig (S, P0)
- T3: Define Outcome/Allocation/Signature (S, P0)
- T4: ChannelId generation using voltaire (M, P0)
- T5: State hashing using voltaire ABI (L, P0)
- T6: Sign creation using voltaire crypto (M, P0)
- T7: Verify/recovery using voltaire crypto (M, P0)
- T8: ABI encoding wrapper (thin wrapper over voltaire) (M, P0)
- T9: Event emission integration (M, P1)
- T10-13: Tests, benchmarks, docs

**Path:** T1 (ADRs) → T2-T3 (Types) → T4 (ChannelId) → T5 (Hashing) → T6-T7 (Signatures) → T8-T9 (ABI/Events) → T10-13 (Tests/Docs)

**Day 1 Target:** T1-T4 complete (ADRs, types, ChannelId with tests)
**Day 2 Target:** T5-T7 complete (hashing, signatures with tests)
**Day 3 Target:** T8-T9 complete (ABI wrapper, event emission)
**Day 4 Target:** T10-13 complete (full test suite, benchmarks, demo)

## Testing

**Unit:** 60+ tests, 90%+ cov
- ChannelId deterministic
- State hash deterministic
- Sig roundtrip correct
- ABI encoding byte-match
- Event emission complete

**Zig Memory Management in Tests:**

Critical pattern when testing structs with allocated fields:

```zig
test "struct with allocated memory" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Allocate data
    const data = try allocator.dupe(u8, "test_value");

    // Create struct (transfers ownership)
    const s = MyStruct{
        .field = data,  // Struct now owns this memory
    };

    // CORRECT: Only defer struct.deinit()
    defer s.deinit(allocator);  // This will free 'data'

    // WRONG: defer allocator.free(data);  ← Double-free panic!
}
```

**Common structs with ownership:**
- `VariablePart.deinit()` frees `app_data` and calls `outcome.deinit()`
- `Allocation.deinit()` frees `metadata`
- `State.deinit()` frees `participants`, `app_data`, calls `outcome.deinit()`
- `FixedPart.deinit()` frees `participants`
- `Outcome.deinit()` frees all `allocations` and their metadata

### Golden Test Vector Completeness

**CRITICAL:** Phase 1 had incomplete golden vectors (only 4/20 events had actual hashes).

**Requirements for Phase 2 golden vectors:**
- ✅ Schema files exist for all state operations
- ✅ Canonical test inputs provided
- ✅ **ACTUAL computed hashes stored** (not "computed_by_test" placeholder)
- ✅ Test verifies hash stability across runs

**How to generate actual hashes:**
```zig
// Temporary helper in types.test.zig (delete after golden vectors created)
test "generate golden hash for ChannelId" {
    const alice: types.Address = [_]u8{0xAA} ** 20;
    const bob: types.Address = [_]u8{0xBB} ** 20;

    const fixed = FixedPart{
        .participants = &[_]Address{alice, bob},
        .channel_nonce = 42,
        .app_definition = [_]u8{0x00} ** 20,
        .challenge_duration = 86400,
    };

    const id = try channelId(fixed, allocator);

    // Print hex for copying to golden file
    std.debug.print("ChannelId: 0x", .{});
    for (id) |b| std.debug.print("{x:0>2}", .{b});
    std.debug.print("\n", .{});
}
```

**Golden vector pattern:**
```json
{
  "description": "Standard 2-party channel",
  "inputs": {
    "participants": ["0xAAAA...", "0xBBBB..."],
    "channel_nonce": 42,
    "app_definition": "0x0000...",
    "challenge_duration": 86400
  },
  "expected_channel_id": "0x1234abcd..."
}
```

**Cross-Implementation Test Vector:**

Add this test to verify Zig matches Solidity:
```zig
test "ChannelId - matches Solidity reference implementation" {
    // Test vector from Ethereum contract
    // Inputs:
    //   participants: [0xAAAA...AAAA, 0xBBBB...BBBB] (20 bytes each)
    //   nonce: 42
    //   appDef: 0x0000...0000 (20 bytes)
    //   challengeDuration: 86400
    //
    // Expected ChannelId: 0x... (compute in Solidity, add here)

    const alice: types.Address = [_]u8{0xAA} ** 20;
    const bob: types.Address = [_]u8{0xBB} ** 20;
    // ... implementation

    // TODO: Replace with actual hash from Solidity contract
    const expected_id = [_]u8{0x00} ** 32; // PLACEHOLDER
    try testing.expectEqualSlices(u8, &expected_id, &computed_id);
}
```

Generate expected value by deploying test contract with same inputs.

**Integration:**
- Full lifecycle: Create → Sign → Verify → Emit → Reconstruct
- Cross-impl: Our encoding matches reference implementations byte-for-byte

**Benchmarks:**
- ChannelId: <1ms
- State hash: <2ms
- Sign+verify: <10ms P95

## Dependencies

**Req:** P1 (EventStore), Zig 0.15+
**External:** voltaire/primitives (https://github.com/evmts/primitives)
**Modules:** `primitives` (Address, AbiEncoding), `crypto` (secp256k1, Keccak256), `precompiles` (unused)
**Integration pattern:** See ../guillotine-mini/build.zig.zon for proven setup
**Local dev:** ../voltaire cloned locally for reference
**⚠️ Security:** Crypto implementation marked UNAUDITED by voltaire - acceptable for P2 testing, audit required for production

**Voltaire integration:**
```bash
# IMPORTANT: Fetch latest before starting (includes recent bug fixes)
zig fetch --save=primitives https://github.com/evmts/primitives/archive/refs/heads/main.tar.gz
zig build test  # Verify integration works
```

**build.zig pattern:**
```zig
const primitives_dep = b.dependency("primitives", .{
    .target = target,
    .optimize = optimize,
});
const primitives_mod = primitives_dep.module("primitives");
const crypto_mod = primitives_dep.module("crypto");
const precompiles_mod = primitives_dep.module("precompiles");

// Add to module imports
.imports = &.{
    .{ .name = "primitives", .module = primitives_mod },
    .{ .name = "crypto", .module = crypto_mod },
    .{ .name = "precompiles", .module = precompiles_mod },
},
```

**Code usage:**
```zig
const primitives = @import("primitives");
const crypto_pkg = @import("crypto");
const Address = primitives.Address.Address;
const Hash = crypto_pkg.Hash;
const Crypto = crypto_pkg.Crypto;
const abi = primitives.AbiEncoding;

// ChannelId = keccak256(encodePacked(fixedPart))
const encoded = try abi.encodePacked(allocator, &abi_values);
const channel_id = Hash.keccak256(encoded);

// Sign state hash
const sig = try Crypto.unaudited_signHash(state_hash, private_key);

// Recover signer
const addr = try Crypto.unaudited_recoverAddress(state_hash, signature);
```

## Risks

|Risk|P|I|Mitigation|
|--|--|--|--|
|ABI encoding bugs|M|H|Cross-test vs reference implementations, contract vectors|
|Sig verify wrong recovery|M|H|Test vs ethers.js, proven lib|
|Keccak256 incorrect|L|H|Use tested lib (voltaire)|
|Voltaire crypto unaudited|L|M|Explicitly mark P2 as development/testing only; document audit requirement for production|
|secp256k1 integration complex|M|M|2 days allocated, test thoroughly|

## Deliverables

**Code:** `src/state/{types,channel_id,hash}.zig`, `src/crypto/signature.zig`, `src/abi/encoder.zig`, tests
**Docs:** ADR-0004/0005, arch docs (state structure, signatures, ABI), API ref
**Val:** 90%+ cov, cross-impl match, benchmarks met

## Validation Gates

- G1: ADRs approved, API designed, voltaire integrated
- G2: Code review (2+), tests pass, 90%+ cov
- G3: Cross-impl passes, benchmarks met, events work
- G4: Demo complete, docs published, P3 unblocked

## Refs

**Phases:** P1 (Events)
**ADRs:** 0004 (Sig), 0005 (ABI), 0006 (ChannelId)
**External:** State channel implementations, Ethereum ABI spec, EIP-191, secp256k1 spec
**Reference Implementation:** ../guillotine-mini - proven voltaire integration
**Voltaire Examples:** ../voltaire/examples/signature_recovery.zig - secp256k1 usage patterns

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

---

## CONTEXT FROM PHASE 1 (Event Surface)

**Phase 1 Status:** Event types defined ✅ | EventStore implementation → Phase 1b (pending)

### Event Types Already Defined

Phase 1 delivered **20 events** including state-related events relevant to this phase:

**Channel State Events (use these):**
- [`channel-created`](../../schemas/events/channel-created.schema.json) - Emitted when ChannelId derived from FixedPart
- [`state-signed`](../../schemas/events/state-signed.schema.json) - Emitted when local party signs state
- [`state-received`](../../schemas/events/state-received.schema.json) - Emitted when remote state received/validated
- [`state-supported-updated`](../../schemas/events/state-supported-updated.schema.json) - Emitted when supported turn advances

**Implementation:**
- Event types: [src/event_store/events.zig](../../src/event_store/events.zig)
- Event schemas: [schemas/events/](../../schemas/events/)
- Event catalog: [docs/architecture/event-types.md](../../docs/architecture/event-types.md)

### Event Field Completeness (CRITICAL)

**When Event Schemas Change:**

If Phase 1 event schemas are updated, you MUST update ALL test usages:

```bash
# Find all test event constructions
grep -rn "\.state_signed = \." src/ --include="*.test.zig"
grep -rn "\.channel_created = \." src/ --include="*.test.zig"
```

**Common missing fields after schema updates:**
- `StateSignedEvent`: `is_final`, `app_data_hash`
- `ObjectiveCrankedEvent`: `waiting` (not just `side_effects_count`)
- `ChannelCreatedEvent`: `app_definition`
- `StateReceivedEvent`: `signer`, `signature`, `is_final`, `peer_id`

**Pattern:** After importing event types, run `zig build test` immediately to catch missing fields.

**Example from Phase 1 cleanup:**
```zig
// ❌ WRONG - missing required fields
const event = Event{ .state_signed = .{
    .channel_id = id,
    .turn_num = 0,
    .state_hash = hash,
    // Missing: is_final, app_data_hash, signer, signature
}};

// ✅ CORRECT - all required fields
const event = Event{ .state_signed = .{
    .event_version = 1,
    .timestamp_ms = @intCast(std.time.milliTimestamp()),
    .channel_id = id,
    .turn_num = 0,
    .state_hash = hash,
    .signer = alice,
    .signature = sig,
    .is_final = false,
    .app_data_hash = null,
}};
```

### Integration Requirements for Phase 2

**When implementing State operations:**

1. **ChannelId Generation:**
   ```zig
   pub fn channelId(self: FixedPart, a: Allocator) !ChannelId {
       // 1. ABI encode FixedPart
       // 2. Keccak256 hash
       // 3. Emit channel-created event
       const id = keccak256(abi_encoded);
       try emitChannelCreated(event_store, self, id, a);
       return id;
   }
   ```

2. **State Signing:**
   ```zig
   pub fn sign(self: State, a: Allocator, pk: [32]u8) !Signature {
       const state_hash = try self.hash(a);
       const sig = try signEthereumMessage(state_hash, pk);
       // Emit state-signed event
       try emitStateSigned(event_store, self, sig, a);
       return sig;
   }
   ```

3. **State Reception:**
   ```zig
   pub fn recoverSigner(self: State, a: Allocator, sig: Signature) !Address {
       const state_hash = try self.hash(a);
       const addr = try recoverEthereumMessageSigner(state_hash, sig);
       // Emit state-received event (if from remote peer)
       try emitStateReceived(event_store, self, sig, addr, a);
       return addr;
   }
   ```

**Event Emission Pattern:**
```zig
pub fn emitStateSigned(
    store: *EventStore,  // From Phase 1b (when implemented)
    state: State,
    sig: Signature,
    a: Allocator
) !void {
    const event = Event{
        .state_signed = .{
            .event_version = 1,
            .timestamp_ms = @intCast(std.time.milliTimestamp()),
            .channel_id = try state.channelId(a),
            .turn_num = state.turn_num,
            .state_hash = try state.hash(a),
            .signer = try state.recoverSigner(a, sig),
            .signature = sig.toBytes(),
            .is_final = state.is_final,
            .app_data_hash = if (state.app_data.len > 0) 
                keccak256(state.app_data) else null,
        },
    };
    _ = try store.append(event);
}
```

### State Hashing Must Match Event ID Approach

Phase 1 established canonical serialization for event IDs:
- Sorted keys (lexicographic)
- No whitespace
- Keccak256 hashing

**State.hash() should use similar approach:**
```zig
pub fn hash(self: State, a: Allocator) !Bytes32 {
    // 1. ABI encode State (deterministic, sorted)
    // 2. Keccak256 hash
    // 3. Result must be reproducible (same state → same hash)
    const encoded = try abiEncode(a, self);
    defer a.free(encoded);
    return keccak256(encoded);
}
```

**Consistency requirement:** If state is reconstructed from events, hashing it should produce same state_hash as stored in `state-signed` event.

### Test Vectors Available

Use existing golden vectors to verify compatibility:
- [testdata/events/state-signed.golden.json](../../testdata/events/state-signed.golden.json)
- Contains example state_hash, signature, channel_id values
- Phase 2 implementation should produce byte-identical hashes

### Validation Hooks

State validation can reference event history:
```zig
pub fn validate(state: State, ctx: ValidationContext) !void {
    // Check if channel exists (via event log query)
    const channel_events = try ctx.getChannelEvents(state.channelId());
    if (channel_events.len == 0) return error.ChannelNotFound;
    
    // Check turn progression (vs latest state-signed event)
    const latest = ctx.getLatestSignedTurn(state.channelId());
    if (state.turn_num <= latest) return error.InvalidTurnProgression;
}
```

### Files to Reference

**Phase 1 Deliverables:**
- Event definitions: [src/event_store/events.zig](../../src/event_store/events.zig)
- ID derivation (for consistency): [src/event_store/id.zig](../../src/event_store/id.zig)
- Event schemas: [schemas/events/state-*.schema.json](../../schemas/events/)
- Documentation: [docs/architecture/event-types.md](../../docs/architecture/event-types.md)

**Don't Re-implement:**
- Event types (already exist)
- Event ID derivation (use existing keccak256 approach)
- Canonical JSON serialization (exists in id.zig)

**Do Implement:**
- State/FixedPart/VariablePart types (new in P2)
- ABI encoding (Ethereum-specific, different from JSON)
- secp256k1 signatures (new in P2)
- Event emission helpers (bridge between State and Event types)

---

**Context Added:** 2025-11-08  
**Phase 1 Status:** Events defined, EventStore pending Phase 1b
