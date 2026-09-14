# Offline-First Group Scorecard

A multi-device scorecard for group golf rounds. Four phones, no cell service, no accounts, no server. Each phone is a replica. State merges peer-to-peer over a local mesh and reconciles when devices reconnect.

Golf is the use case. The project is the sync layer.

## Architecture decisions

**Delta-state CRDT, not operation-based.** Deltas are idempotent on merge, so they can be resent freely over a lossy transport without dedup bookkeeping.

**The server is a replica, not an authority.** It merges like any other peer and cannot overrule a phone. If it disappeared, the app would still work.

**Identity without identification.** No accounts. Each install generates a persistent `DeviceID` (UUID) on first launch. Version vectors key on it.

**Hybrid logical clocks, not wall clocks.** Phone clocks drift. HLC gives causally consistent ordering with wall-clock readability, and `DeviceID` breaks ties deterministically.

**Anyone can write anyone's score.** This is deliberate. Restricting each player to their own score would eliminate concurrent writes and there would be no merge problem left to solve.

**Conflicts surface, they do not silently resolve.** Score is a multi-value register: when two writes are concurrent and neither dominates, both values are retained and shown in the UI. Resolution is a new write that dominates both.

## Stack

- Swift, iOS only
- MultipeerConnectivity for discovery and transport (BLE + WiFi)
- CBOR wire format with explicit schema (`CRDTKit/WIRE_FORMAT.md`)
- Local persistence: TBD (Stage 3)

## Project structure

```
CRDTKit/                    Swift package — the CRDT core
  Sources/CRDTKit/          Delta-state types, round state, CBOR wire format
  Tests/CRDTKitTests/       Property and round-trip tests
  WIRE_FORMAT.md            CBOR schema for transport payloads
PLAN.md                     Build plan and stage definitions
PROGRESS.md                 What shipped, what was decided, what is open
```

## Running the tests

```
cd CRDTKit
swift test
```

Requires Swift 5.9+. No external dependencies.
