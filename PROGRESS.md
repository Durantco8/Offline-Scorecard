# Progress

## Stage 1 — CRDT core ✅

**Shipped:** Pure Swift package (`CRDTKit/`) with delta-state CRDT types and
round state composition. No UI, networking, or persistence. Only `Foundation`
imported.

### What was built

- `DeviceID`, `HLC`, `VersionVector`, `Dot` — clock and causality primitives
- `LWWRegister<T>` — last-writer-wins register, ordered by HLC, dot-tracked
  for delta computation
- `MVRegister<T>` — multi-value register using dot-kernel merge; concurrent
  writes coexist until explicitly resolved
- `ORSet<T>` — observed-remove set using dot-kernel merge; add wins over
  concurrent remove
- `RoundState` — composes the above into the full round data model (course,
  players, player names, per-hole score entries)
- `RoundDelta` — delta payload for transport
- `Transport` protocol — defined, not yet implemented
- CBOR wire format — minimal encoder/decoder and explicit `WireCodable`
  conformances for all types, with schema documented in `WIRE_FORMAT.md`
- Domain types: `PlayerID`, `Lie` (enum), `Shot`, `Hole`, `Course`, `HoleEntry`

### Decisions made

- **Delta granularity is per-sub-CRDT, not per-entry.** `MVRegister.delta(since:)`
  and `ORSet.delta(since:)` return their full state or nil. Entry-level deltas
  are well-defined in the literature (Almeida, Shoker, Baquero) using
  delta-mutators that record the precise causal context of each mutation — the
  specific dots observed and consumed, not the full version vector. This
  implementation derives deltas from final state instead, which can't recover
  which dots a mutation consumed: sending full VV + partial entries causes
  false removals; sending partial VV + partial entries can't signal cross-device
  removal. Per-mutation delta accumulation is the correct path to entry-level
  granularity, but since each register holds one (player, hole) score entry
  and the players set is typically 1–8 entries, full-state deltas are
  effectively free at this scale.
- **Dot allocation is global across a RoundState.** All sub-CRDTs draw dots
  from a shared counter per device. Sub-CRDT version vectors may "over-claim"
  (cover dots belonging to sibling sub-CRDTs) but this is harmless — entries
  from other sub-CRDTs never appear.
- **Wire format is CBOR with integer-keyed maps** for structs and arrays for
  fixed-arity types. Schema is in `CRDTKit/WIRE_FORMAT.md`.

### What is open

- Persistence (Stage 3)
- MultipeerConnectivity transport (Stage 4)
- Whether per-mutation delta accumulation is worth adding for bandwidth
  optimization over the mesh
- **Global VV is not reconstructable from received deltas.** When an
  LWW-losing init dot is discarded by merge, no sub-CRDT carries it, so
  peers can never reconstruct the originator's full VV via applyDelta.
  Safe for local dot allocation (always uses locally-allocated counters)
  but must not be compared across replicas or used as a causal summary.
  Stage 4 gossip design should account for this if it needs a real
  per-replica causal summary

## Stage 2 — Simulation harness ✅

**Shipped:** Deterministic simulation harness exercising the CRDT core under
adversarial network conditions. No production code changes.

### What was built

- `SimNetwork` — in-memory network with connectivity graph, message queue,
  configurable drop/duplicate rates, partition/heal operations
- `SimTransport` — `Transport` protocol implementation backed by SimNetwork
- `SimReplica` — wraps `RoundState` + `HLC` + per-peer VV tracking with
  sync/crash/write methods. Crash models state loss with persisted counter
  guard to prevent dot reuse on recovery
- `WriteLog` / `WriteRecord` — tracks writes with causal metadata for
  property verification against converged state
- 4 test functions, 1000+ seeded schedules:
  - `testRandomizedSchedules` (700 seeds): random events including writes,
    syncs, partitions, heals, crashes, fault injection. Checks convergence,
    no-lost-writes, conflict retention, idempotency
  - `testTransitivePropagation` (100 seeds): A↔B, B↔C topology
  - `testCrashRecovery` (100 seeds): crash with/without state, verify
    convergence after recovery
  - `testConcurrentConflicts` (100 seeds): isolated replicas write same key,
    verify all values survive

### Decisions made

