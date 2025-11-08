# Event Surface Area: P1 Event Sourcing Foundation

**Version:** 1.0
**Date:** 2025-11-08
**Status:** Implemented

---

## Overview

This document defines the complete event surface for Phase 1: Event Sourcing Foundation. Events are the **sole source of truth** for all state transitions in the state channel engine. Each event has:

- **Unique ID**: Deterministically derived via `keccak256("ev1|" + event_name + "|" + canonical_json)`
- **Immutable payload**: JSON Schema validated
- **Causal rules**: Preconditions and postconditions enforcing state invariants
- **Version**: Schema versioning for forward compatibility

## Event Catalog

20 events across 4 domains:

| Domain             | Count | Events                                                                 |
| ------------------ | ----- | ---------------------------------------------------------------------- |
| Objective Lifecycle | 5     | created, approved, rejected, cranked, completed                        |
| Channel State       | 5     | created, state-signed, state-received, supported-updated, finalized    |
| Chain Bridge        | 6     | deposit, allocation, challenge-registered/cleared, concluded, withdraw |
| Messaging           | 4     | sent, received, acked, dropped                                         |

## Event Definitions

### 1. Objective Lifecycle Events

#### 1.1 `objective-created`

**Purpose:** Spawns new objective in engine (DirectFund, DirectDefund, VirtualFund, VirtualDefund).

| Field           | Type                           | Description                               |
| --------------- | ------------------------------ | ----------------------------------------- |
| event_version   | u8                             | Schema version (1)                        |
| timestamp_ms    | u64                            | Unix timestamp (milliseconds)             |
| objective_id    | [32]u8                         | Unique objective identifier               |
| objective_type  | enum                           | DirectFund\|DirectDefund\|Virtual...      |
| channel_id      | [32]u8                         | Associated channel                        |
| participants    | [][20]u8                       | Ordered participant addresses (2-255)     |

**Causal Rules:**
- **Pre:** `objective_id` must be globally unique (checked by store).
- **Post:** Objective exists in `unapproved` state; awaiting policymaker decision.

**ID Derivation:** `keccak256("ev1|objective-created|" + canonical_json(payload))`

**Schema:** [schemas/events/objective-created.schema.json](../../schemas/events/objective-created.schema.json)

---

#### 1.2 `objective-approved`

**Purpose:** Policymaker approves objective; transitions to active processing.

| Field         | Type       | Description                    |
| ------------- | ---------- | ------------------------------ |
| event_version | u8         | 1                              |
| timestamp_ms  | u64        |                                |
| objective_id  | [32]u8     | Objective being approved       |
| approver      | ?[20]u8    | Optional approving party addr  |

**Causal Rules:**
- **Pre:** Objective exists in `unapproved` state.
- **Post:** Objective state := `approved`; eligible for cranking.

**Schema:** [schemas/events/objective-approved.schema.json](../../schemas/events/objective-approved.schema.json)

---

#### 1.3 `objective-rejected`

**Purpose:** Policymaker rejects objective; terminal failure state.

| Field         | Type         | Description                      |
| ------------- | ------------ | -------------------------------- |
| event_version | u8           | 1                                |
| timestamp_ms  | u64          |                                  |
| objective_id  | [32]u8       |                                  |
| reason        | []const u8   | Human-readable rejection reason  |
| error_code    | ?[]const u8  | Machine-readable code            |

**Causal Rules:**
- **Pre:** Objective exists (any state).
- **Post:** Objective state := `rejected` (terminal); no further cranking.

**Schema:** [schemas/events/objective-rejected.schema.json](../../schemas/events/objective-rejected.schema.json)

---

#### 1.4 `objective-cranked`

**Purpose:** Objective `Crank()` method executed; side effects generated.

| Field              | Type    | Description                            |
| ------------------ | ------- | -------------------------------------- |
| event_version      | u8      | 1                                      |
| timestamp_ms       | u64     |                                        |
| objective_id       | [32]u8  |                                        |
| side_effects_count | u32     | Number of side effects emitted         |
| waiting            | bool    | True if waiting for external input     |

