# P7: Chain Service

**Meta:** P7 | Deps: P2, P3 | Owner: Core

## Zig Ethereum RPC

**std.http client:**
- Built-in HTTP client/server in std
- Needs allocator pre-allocated for response body
- `std.json` for request/response parsing

**zabi (RECOMMENDED):**
- Full Ethereum lib: RPC, ABI, RLP, tx parsing, wallet
- Custom JSON parser for RPC runtime deser/ser
- Already includes secp256k1 + Keccak (dep for P2)

**JSON-RPC libs:**
- `zigjr` - lightweight JSON-RPC 2.0 (std.json)
- `zig-json-rpc` - protocol impl
- Roll own with std.http + std.json (more work)

**Rec:** Use zabi - covers P2 (crypto) + P7 (RPC) in one dep

## Summary

Ethereum chain integration - deposit detection, tx submission, event listening, challenge handling. Critical - channels need on-chain funding/finalization. RPC client, event subscriptions, tx building, reorg handling. Replaces P3 mock chain with real Ethereum connection.

## Objectives

- OBJ-1: Ethereum RPC client (read/write ops)
- OBJ-2: Event listening (Deposited, ChallengeRegistered, Concluded)
- OBJ-3: Tx submission (deposit, conclude, challenge)
- OBJ-4: Reorg handling (confirmation depth)
- OBJ-5: Integration with Objective side effects

## Success Criteria

**Done when:**
- RPC client works (query block/balance) 100%
- Events detected (<5s latency)
- Tx submission works (correct nonce/gas)
- Reorgs handled (re-emit events)
- Integration: DirectFund deposits detected
- 60+ tests, 90%+ cov
- ADR approved (confirmation depth)
- Docs + demo

**Exit gates:** Tests pass, integration (deposit→detect)

## Architecture

**Components:** RpcClient (JSON-RPC calls), EventListener (subscribe to contracts), TxBuilder (construct signed txs), ChainService (high-level API)

**Flow:**
```
Objective → SideEffect{SubmitTx} → TxBuilder → RpcClient → Ethereum
Ethereum → Event → EventListener → ChainService → Objective
```

## ADRs

**ADR-0012: Confirmation Depth**
- Q: When trust event?
- Opts: A) 0 blocks | B) 1 block | C) 12 blocks
- Rec: C (12 blocks)
- Why: Reorg safety, industry standard vs ⚠️ latency (ok <3min)

## Data Structures

```zig
pub const ChainService = struct {
    rpc: *RpcClient,
    listener: *EventListener,
    adjudicator: Address,
    signer: [32]u8,

    pub fn deposit(self: *Self, channel_id: ChannelId, amount: u256) !TxHash;
    pub fn conclude(self: *Self, state: SignedState) !TxHash;
    pub fn onDeposited(self: *Self, callback: DepositCallback) !void;
};

pub const RpcClient = struct {
    endpoint: []const u8,

    pub fn getBlock(self: *Self, num: u64) !Block;
    pub fn sendTransaction(self: *Self, tx: Transaction) !TxHash;
};
```

## APIs

```zig
// Init chain service
pub fn init(
    rpc_url: []const u8,
    adjudicator: Address,
    signer: [32]u8,
    a: Allocator
) !*ChainService;

// Submit deposit tx
pub fn deposit(self: *ChainService, channel_id: ChannelId, amount: u256) !TxHash;

// Subscribe to Deposited events
pub fn onDeposited(self: *ChainService, callback: DepositCallback) !void;
```

## Implementation

**W1:** RPC client + tx building + basic events
**W2:** Event listening + confirmation tracking + reorg handling
**W3:** Objective integration + testing + validation

**Tasks:** T1: RPC client (L) | T2: Tx building (M) | T3: Event listener (L) | T4: Confirmation tracking (M) | T5: Reorg detection (M) | T6: Objective integration (M) | T7: Test local node (L) | T8: Test reorgs (M)

**Path:** T1→T2→T3→T4→T6→T7

## Testing

**Unit:** 60+ tests
- RPC queries block
- Deposit tx correct calldata
- Events detected

**Integration:**
- Local anvil node + deployed contracts
- Submit deposit → wait 12 blocks → event detected

**Reorg:**
- Emit event block 100 → fork block 99 → event re-emitted

## Dependencies

**Req:** P2 (State/Sig), P3 (Objectives), Zig 0.15+
**External:** zabi (RPC + tx + ABI), Ethereum node (Geth/Anvil), op-stack compatible adjudicator contracts
**Alt:** std.http + std.json + JSON-RPC lib (fragmented, more work)

## Risks

|Risk|P|I|Mitigation|
|--|--|--|--|
|RPC connection failures|M|H|Retry logic, multiple endpoints|
|Reorg complexity|M|H|Confirmation depth, extensive tests|
|Tx nonce management|M|M|Track pending txs, nonce queuing|
|Event missed (restart)|M|H|Persist last block, backfill|
|Gas estimation issues|M|M|Conservative limits, allow override|

## Deliverables

**Code:** `src/chain/{rpc,events,service}.zig`, tests
**Docs:** ADR-0012, `docs/architecture/chain-service.md`
**Val:** 90%+ cov, integration passes (local node)

## Validation Gates

- G1: ADR approved, RPC working, txs buildable
- G2: Code review, event listening works
- G3: Integration passes (deposit→detect)
- G4: Docs complete, P8 unblocked

## Refs

**Phases:** P2 (State), P3 (Objectives)
**ADRs:** 0012 (Confirmation depth)
**External:** State channel chain integration patterns, Ethereum JSON-RPC, op-stack compatible contracts

## Example

```zig
// Init chain service
var chain = try ChainService.init(
    "http://localhost:8545",
    adjudicator,
    private_key,
    allocator
);
defer chain.deinit();

// Deposit
const tx_hash = try chain.deposit(channel_id, 100);

// Listen for deposits
try chain.onDeposited(handleDeposit);
```