- **Crash-without-state models persisted counter.** A crashed replica tracks
  its pre-crash counter (max across multiple crashes) and blocks writes until
  VV recovery reaches that level, preventing dot reuse
- **peerVV tracking is optimistic.** The sender updates peerVVs after
  enqueuing, not on delivery confirmation. This matches real UDP-like
  transport but means dropped messages cause unnecessary retransmission in
  subsequent syncs rather than data loss
- **removeLostWrites uses converged state, not global VVs.** Global VVs can
  cover a dot from a different sub-CRDT, falsely preserving a write record
  for a truly lost entry. Checking the actual register state after quiescence
  is precise
- **Global VV intentionally excluded from convergence check.** applyDelta
  reconstructs VV from sub-CRDT dots/VVs only; init dots from losing LWW
  courses are not propagated. This is cosmetic — delta computation uses
  sub-CRDT VVs

### Bugs found and fixed (in the harness)

- Double-crash preCrashCounter regression: second crash overwrote guard with
  stale VV from fresh init. Fixed with max()
- Stale messages in queue during quiescence could prevent convergence. Fixed
  by clearing queue at quiesce start

## Stage 3 — Persistence ✅

**Shipped:** Durable local store with atomic writes. State survives process
kill and device restart. Serialization round-trip verified across 1000+
simulation seeds.

### What was built

- `RoundStore` protocol — `save`, `load`, `list`, `delete` for round state
- `FileRoundStore` — JSON-encoded files, one per round. Writes to a temp
  file then renames for atomicity (no corrupted state on mid-write kill)
- Simulation integration: `crash(keepState: true)` now round-trips state
  through `JSONEncoder`/`JSONDecoder`, proving serialization preserves
  enough CRDT state for convergence across all 1000+ seeded schedules
- 7 unit tests for FileRoundStore (save/load/list/delete/overwrite/atomic)

### Decisions made

- **File-based with JSONEncoder, not SQLite or Core Data.** RoundState is a
  single struct serialized as a unit — no relational queries, no field-level
  updates, no joins. State is under 50 KB per round (4 players × 18 holes).
  Core Data's managed object graph and SQLite's query surface are unused
  overhead for what is functionally `save(blob, key)` / `load(key)`
- **Atomic writes via temp-file-then-rename.** A JSON write isn't atomic —
  process kill mid-write produces a corrupted file. Writing to `.tmp` then
  using `replaceItemAt` ensures the file is always the old or new state,
  never partial

### What is open

- **Full-state write on every mutation is a known scaling limit.** At ~50 KB
  per round, rewriting the entire file on every score entry and received
  delta is fast for v1. If rounds grow (per-shot logging, many players) or
  save frequency increases, incremental persistence (WAL or delta journal)
  would be needed. Acceptable now, flagged for later
- DeviceID persistence (app layer concern, deferred to Stage 5)

### Test coverage

44 tests covering:
- Randomized algebraic law tests (idempotent, commutative, associative merge)
  for VersionVector, LWWRegister, MVRegister, ORSet, and RoundState — 50–100
  seeds each, seeded RNG for reproducibility
- Hand-written behavioral tests for HLC ordering/tick/receive, LWW
  timestamp-wins, MV conflict retention/overwrite/resolution, ORSet
  add-wins/remove-propagation, VV dominance
- Delta round-trip equivalence (applying delta == merging full state)
- CBOR wire format round-trips for all types including version field
- No networking imports in the library target
- Simulation harness (Stage 2): 4 replicas over in-memory transport with
  seeded schedules (1000+ seeds). Simulates partitions, message
  drop/reorder/duplication, crash with and without state loss, concurrent
  writes. Properties verified: convergence after quiescence, transitive
  propagation (A↔B, B↔C, no A↔C), idempotent delta application, no lost
  writes, concurrent conflicts retained. Validated by confirming failures
  when applyDelta VV update is removed and when MVRegister.merge is broken.
- FileRoundStore: save/load round-trip, list, delete, overwrite, atomic
  write (no .tmp residue), nonexistent-key handling
- Simulation crash-with-state exercises JSONEncoder/JSONDecoder round-trip
  on every keepState crash across all 1000+ seeds

## Stage 4 — Real transport ⚠️ (exit criteria pending real hardware)

