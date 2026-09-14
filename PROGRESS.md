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

- Transport implementations (in-memory fake for Stage 2, MultipeerConnectivity
  for Stage 4)
- Persistence (Stage 3)
- Whether per-mutation delta accumulation is worth adding for bandwidth
  optimization over the mesh

### Test coverage

33 tests covering:
- Randomized algebraic law tests (idempotent, commutative, associative merge)
  for VersionVector, LWWRegister, MVRegister, ORSet, and RoundState — 50–100
  seeds each, seeded RNG for reproducibility
- Hand-written behavioral tests for HLC ordering/tick/receive, LWW
  timestamp-wins, MV conflict retention/overwrite/resolution, ORSet
  add-wins/remove-propagation, VV dominance
- Delta round-trip equivalence (applying delta == merging full state)
- CBOR wire format round-trips for all types including version field
- No networking imports in the library target
