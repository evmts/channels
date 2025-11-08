# go-nitro API Reference

go-nitro API patterns for Zig implementation reference.

## Node Init

<node-init>
**go-nitro:**
```go
nitroNode := nc.New(msgService, chain, store, logDest, policy, metrics)
```

**Our Zig:**
```zig
const Node = struct {
    allocator: Allocator,
    msg_service: *MessageService,
    chain_service: *ChainService,
    event_store: *EventStore,  // Event-sourced vs snapshot store
    policy: Policy,

    pub fn init(allocator: Allocator, config: NodeConfig) !*Node;
};
```

**Diff:** EventStore (event log source-of-truth) vs Store (snapshots)
</node-init>

## Ledger Channels

<ledger-api>
**go-nitro:**
```go
resp := node.CreateLedgerChannel(counterparty, challengeDuration, outcome)
// Returns: {ChannelId, ObjectiveId}
node.WaitForCompletedObjective(resp.ObjectiveId)
```

**Flow:** DirectFund obj→prefund states (off-chain)→deposits (on-chain)→postfund states→ready

**Our Zig:**
```zig
pub fn createLedgerChannel(
    self: *Node,
    counterparty: Address,
    challenge_duration: u32,
    outcome: Outcome,
) !CreateChannelResponse; // {channel_id, objective_id}

pub fn waitForObjective(
    self: *Node,
    objective_id: ObjectiveId,
    timeout: ?u64,
) !ObjectiveStatus;
```
</ledger-api>

## Virtual Channels

<virtual-api>
**go-nitro:**
```go
resp := node.CreateVirtualPaymentChannel(
    intermediaries []Address,  // Hub path
    counterparty Address,
    challengeDuration uint32,
    outcome Outcome,
)
```

**Flow:** VirtualFund obj→3-party (A-H-B) prefund sigs→ledger guarantees (off-chain)→postfund→ready (NO on-chain txs)

**Our Zig:**
```zig
pub fn createVirtualChannel(
    self: *Node,
    intermediaries: []const Address,  // len=1: single hub, len>1: multi-hop
    counterparty: Address,
    challenge_duration: u32,
    outcome: Outcome,
) !CreateChannelResponse;
```
</virtual-api>

## Payments

<payment-api>
**go-nitro:**
```go
node.Pay(channelId, amount)  // Creates signed voucher
```

**Flow:** Create voucher (incremented amount)→send P2P→counterparty validates+stores→no blockchain

**Our Zig:**
```zig
pub fn pay(self: *Node, channel_id: ChannelId, amount: u256) !Voucher;
pub fn receiveVoucher(self: *Node, voucher: Voucher) !void;

pub const Voucher = struct {
    channel_id: ChannelId,
    amount: u256,
    signature: Signature,
    pub fn validate(self: Voucher, expected_signer: Address) !void;
};
```
</payment-api>

## Channel Closing

<close-api>
**Virtual:**
```go
resp := node.CloseVirtualChannel(channelId)
```
Flow: VirtualDefund→finalize virtual state→resolve vouchers→update ledgers (remove guarantees)→defunded (off-chain)

**Ledger:**
```go
resp := node.CloseChannel(channelId)
```
Flow: DirectDefund→finalize→submit conclusion (on-chain)→withdraw assets→closed

**Our Zig:**
```zig
pub fn closeVirtualChannel(self: *Node, channel_id: ChannelId) !CloseChannelResponse;
pub fn closeLedgerChannel(self: *Node, channel_id: ChannelId) !CloseChannelResponse;
pub const CloseChannelResponse = struct { objective_id: ObjectiveId };
```
</close-api>

## RPC API

<rpc-api>
**go-nitro Methods** (`/packages/nitro-rpc-client/src/interface.ts`):

**Ledger:** CreateLedgerChannel, GetLedgerChannel, CloseLedgerChannel
**Payment:** CreatePaymentChannel, GetPaymentChannel, ClosePaymentChannel
**Pay:** Pay, ReceiveVoucher, GetPaymentChannelsByLedger
**Info:** GetAddress, GetSigningAddress, GetAllLedgerChannels, GetNodeInfo, GetVersion

**Our Zig (http.zig):**
```zig
pub fn serveRPC(node: *Node, config: RPCConfig) !void {
    const server = try http.Server.init(config.allocator, .{.port = config.port});
    try server.route("POST", "/api/ledger/create", handleCreateLedger);
    try server.route("POST", "/api/virtual/create", handleCreateVirtual);
    try server.route("POST", "/api/pay", handlePay);
    try server.route("GET", "/api/channels", handleGetChannels);
    try server.listen();
}
```