**Causal Rules:**
- **Pre:** Objective in `approved` state.
- **Post:** Side effects recorded (messages, chain txs); `waiting` flag updated.

**Schema:** [schemas/events/objective-cranked.schema.json](../../schemas/events/objective-cranked.schema.json)

---

#### 1.5 `objective-completed`

**Purpose:** Objective reached terminal success state.

| Field                | Type       | Description                  |
| -------------------- | ---------- | ---------------------------- |
| event_version        | u8         | 1                            |
| timestamp_ms         | u64        |                              |
| objective_id         | [32]u8     |                              |
| success              | bool       | True if completed successfully |
| final_channel_state  | ?[32]u8    | Hash of final channel state  |

**Causal Rules:**
- **Pre:** Objective in `approved` state; goal achieved.
- **Post:** Objective state := `completed` (terminal); removed from active set.

**Schema:** [schemas/events/objective-completed.schema.json](../../schemas/events/objective-completed.schema.json)

---

### 2. Channel State Events

#### 2.1 `channel-created`

**Purpose:** Fixed part materialized; channel ID derived.

| Field              | Type       | Description                              |
| ------------------ | ---------- | ---------------------------------------- |
| event_version      | u8         | 1                                        |
| timestamp_ms       | u64        |                                          |
| channel_id         | [32]u8     | Derived via keccak256(FixedPart)         |
| participants       | [][20]u8   | Ordered addresses (2-255)                |
| channel_nonce      | u64        | Nonce for uniqueness                     |
| app_definition     | [20]u8     | Application contract address             |
| challenge_duration | u32        | Challenge window (seconds, ≥1)           |

**Causal Rules:**
- **Pre:** `channel_id = keccak256(encode(participants, nonce, app_definition, challenge_duration))`.
- **Pre:** `challenge_duration ≥ 1`.
- **Post:** Channel fixed part persisted; ready for state updates.

**Schema:** [schemas/events/channel-created.schema.json](../../schemas/events/channel-created.schema.json)

---

#### 2.2 `state-signed`

**Purpose:** Local party signed state update.

| Field           | Type       | Description                             |
| --------------- | ---------- | --------------------------------------- |
| event_version   | u8         | 1                                       |
| timestamp_ms    | u64        |                                         |
| channel_id      | [32]u8     |                                         |
| turn_num        | u64        | Sequential turn number                  |
| state_hash      | [32]u8     | Keccak256 hash of full state            |
| signer          | [20]u8     | Address that signed                     |
| signature       | [65]u8     | ECDSA signature (r, s, v)               |
| is_final        | bool       | True if final state                     |
| app_data_hash   | ?[32]u8    | Hash of application data                |

**Causal Rules:**
- **Pre:** Channel exists.
- **Pre:** `turn_num = prev_turn_num + 1` (sequential).
- **Pre:** `signer ∈ participants`.
- **Pre:** `signature` valid over `keccak256(state_hash)` (with Ethereum prefix).
- **Post:** `latest_signed_turn := turn_num`.

**Schema:** [schemas/events/state-signed.schema.json](../../schemas/events/state-signed.schema.json)

---

#### 2.3 `state-received`

**Purpose:** Remote party's signed state received and validated.

| Field         | Type          | Description                    |
| ------------- | ------------- | ------------------------------ |
| event_version | u8            | 1                              |
| timestamp_ms  | u64           |                                |
| channel_id    | [32]u8        |                                |
| turn_num      | u64           |                                |
| state_hash    | [32]u8        |                                |
| signer        | [20]u8        |                                |
| signature     | [65]u8        |                                |
| is_final      | bool          |                                |
| peer_id       | ?[]const u8   | Network ID of sender           |

**Causal Rules:**
- **Pre:** Channel exists.
- **Pre:** `signature` valid.
- **Pre:** `signer ∈ participants`.
- **Post:** State stored; may trigger `state-supported-updated` if sufficient signatures collected.

