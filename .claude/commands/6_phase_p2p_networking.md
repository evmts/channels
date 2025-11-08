# P6: P2P Networking

**Meta:** P6 | Deps: P2, P3 | Owner: Core

## Summary

Peer-to-peer messaging layer - direct message exchange between participants. Transport (TCP or libp2p), message codec (serialization), peer discovery, delivery guarantees. Critical - protocols need to exchange signed states. Replaces P3/P5 mock message service with real network stack.

## Objectives

- OBJ-1: Transport layer (TCP or libp2p)
- OBJ-2: Message codec (serialize/deserialize Protocol Messages)
- OBJ-3: Peer connectivity (dial/listen/connections)
- OBJ-4: Delivery guarantees (acks, retries, ordering)
- OBJ-5: Integration with Objective side effects

## Success Criteria

**Done when:**
- Send/receive works (2 nodes, 100% delivery)
- Codec roundtrips all message types 100%
- Connection reliability (network partition → auto reconnect)
- Perf: <50ms P95 latency for 1000 messages
- Integration: DirectFund completes over network
- 70+ tests, 90%+ cov
- 2 ADRs approved (transport, codec)
- Docs + demo

**Exit gates:** Tests pass, integration (2+ nodes communicate), benchmarks met

## Architecture

**Components:** Transport (TCP/libp2p connections), MessageCodec (serialize messages), PeerManager (track connections), MessageRouter (route to objectives)

**Flow:**
```
Objective → SideEffect{SendMessage} → Codec → Transport → Network
Network → Transport → Codec → Router → Objective
```

## ADRs

**ADR-0010: Transport Protocol**
- Q: TCP or libp2p?
- Opts: A) Raw TCP | B) libp2p | C) QUIC
- Rec: A (TCP initially), B (libp2p P12)
- Why: Simpler, defer NAT/discovery complexity vs ⚠️ limited features (ok for testing)

**ADR-0011: Message Codec**
- Q: Serialization format?
- Opts: A) JSON | B) MessagePack | C) Protobuf
- Rec: B
- Why: Compact, fast, Zig support vs ⚠️ not human-readable (ok debug tools)

## Data Structures

```zig
pub const Message = union(enum) {
    propose_state: ProposeStateMessage,
    accept_state: AcceptStateMessage,
    reject_proposal: RejectProposalMessage,

    pub fn encode(self: Message, a: Allocator) ![]u8;
    pub fn decode(bytes: []const u8, a: Allocator) !Message;
};

pub const ProposeStateMessage = struct {
    channel_id: ChannelId,
    state: State,
    signature: Signature,
};

pub const P2PService = struct {
    transport: *Transport,
    peers: PeerManager,
    router: MessageRouter,

    pub fn sendMessage(self: *Self, to: Address, msg: Message) !void;
    pub fn onMessage(self: *Self, callback: MessageCallback) !void;
};
```

## APIs

```zig
// Init P2P service
pub fn init(listen_addr: []const u8, a: Allocator) !*P2PService;

// Send message to peer
pub fn sendMessage(self: *P2PService, peer: Address, msg: Message) !void;

// Subscribe to messages
pub fn onMessage(self: *P2PService, callback: MessageCallback) !void;
```

## Implementation

**W1:** Message types + codec + TCP transport basics
**W2:** Connection mgmt + routing + reliability (acks/retries)
**W3:** Integration with objectives + testing + validation

**Tasks:** T1: Message types (M) | T2: MessagePack codec (M) | T3: TCP transport (L) | T4: Connection mgmt (M) | T5: Routing (M) | T6: Acks/retries (M) | T7: Peer discovery (M) | T8: Objective integration (L) | T9: Network tests (L)

**Path:** T1→T2→T3→T4→T5→T8→T9

## Testing

**Unit:** 70+ tests
- Message codec roundtrip correct
- TCP connection established
- Acks/retries work

**Integration:**
- DirectFund over network (no manual message passing)
- Alice creates channel → Bob receives prefund over P2P

**Benchmarks:**
- 1000 messages: <50ms P95 latency

## Dependencies

**Req:** P2 (State/Sig for messages), P3 (Objective side effects)
**External:** Zig std.net (TCP), MessagePack library

## Risks

|Risk|P|I|Mitigation|
|--|--|--|--|
|TCP connection issues|M|M|Test edge cases, reconnect logic|
|Message loss|M|H|Acks + retries, sequence numbers|
|Codec bugs (deserialize)|M|M|Fuzz testing, schema validation|
|NAT traversal needed|H|M|Defer P12 (libp2p), use relay|

## Deliverables

**Code:** `src/p2p/{transport,codec,service}.zig`, tests
**Docs:** ADR-0010/0011, `docs/architecture/p2p.md`
**Val:** 90%+ cov, integration passes, benchmarks met

## Validation Gates

- G1: ADRs approved, message types defined, TCP working
- G2: Code review, routing works
- G3: Integration passes (DirectFund over network)
- G4: Docs complete, P7 unblocked

## Refs

**Phases:** P2 (State), P3 (Objectives)
**ADRs:** 0010 (Transport), 0011 (Codec)
**External:** go-nitro `/node/engine/messageservice/`, libp2p

## Example

```zig
// Init P2P
var p2p = try P2PService.init("0.0.0.0:5000", allocator);
defer p2p.deinit();

// Send message
const msg = Message{
    .propose_state = .{ .channel_id = id, .state = state, .signature = sig },
};
try p2p.sendMessage(peer_addr, msg);

// Receive
try p2p.onMessage(handleMessage);
```