**Shipped:** MultipeerConnectivity transport behind the existing `Transport`
protocol, with anti-entropy gossip and peer lifecycle management. Nothing
above the protocol changed.

**Exit criteria status:** The PLAN.md exit bar is four physical devices in
airplane mode, separated into partitions, rejoined, converging on identical
state. This cannot be tested from CLI or simulators — MultipeerConnectivity
requires real Bluetooth/WiFi hardware (no Bonjour in the simulator). The
gossip protocol is proven correct via unit tests against a fake transport,
and the underlying CRDT merge is validated by 1000+ seeded simulation
schedules, but the real-device convergence test is blocked on Stage 5 UI.
It should be the first thing run once there is an app to install.

### What was built

- `CRDTTransport` library target depending on `CRDTKit`
- `SyncMessage` — two message types for gossip protocol:
  - `.vvDigest(roundID, vv)` — "here's what I have"
  - `.delta(RoundDelta)` — "here's what you're missing"
  - CBOR-encoded using the existing wire format
- `SyncEngine` — anti-entropy gossip protocol:
  - Periodic or on-demand VV digest exchange with all connected peers
  - On receiving a digest: compare against local state, send delta if local
    is ahead, reply with own digest if peer might have state we lack
  - On receiving a delta: merge into local state, notify delegate
  - Per-peer VV tracking to avoid redundant delta sends
  - Peer status tracking: `lastSeen`, `lastSynced` timestamps
  - Round management: add/update/remove rounds
  - Delegate protocol for app-layer persistence on state change
- `MCTransport` — MultipeerConnectivity implementation:
  - Simultaneous advertise + browse for automatic peer discovery
  - Auto-accept all invitations (no auth for v1)
  - DeviceID handshake on connect: 2-byte prefix + 16-byte UUID, sent
    immediately on session connect. Messages received before handshake
    completes are queued and drained once mapping is established
  - MCPeerID ↔ DeviceID bidirectional mapping
  - `onPeerChange` callback for connect/disconnect events
  - `start()`/`stop()` lifecycle
- 11 unit tests for SyncEngine and SyncMessage with fake transport

### Decisions made

- **Gossip is digest-then-delta, not broadcast.** Each sync round starts
  with a lightweight VV digest (tens of bytes). Deltas are sent only when
  the digest reveals the peer is behind. This avoids broadcasting full
  deltas every cycle, which matters over BLE where bandwidth is ~2 KB/s
- **Per-peer VV tracking uses optimistic update.** After sending a delta,
  the sender records the peer's VV as up-to-date. If the message is lost,
  the next digest exchange will detect the gap and resend. Same tradeoff
  as the simulation harness
- **Handshake is a custom 18-byte message, not Bonjour discovery info.**
  MCPeerID display names are truncated and not guaranteed unique.
  Discovery info is only available during browsing, not after session
  establishment. A post-connect handshake is reliable and simple
- **Auto-accept invitations, no peer limit.** Every nearby device running
  the same service type is invited and accepted unconditionally — no
  session cap, no round-scoping, no group membership check. Acceptable
  for a friend-group demo where physical proximity (BLE range ~10m) is
  the only boundary. If the app is ever used at a tournament or driving
  range where multiple groups are nearby, this needs scoping — likely
  round ID in the Bonjour discovery info so browsers only invite peers
  advertising the same round
- **`RoundDelta.isEmpty` promoted to public property.** Was previously a
  test-only extension. SyncEngine needs it to skip no-op delta sends

### SimNetwork vs MultipeerConnectivity gaps

| Concern | SimNetwork | Real MPC |
|---|---|---|
| Session negotiation | Instant | 1–3s latency; can fail silently |
| Message size | Unlimited | ~96 KB per `send()` (undocumented) |
| Discovery | Instant, deterministic | Flaky; peers appear/disappear |
| Background | Always running | Suspended by iOS; sessions drop |
| Peer identity | Stable DeviceID | MCPeerID changes across sessions |
| Message ordering | Queue order (randomized) | Reliable mode preserves order |
| Duplex | Symmetric | Both sides must advertise+browse |

### What is open

- **Message size limit (~96 KB) is not enforced.** RoundDelta for a
  typical round is well under this (~50 KB max), but if rounds grow
  (many players, per-shot data), large deltas may need chunking