**Schema:** [schemas/events/state-received.schema.json](../../schemas/events/state-received.schema.json)

---

#### 2.4 `state-supported-updated`

**Purpose:** Latest supported turn advanced (sufficient signatures collected).

| Field               | Type    | Description                              |
| ------------------- | ------- | ---------------------------------------- |
| event_version       | u8      | 1                                        |
| timestamp_ms        | u64     |                                          |
| channel_id          | [32]u8  |                                          |
| supported_turn      | u64     | New supported turn number                |
| state_hash          | [32]u8  | Hash of newly supported state            |
| num_signatures      | u32     | Number of signatures collected (≥1)      |
| prev_supported_turn | u64     | Previous supported turn                  |

**Causal Rules:**
- **Pre:** Channel exists.
- **Pre:** `supported_turn > prev_supported_turn`.
- **Pre:** `num_signatures ≥ threshold` (typically `floor(n/2) + 1` or all n for finalization).
- **Post:** `channel.supported_turn := supported_turn`.

**Schema:** [schemas/events/state-supported-updated.schema.json](../../schemas/events/state-supported-updated.schema.json)

---

#### 2.5 `channel-finalized`

**Purpose:** Off-chain final agreement reached (all parties signed `isFinal=true`).

| Field             | Type    | Description                   |
| ----------------- | ------- | ----------------------------- |
| event_version     | u8      | 1                             |
| timestamp_ms      | u64     |                               |
| channel_id        | [32]u8  |                               |
| final_turn        | u64     | Turn number of final state    |
| final_state_hash  | [32]u8  | Hash of final state           |

**Causal Rules:**
- **Pre:** Channel exists.
- **Pre:** All participants signed state with `isFinal=true` at `final_turn`.
- **Post:** Channel can be concluded off-chain or on-chain without challenge.

**Schema:** [schemas/events/channel-finalized.schema.json](../../schemas/events/channel-finalized.schema.json)

---

### 3. Chain Bridge Events

#### 3.1 `deposit-detected`

**Purpose:** On-chain deposit event observed by chain service.

| Field            | Type         | Description                                 |
| ---------------- | ------------ | ------------------------------------------- |
| event_version    | u8           | 1                                           |
| timestamp_ms     | u64          |                                             |
| channel_id       | [32]u8       |                                             |
| block_num        | u64          | Block number containing deposit             |
| tx_index         | u32          | Transaction index within block              |
| tx_hash          | ?[32]u8      | Transaction hash                            |
| asset            | [20]u8       | Asset contract (0x0 for ETH)                |
| amount_deposited | []const u8   | Amount deposited (decimal string, wei)      |
| now_held         | []const u8   | Total held after deposit (decimal string)   |

**Causal Rules:**
- **Pre:** Chain event observed at `block_num`.
- **Pre:** Channel exists.
- **Post:** Channel holdings updated; may trigger objective progression.

**Schema:** [schemas/events/deposit-detected.schema.json](../../schemas/events/deposit-detected.schema.json)

---

#### 3.2 `allocation-updated`

**Purpose:** Asset allocation changed on-chain.

| Field         | Type        | Description                       |
| ------------- | ----------- | --------------------------------- |
| event_version | u8          | 1                                 |
| timestamp_ms  | u64         |                                   |
| channel_id    | [32]u8      |                                   |
| block_num     | u64         |                                   |
| tx_index      | u32         |                                   |
| tx_hash       | ?[32]u8     |                                   |
| asset         | [20]u8      |                                   |
| new_amount    | []const u8  | New allocated amount (decimal)    |

**Causal Rules:**
- **Pre:** Channel exists.
- **Post:** Allocation projection updated.

**Schema:** [schemas/events/allocation-updated.schema.json](../../schemas/events/allocation-updated.schema.json)

---

#### 3.3 `challenge-registered`

**Purpose:** Challenge registered on-chain via ForceMove.

