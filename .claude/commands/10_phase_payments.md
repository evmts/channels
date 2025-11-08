# P10: Payments

**Meta:** P10 | Deps: P9 | Owner: Core

## Summary

Payment vouchers - atomic value transfer within virtual channels. Vouchers = signed commitments to pay, validated against channel state, resolved during defund. Critical for payment use cases - without vouchers, channels only support final settlement. Simple protocol: create voucher → validate → accumulate → settle on defund. Follows proven payment voucher patterns.

## Objectives

- OBJ-1: Payment voucher creation and signing
- OBJ-2: Voucher validation (amount available, signature correct)
- OBJ-3: Voucher accumulation (track total paid)
- OBJ-4: Payment resolution during defund (update final outcome)
- OBJ-5: Integration with virtual channels

## Success Criteria

**Done when:**
- Voucher creation works (create + sign) valid voucher
- Validation rejects invalid (insufficient funds, wrong sig) 100%
- Accumulation correct (multiple vouchers sum matches)
- Resolution updates outcome (defund with payments correct balances)
- Perf: <1s for 1000 vouchers
- 40+ tests, 90%+ cov
- Docs + demo

**Exit gates:** Tests pass, integration (payments in virtual channel)

## Data Structures

```zig
pub const Voucher = struct {
    channel_id: ChannelId,
    amount: u256,
    nonce: u64,                // Prevent replay
    signature: Signature,

    pub fn create(channel_id: ChannelId, amount: u256, nonce: u64, pk: [32]u8, a: Allocator) !Voucher;
    pub fn hash(self: Voucher, a: Allocator) !Bytes32;
    pub fn verify(self: Voucher, payer: Address, a: Allocator) !bool;
};

pub const VoucherManager = struct {
    channel_id: ChannelId,
    received: ArrayList(Voucher),
    total_received: u256,
    next_nonce: u64,

    pub fn validate(self: *Self, voucher: Voucher, channel: Channel) !void;
    pub fn add(self: *Self, voucher: Voucher) !void;
    pub fn totalReceived(self: Self) u256;
};

pub const PaymentResolver = struct {
    pub fn resolvePayments(vouchers: []Voucher, original: Outcome, a: Allocator) !Outcome;
};
```

## APIs

```zig
// Create voucher
pub fn createVoucher(
    channel_id: ChannelId,
    amount: u256,
    nonce: u64,
    payer_key: [32]u8,
    a: Allocator
) !Voucher;

// Validate voucher
pub fn validate(voucher: Voucher, channel: Channel, payer: Address, a: Allocator) !void;

// Resolve to final outcome
pub fn resolvePayments(vouchers: []Voucher, original: Outcome, a: Allocator) !Outcome;
```

## Implementation

**W1:** Voucher design + creation + validation + voucher manager
**W2:** Payment resolution + defund integration + testing + validation

**Tasks:** T1: Voucher struct (S) | T2: Create + sign (M) | T3: Validation (M) | T4: VoucherManager (M) | T5: PaymentResolver (M) | T6: Unit tests (M) | T7: Integration (L) | T8: Benchmarks (S)

**Path:** T1→T2→T3→T4→T5→T7

## Testing

**Unit:** 40+ tests
- Create valid voucher
- Validation rejects insufficient funds
- Resolution updates outcome correctly

**Integration:**
- Payments in virtual channel
- Alice sends 3 vouchers to Bob → Bob accumulates → defund → balances correct

## Dependencies

**Req:** P2 (Signatures), P5 (Defund for resolution), P9 (Virtual channels)

## Risks

|Risk|P|I|Mitigation|
|--|--|--|--|
|Voucher replay attacks|L|H|Nonce validation, extensive tests|
|Double-spending|L|H|Validation checks, accumulation logic|
|Resolution bugs (wrong outcome)|M|H|Unit tests, cross-check reference implementations|
|Performance (many vouchers)|L|M|Benchmark, acceptable if <1s for 1000|

## Deliverables

**Code:** `src/payment/{voucher,manager,resolver}.zig`, tests
**Docs:** `docs/protocols/payments.md`
**Val:** 90%+ cov, integration passes

## Validation Gates

- G1: Voucher design reviewed, validation logic specified
- G2: Code review, tests pass
- G3: Integration passes (payments in virtual)
- G4: Docs complete, P11 unblocked

## Refs

**Phases:** P2 (Sig), P5 (Defund), P9 (Virtual)
**External:** Payment channel voucher patterns, payment app contracts

## Example

```zig
// Alice creates voucher to pay Bob
const voucher = try alice.createVoucher(
    channel_id,
    amount = 10,
    nonce = alice.nextNonce(),
);

// Send to Bob (off-chain)
try alice.sendVoucher(bob_addr, voucher);

// Bob validates + tracks
try bob.receiveVoucher(voucher);

// On defund: payments resolved automatically
try alice.defundChannel(channel_id);
```