- **Background suspension drops MPC sessions.** iOS suspends the app
  after ~30s in background; MCSession disconnects. Reconnect-on-foreground
  is needed for Stage 5 UI integration
- **No encryption.** `encryptionPreference: .none` for v1. Physical
  proximity is the security boundary. If the app moves to WiFi-range
  sync, encryption should be added
- DeviceID persistence (app layer concern, deferred to Stage 5)
- Physical device testing deferred to Stage 5 UI integration — gossip
  protocol is proven correct via unit tests with fake transport and
  the Stage 2 simulation harness validates the underlying CRDT merge

### Test coverage

55 tests covering:
- All Stage 1–3 tests (unchanged, still passing)
- SyncMessage CBOR round-trip: vvDigest, delta, empty VV, invalid data
- SyncEngine gossip: digest-triggers-delta, bidirectional sync,
  transitive propagation (A↔B↔C), duplicate delta idempotency,
  no-delta-when-up-to-date, peer add/remove, round add/remove

## Stage 5 — UI ⚠️ (builds, needs real-device test)

**Shipped:** Minimal SwiftUI app with all screens. Builds for iOS device
(iphoneos SDK). Not yet tested on real hardware — Stage 4 exit criteria
(partition/rejoin/converge on physical devices) still pending.

### What was built

- `ScoreCard/` Xcode project with local package dependency on `CRDTKit/`
- `AppState` — `@MainActor ObservableObject` coordinating:
  - `SyncEngine` + `MCTransport` for peer discovery and gossip
  - `FileRoundStore` for persistence
  - `DeviceID` persisted to UserDefaults on first launch
  - Round lifecycle (create, add player, set score, resolve conflict)
  - Delegate bridge: remote merges → `@Published` state + persist
- `RoundListView` — create round, see nearby devices, navigate to round
- `CourseSetupView` — 9/18 holes, par per hole (3–5), stroke index,
  add players by name
- `ScorecardView` — players × holes grid with:
  - Tap-to-edit score entry (any player, any hole)
  - Running totals and par-relative scoring (E/+N/-N, color-coded)
  - Conflict indicator (orange "!" badge) linking to resolve view
- `PeerStatusView` — this device ID, connected peers with last-seen
  and last-synced timestamps, round count
- `ConflictView` — shows both concurrent values, tap to resolve
  (writes a new dominating entry)
- `RoundHistoryView` — completed rounds (all players scored all holes)
- Info.plist with `NSLocalNetworkUsageDescription`, `NSBonjourServices`,
  `UILaunchScreen`, orientation support

### Decisions made

- **DeviceID persisted to UserDefaults, not Keychain.** Simpler for v1.
  Keychain would survive app reinstall but adds complexity for no benefit
  at this stage — a reinstall means a new replica anyway
- **`HLC.now(device:)` uses millisecond wall clock.** Consistent with
  the rest of the CRDT layer's HLC usage
- **SyncDelegate stored as strong property on AppState.** SyncEngine's
  delegate is weak; a temporary would be immediately deallocated
- **Course setup inline, not a separate flow.** Sheet on round creation,
  also accessible from the scorecard toolbar. No separate "new round
  wizard" — keep it minimal
- **Conflict resolution is a new write that dominates.** Tapping a value
  in ConflictView writes that value as a new entry, which dominates
  both concurrent values on merge. This matches the CRDT semantics
  (new write with later HLC supersedes)

### What is open

- **Stage 4 real-device exit criteria still pending.** App builds for
  device but hasn't been installed or tested on real hardware yet.
  First priority is: install on two phones, create a round on one,
  verify it syncs to the other, then run the full partition/rejoin test
- **No round sharing by proximity.** Currently each device creates its
  own round. For join-by-proximity, the app needs a way to discover
  and subscribe to a round that another device already has. The sync
  engine will propagate any round both devices know about, but the
  "I want to join your round" intent isn't expressed yet
- **Stroke index editing is display-only.** SI values are shown but not
  editable in the UI — they're set to 1–18 sequentially. Fine for v1
- **No undo.** A mis-entered score can be overwritten but not undone
- **Timer-based periodic sync at 2s.** Acceptable for v1 but should
  move to event-driven (sync on mutation + on peer connect) to reduce
  unnecessary network traffic
