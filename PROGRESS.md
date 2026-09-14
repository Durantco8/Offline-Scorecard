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
  and `ORSet.delta(since:)` return their full state or nil — not a filtered
  subset of entries. The dot-kernel encodes removal as "dot covered by VV,
  absent from entries," which works in full-state merge but breaks in
  state-derived partial deltas: when device X's `set()` replaces device Y's
  entry, Y's VV counter doesn't change, so no partial delta can signal Y's
  removal without also creating false tombstones for Y's entries in sibling
  registers. Since each (player, hole) pair has its own register, registers
  are small and the overhead is negligible. Per-mutation delta accumulation
  (tracking deltas at write time rather than deriving them from state) can
  solve this if profiling warrants it.
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