| Field                 | Type       | Description                                    |
| --------------------- | ---------- | ---------------------------------------------- |
| event_version         | u8         | 1                                              |
| timestamp_ms          | u64        |                                                |
| channel_id            | [32]u8     |                                                |
| block_num             | u64        |                                                |
| tx_index              | u32        |                                                |
| tx_hash               | ?[32]u8    |                                                |
| turn_num_record       | u64        | Turn number of challenged state                |
| finalization_time     | u64        | Unix timestamp when challenge expires          |
| challenger            | [20]u8     | Address that registered challenge              |
| is_final              | bool       | True if challenged state is final              |
| candidate_state_hash  | ?[32]u8    | Hash of candidate state                        |

**Causal Rules:**
- **Pre:** Channel exists.
- **Pre:** `turn_num_record ≥ supported_turn` (or challenge invalid).
- **Post:** Challenge timer started; finalization at `finalization_time` unless cleared.

**Schema:** [schemas/events/challenge-registered.schema.json](../../schemas/events/challenge-registered.schema.json)

---

#### 3.4 `challenge-cleared`

**Purpose:** Challenge cleared by submitting newer state.

| Field               | Type       | Description                                      |
| ------------------- | ---------- | ------------------------------------------------ |
| event_version       | u8         | 1                                                |
| timestamp_ms        | u64        |                                                  |
| channel_id          | [32]u8     |                                                  |
| block_num           | u64        |                                                  |
| tx_index            | u32        |                                                  |
| tx_hash             | ?[32]u8    |                                                  |
| new_turn_num_record | u64        | Turn number of clearing state (> challenged)     |

**Causal Rules:**
- **Pre:** Channel exists; challenge active.
- **Pre:** `new_turn_num_record > turn_num_record` (from challenge).
- **Post:** Challenge cleared; timer reset.

**Schema:** [schemas/events/challenge-cleared.schema.json](../../schemas/events/challenge-cleared.schema.json)

---

#### 3.5 `channel-concluded`

**Purpose:** Channel concluded on-chain (via finalization or cooperative close).

| Field              | Type       | Description                        |
| ------------------ | ---------- | ---------------------------------- |
| event_version      | u8         | 1                                  |
| timestamp_ms       | u64        |                                    |
| channel_id         | [32]u8     |                                    |
| block_num          | u64        |                                    |
| tx_index           | u32        |                                    |
| tx_hash            | ?[32]u8    |                                    |
| finalized_at_turn  | ?u64       | Final turn recorded on-chain       |

**Causal Rules:**
- **Pre:** Channel exists.
- **Post:** Channel concluded on-chain; withdrawals now possible.

**Schema:** [schemas/events/channel-concluded.schema.json](../../schemas/events/channel-concluded.schema.json)

---

#### 3.6 `withdraw-completed`

**Purpose:** Funds withdrawn to L1 after channel conclusion.

| Field         | Type        | Description                      |
| ------------- | ----------- | -------------------------------- |
| event_version | u8          | 1                                |
| timestamp_ms  | u64         |                                  |
| channel_id    | [32]u8      |                                  |
| block_num     | u64         |                                  |
| tx_index      | u32         |                                  |
| tx_hash       | ?[32]u8     |                                  |
| recipient     | [20]u8      | Address receiving funds          |
| asset         | [20]u8      |                                  |
| amount        | []const u8  | Amount withdrawn (decimal)       |

**Causal Rules:**
- **Pre:** Channel concluded on-chain.
- **Post:** Funds transferred to `recipient`; withdrawal objective completed.

**Schema:** [schemas/events/withdraw-completed.schema.json](../../schemas/events/withdraw-completed.schema.json)

---

### 4. Messaging Events

#### 4.1 `message-sent`

**Purpose:** Message dispatched to peer via message service.

