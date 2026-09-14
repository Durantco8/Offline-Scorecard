# Offline-First Group Scorecard — Build Plan

## What this is

A multi-device scorecard for a group round of golf. Four phones, no cell service, no
accounts, no authoritative server. Each phone is a replica. State merges peer-to-peer
over a local mesh and reconciles when devices regain connectivity.

Golf is the use case. The project is the sync layer.

PLAN.md is authoritative. Where it specifies structure that looks speculative — protocol seams, unused model fields, explicit wire formats — that structure is deliberate and stays. Ask before removing it.

## Definition of done (v1)

Four phones in airplane mode play a full round, get separated into partitions, rejoin,
and agree on every score — with no server involved at any point.

If convergence is not proven in simulation, nothing else in this plan matters.

## Stack

- Swift, iOS only
- MultipeerConnectivity for discovery and transport (BLE + WiFi, automatic)
- Local persistence: SQLite or Core Data (decide in Stage 3, justify in PROGRESS.md)
- Optional backend replica: small Node/Express or Flask service, non-authoritative

MultipeerConnectivity is the reason for going native. React Native has no mesh story
that doesn't require writing the native module first.

---

## Architecture decisions (settled — do not relitigate without flagging)

**Delta-state CRDT, not operation-based.** Deltas are idempotent on merge, so they can
be resent freely over a lossy transport without dedup bookkeeping.

**The server is a replica, not an authority.** It merges like any other peer and cannot
overrule a phone. If it disappeared, the app would still work.

**Identity without identification.** No accounts. Each install generates a persistent
`DeviceID` (UUID) on first launch. Version vectors key on it; OR-Set elements are unique
by it. That is the whole identity system.

**Hybrid logical clocks, not wall clocks.** Phone clocks drift. HLC gives causally
consistent ordering with wall-clock readability, and `DeviceID` breaks ties
deterministically.

**Anyone can write anyone's score.** This is deliberate. Restricting each player to
their own score would eliminate concurrent writes and there would be no merge problem
left to solve.

**Conflicts surface, they do not silently resolve.** Score is a multi-value register:
when two writes are concurrent and neither dominates, both values are retained and shown
in the UI. Resolution is a new write that dominates both. This is a design opinion and
defending it is worth more than the feature.

**Shots are modeled from day one.** Even though v1's UI only ever writes a stroke count.
Retrofitting per-shot structure later means a migration; carrying it now costs almost
nothing.

---

## Data model

```
DeviceID      = UUID, persisted at first launch
HLC           = (wallClock, logicalCounter, DeviceID)
VersionVector = [DeviceID: counter]

Round
  id          : UUID
  course      : LWWRegister<Course>
  players     : ORSet<PlayerID>
  playerNames : [PlayerID: LWWRegister<String>]
  entries     : [PlayerID: [HoleNumber: MVRegister<HoleEntry>]]

HoleEntry
  strokes : Int
  shots   : [Shot]?     // nil in v1; populated in phase 1.5

Course
  holes : [Hole]        // par, stroke index, hole number

Shot                    // defined now, unused in v1
  startLie, startDistanceToPin, endLie, endDistanceToPin
```

Players are entities with stable IDs, not bare name strings. This keeps cross-round
stats possible later without a migration.

Score for a hole is `entry.strokes`. Once shots are logged, strokes is derived from
`shots.count` — but the field stays authoritative in v1 so the two never disagree.

---

## Stages

Each stage ends with a git commit checkpoint and a PROGRESS.md update. Do not begin a
stage before the previous stage's exit criteria pass.

### Stage 1 — CRDT core

Pure Swift package. No UI. No networking. No persistence. No Apple frameworks beyond
Foundation.

Build:
- `DeviceID`, `HLC`, `VersionVector`
- `LWWRegister`, `MVRegister`, `ORSet` — each with `merge`, and `delta(since: VersionVector)`
- `RoundState` composing the above, with the same two operations
- `Transport` protocol (send/receive of opaque delta payloads) — defined here, implemented
  in Stage 2 as an in-memory fake and Stage 4 as MultipeerConnectivity