**JSON-RPC 2.0:**
```zig
pub const RPCRequest = struct {
    jsonrpc: []const u8 = "2.0",
    method: []const u8,
    params: json.Value,
    id: union(enum) { number: i64, string: []const u8 },
};
```
</rpc-api>

## Events/Notifications

<notifications>
**go-nitro:**
```ts
on('objective_completed', (id) => {})
on('payment_received', (voucher) => {})
on('ledger_channel_updated', (id, info) => {})
```

**Our Zig WebSocket:**
```zig
pub const Notification = union(enum) {
    objective_completed: struct { objective_id: ObjectiveId, status: ObjectiveStatus },
    payment_received: struct { channel_id: ChannelId, amount: u256 },
    channel_updated: struct { channel_id: ChannelId, turn_num: u64 },
    pub fn toJSON(self: Notification, allocator: Allocator) ![]const u8;
};
```
</notifications>

## Errors

<errors>
**go-nitro:**
```go
type APIError struct { Code int, Message string }
// ErrChannelNotFound, ErrInvalidOutcome, ErrInsufficientFunds, ErrObjectiveNotApproved
```

**Our Zig:**
```zig
pub const NodeError = error{
    ChannelNotFound, ObjectiveNotFound, InvalidOutcome, InsufficientFunds,
    InvalidSignature, ObjectiveNotApproved, EventStoreError, DerivationError,
    ChainServiceError, MessageServiceError, Timeout,
};
```
</errors>

## Integration Test Pattern

<test-pattern>
**go-nitro** (`/node_test/integration_test.go`):
```go
// 1. Setup: chain, msgService
// 2. Create nodes: alice, bob, hub
// 3. Peer discovery: waitForPeers
// 4. Ledger channels: alice-hub, bob-hub (CreateLedger + Wait)
// 5. Virtual: alice-bob via hub (CreateVirtual + Wait)
// 6. Payments: alice.Pay(id, amount) x10
// 7. Close virtual: CloseVirtual + Wait
// 8. Verify: balances changed correctly
```

**Our Zig:**
```zig
test "virtual payment with hub" {
    const allocator = testing.allocator;
    const chain = try MockChain.init(allocator);
    const msg = try TestMessageService.init(allocator);

    var alice = try createTestNode(allocator, "Alice", chain, msg);
    var bob = try createTestNode(allocator, "Bob", chain, msg);
    var hub = try createTestNode(allocator, "Hub", chain, msg);

    const alice_hub = try alice.createLedgerChannel(hub.address, 86400, outcome(100,100));
    try alice.waitForObjective(alice_hub.objective_id, 5000);

    const alice_bob = try alice.createVirtualChannel(&[_]Address{hub.address}, bob.address, 86400, outcome(10,10));
    try alice.waitForObjective(alice_bob.objective_id, 5000);

    var i: usize = 0;
    while (i < 10) : (i += 1) _ = try alice.pay(alice_bob.channel_id, 5);

    const close = try alice.closeVirtualChannel(alice_bob.channel_id);
    try alice.waitForObjective(close.objective_id, 5000);

    try testing.expectEqual(@as(u256, 90), alice.getBalance());
    try testing.expectEqual(@as(u256, 110), bob.getBalance());
}
```
</test-pattern>

## Design Principles

<principles>
**go-nitro (preserve):**
1. Async ops (return ObjectiveId immediately)
2. Wait pattern (WaitForCompletedObjective for sync)
3. Separation (ledger vs virtual distinct APIs)
4. Simplicity (high-level hides protocol complexity)
5. Type safety (strong typing for addresses/IDs/outcomes)

**Our Zig improvements:**
1. Event-sourced state (ops append events, not mutate)
2. Explicit errors (error unions vs exceptions)
3. Memory safety (explicit allocators, no GC)
4. Comptime (generic protocols via comptime)
5. Async/await (structured concurrency vs goroutines)
</principles>

## Refs

<references>
- Node API: `/go-nitro/node/node.go`
- RPC: `/go-nitro/packages/nitro-rpc-client/src/{interface,types}.ts`
- Tests: `/go-nitro/node_test/integration_test.go`
- README: `/go-nitro/node/readme.md`
</references>
