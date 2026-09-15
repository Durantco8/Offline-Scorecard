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

### Test coverage

37 tests covering:
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