Exit criteria:
- `merge` is provably idempotent, commutative, and associative in unit tests
- `delta(since:)` round-trips: applying a delta produces the same state as merging the
  full remote state
- Zero networking imports in the target

Commit: `crdt: core delta-state types and round state`

### Stage 2 — Simulation harness

This is the stage that makes the project credible. Most candidates cannot say they did
it.

Build an in-process harness that spins up N replicas over the in-memory `Transport`
fake and runs randomized schedules:
- Network partitions that form and heal
- Message drop, reorder, and duplication
- Replica crash and restart (with state loss, and without)
- Concurrent writes to the same (player, hole) key

Property tests, run over seeded random schedules so any failure reproduces exactly:
- **Convergence**: after quiescence with full connectivity, all replicas hold identical state
- **Transitive propagation**: with A↔B and B↔C but no A↔C, A's writes reach C
- **Idempotence**: `merge(a, a) == a`
- **No lost writes**: every accepted write is present or dominated in the final state
- **Conflict retention**: concurrent conflicting writes both survive to the UI layer

Exit criteria: 1000+ seeded schedules pass. A deliberately broken merge fails them.

Commit: `sim: deterministic partition and drop simulation harness`

### Stage 3 — Persistence

Durable local store. State survives process kill and device restart. Replicas rehydrate
with their version vector intact so catch-up works after a cold start.

Exit criteria: the Stage 2 crash-restart property passes against the real store, not
the fake.

Commit: `store: durable local persistence for round state`

### Stage 4 — Real transport

Swap MultipeerConnectivity in behind the `Transport` protocol. Nothing above the
protocol changes.

Build:
- Peer discovery and session management
- Anti-entropy gossip: periodic version-vector digest exchange, then delta transfer —
  not full-state broadcast
- Peer status tracking: currently reachable, last synced timestamp
- Rejoin and catch-up on reconnect

Exit criteria: four physical devices (or simulators) in airplane mode, separated and
rejoined, converge on identical state.

Commit: `transport: multipeer mesh with anti-entropy gossip`

### Stage 5 — UI

Minimal and unglamorous. Do not spend time here that Stages 1–4 need.

- Round creation; join by proximity
- Course setup: 18 holes, par, stroke index
- Hole-by-hole grid entry, any player's score editable by anyone
- Running totals, par/birdie/bogey relative scoring
- Peer status panel — reachable peers and last-sync times, so partition is visible
- Conflict view: both concurrent values shown, tap to resolve
- Round history

Commit: `ui: round entry, peer status, and conflict resolution`

### Stage 6 — Backend replica

Small service that merges uploaded deltas exactly as a phone does. Rounds upload when a
device regains signal, so a round survives a lost phone.

It must not be able to overrule a phone. Verify by pointing the Stage 2 harness at it as
just another replica.

Commit: `backend: non-authoritative merge replica`

---

## Out of scope for v1

Do not build these. They are listed so they stay decided.

- GPS distances, course maps, rangefinding — a different project, weeks of work, nothing
  added to the sync story
- Accounts, auth, cross-device identity
- Social feed, friends, cross-round leaderboards
- Apple Watch companion — a second sync surface before the first one is proven
- Per-shot logging UI — phase 1.5, after v1 ships and has been used in real rounds
- Strokes gained, handicap allocation, match formats (skins, Nassau, best ball) — phase 2

Known accepted tradeoff: with no accounts, round history does not follow a user to a new
phone. This is a deliberate choice, not an oversight.

---

## Standing rules

- Commit at each stage checkpoint above, and at any meaningful intermediate milestone
- **No AI or LLM attribution anywhere** — not in commit messages, not in code comments,
  not in file headers, not in documentation
- `PROGRESS.md` is the authoritative handoff document; update it at every checkpoint with
  what shipped, what was decided, and what is open
- Every bug fix ships with a regression test
- Diagnostic before destructive: confirm before any operation that deletes state
- Present a plan before implementing a stage; wait for review