| Field              | Type          | Description                            |
| ------------------ | ------------- | -------------------------------------- |
| event_version      | u8            | 1                                      |
| timestamp_ms       | u64           |                                        |
| message_id         | [32]u8        | Unique message identifier              |
| peer_id            | []const u8    | Network ID of recipient                |
| objective_id       | [32]u8        | Associated objective                   |
| payload_type       | ?[]const u8   | Type (ObjectivePayload, Proposal, etc) |
| payload_size_bytes | u32           | Serialized size                        |

**Causal Rules:**
- **Post:** Message queued for delivery; acknowledgement awaited.

**Schema:** [schemas/events/message-sent.schema.json](../../schemas/events/message-sent.schema.json)

---

#### 4.2 `message-received`

**Purpose:** Valid message received from peer and decoded.

| Field              | Type          | Description                 |
| ------------------ | ------------- | --------------------------- |
| event_version      | u8            | 1                           |
| timestamp_ms       | u64           |                             |
| message_id         | [32]u8        |                             |
| peer_id            | []const u8    | Network ID of sender        |
| objective_id       | [32]u8        |                             |
| payload_type       | ?[]const u8   |                             |
| payload_size_bytes | u32           |                             |

**Causal Rules:**
- **Post:** Message decoded; ready for objective update.

**Schema:** [schemas/events/message-received.schema.json](../../schemas/events/message-received.schema.json)

---

#### 4.3 `message-acked`

**Purpose:** Delivery acknowledgement received from peer.

| Field         | Type        | Description                              |
| ------------- | ----------- | ---------------------------------------- |
| event_version | u8          | 1                                        |
| timestamp_ms  | u64         |                                          |
| message_id    | [32]u8      | Original message being acknowledged      |
| peer_id       | []const u8  | Peer that acknowledged                   |
| roundtrip_ms  | u32         | Time between send and ack (milliseconds) |

**Causal Rules:**
- **Pre:** Original `message-sent` event exists.
- **Post:** Delivery confirmed; can clear from retry queue.

**Schema:** [schemas/events/message-acked.schema.json](../../schemas/events/message-acked.schema.json)

---

#### 4.4 `message-dropped`

**Purpose:** Message rejected due to decode/verify failure.

| Field              | Type        | Description                                              |
| ------------------ | ----------- | -------------------------------------------------------- |
| event_version      | u8          | 1                                                        |
| timestamp_ms       | u64         |                                                          |
| message_id         | ?[32]u8     | Message ID if parseable                                  |
| peer_id            | []const u8  | Peer that sent invalid message                           |
| reason             | []const u8  | Human-readable failure reason                            |
| error_code         | ErrorCode   | decode_failed\|signature_invalid\|channel_unknown\|etc   |
| payload_size_bytes | u32         | Raw payload size if available                            |

**Causal Rules:**
- **Post:** Message rejected; reason logged for debugging.

**Schema:** [schemas/events/message-dropped.schema.json](../../schemas/events/message-dropped.schema.json)

---

## Event ID Derivation

### Canonical JSON

Deterministic serialization rules:

1. **Sorted keys**: Lexicographic order (UTF-8)
2. **No whitespace**: Compact representation
3. **Integers**: Decimal strings (e.g., `123`, not `1.23e2`)
4. **Strings**: Escaped special chars (`\"`, `\\`, `\n`, `\r`, `\t`)
5. **No trailing commas**

### ID Formula

```
canonical_bytes = utf8_encode(canonical_json(payload))
bytestring = b"ev1|" ++ event_name ++ b"|" ++ canonical_bytes
event_id = keccak256(bytestring)
```

**Example:**

```json
// Payload (arbitrary key order)
{"turn_num": 5, "channel_id": "0x1234", "event_version": 1}

// Canonical form (sorted keys)
{"channel_id":"0x1234","event_version":1,"turn_num":5}

// Bytestring
ev1|state-signed|{"channel_id":"0x1234","event_version":1,"turn_num":5}

// event_id
keccak256(above) → 0x7a8f3c2e... (32 bytes)
```

### Golden Test Vectors

