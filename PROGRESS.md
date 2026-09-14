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
  and `ORSet.delta(since:)` return their full state or nil. Computing
  entry-level deltas from final state alone can't correctly propagate removals
  when the removed entry's device counter hasn't advanced. Since each (player,
  hole) pair has its own register, the overhead is negligible. Per-mutation
  delta accumulation can be added in Stage 2 if profiling warrants it.
- **Dot allocation is global across a RoundState.** All sub-CRDTs draw dots
  from a shared counter per device. Sub-CRDT version vectors may "over-claim"
  (cover dots belonging to sibling sub-CRDTs) but this is harmless — entries
  from other sub-CRDTs never appear.
- **Wire format is CBOR with integer-keyed maps** for structs and arrays for
  fixed-arity types. Schema is in `CRDTKit/WIRE_FORMAT.md`.

### What is open

- Transport implementations (in-memory fake for Stage 2, MultipeerConnectivity
  for Stage 4)
- Persistence (Stage 3)
- Whether per-mutation delta accumulation is worth adding for bandwidth
  optimization over the mesh

### Test coverage

40 tests covering:
- Idempotent, commutative, associative merge for every CRDT type and RoundState
- Delta round-trip equivalence (applying delta == merging full state)
- MVRegister conflict retention and resolution
- ORSet add-wins semantics and remove propagation
- CBOR wire format round-trips for all types
- No networking imports in the library target