Located in `testdata/events/*.golden.json`. Each contains:
- `event_name`
- `payload` (original JSON)
- `canonical_json` (sorted, no whitespace)
- `expected_id` (computed by tests)

Tests verify:
- Same input → same ID (determinism)
- Different content → different ID
- Field order changes → same ID (canonicalization works)

---

## Implementation

### Zig Types

**File:** `src/event_store/events.zig`

```zig
pub const Event = union(enum) {
    objective_created: ObjectiveCreatedEvent,
    objective_approved: ObjectiveApprovedEvent,
    // ... 18 more variants
    message_dropped: MessageDroppedEvent,

    pub fn validate(self: *const Event, ctx: *const ValidationCtx) !void;
};
```

Each struct implements `validate()` enforcing invariants.

### ID Derivation

**File:** `src/event_store/id.zig`

```zig
pub fn deriveEventId(
    allocator: std.mem.Allocator,
    event_name: []const u8,
    canonical_json: []const u8,
) ![32]u8;

pub fn canonicalizeJson(
    allocator: std.mem.Allocator,
    value: std.json.Value,
) ![]u8;
```

### Tests

**File:** `src/event_store/events.test.zig`

- 50+ unit tests
- Invariant checks (turn progression, participant count, etc)
- Golden vector validation
- Serialization round-trips

**Coverage:** >90% (via `zig build test`)

---

## Versioning & Migration

### Schema Evolution

- `event_version` field in every event (currently `1`)
- Add fields: Optional fields backward-compatible
- Remove fields: Create new version, maintain deserializers for old versions
- Change semantics: Increment version, update validation logic

### Forward Compatibility

- Store events as raw JSON + event_id
- Deserialize with version-aware parsers
- Replay always uses versioned deserializers

### Migration Path

When updating schema:

1. Define new schema in `schemas/events/event-name-v2.schema.json`
2. Add Zig struct variant with `event_version: u8 = 2`
3. Update `Event` union
4. Write migration test: v1 → v2 conversion
5. Update golden vectors

---

## References

**Project Documentation:**
- **PRD:** [docs/prd.md](../prd.md) - §4.1 Event Sourcing, §4.2 Message Logs
- **Context:** [docs/context.md](../context.md) - Event sourcing patterns (ElectricSQL, Replicache, PGlite, go-nitro)
- **Phase 1:** [.claude/commands/1_phase_1_event_sourcing.md](../../.claude/commands/1_phase_1_event_sourcing.md) - Implementation phase
- **ADRs:** [docs/adrs/README.md](../adrs/README.md) - ADR-0001 (event sourcing strategy), ADR-0002 (serialization), ADR-0003 (in-memory log)
- **Architecture Index:** [docs/architecture/README.md](README.md) - All architecture docs

**Implementation:**
- **Code:** `src/event_store/events.zig` - Event definitions and validation
- **ID Derivation:** `src/event_store/id.zig` - keccak256-based ID generation
- **Tests:** `src/event_store/events.test.zig` - 50+ tests with golden vectors
- **Root:** `src/root.zig` - Test registration

**Prior Art & Specifications:**
- **Nitro Protocol:** https://docs.statechannels.org/ - State channel specification
- **ForceMove Protocol:** https://github.com/statechannels/nitro-protocol - On-chain contracts
- **go-nitro:** https://github.com/statechannels/go-nitro - Reference implementation
- **JSON Schema Spec:** https://json-schema.org/draft/2020-12/schema - Schema format
- **Keccak256:** Ethereum's hash function (SHA-3 variant) - Used for event IDs

**Testing & Tools:**
- **Fuzz Tests:** [docs/fuzz-tests.md](../fuzz-tests.md) - Zig fuzz testing guide
- **CLAUDE.md:** [CLAUDE.md](../../CLAUDE.md) - Coding conventions and TDD approach

---

## Change Log

| Version | Date       | Changes                            |
| ------- | ---------- | ---------------------------------- |
| 1.0     | 2025-11-08 | Initial P1 event surface (20 events) |
