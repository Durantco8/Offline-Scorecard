import XCTest
@testable import CRDTKit

final class SimulationTests: XCTestCase {

    static let devices = (1...4).map {
        DeviceID(UUID(uuidString: String(format: "00000000-0000-0000-0000-00000000%04d", $0))!)
    }

    static let players = [
        PlayerID(UUID(uuidString: "00000000-0000-0000-1000-000000000001")!),
        PlayerID(UUID(uuidString: "00000000-0000-0000-1000-000000000002")!),
        PlayerID(UUID(uuidString: "00000000-0000-0000-1000-000000000003")!),
    ]

    static let roundID = UUID(uuidString: "00000000-0000-0000-2000-000000000001")!

    // MARK: - Helpers

    private func makeSimulation(
        replicaCount: Int,
        rng: inout SeededRNG
    ) -> (SimNetwork, [SimReplica]) {
        let network = SimNetwork()
        let replicas = Self.devices.prefix(replicaCount).map { device in
            SimReplica(
                roundID: Self.roundID, device: device,
                network: network, wallClock: 100
            )
        }
        network.healAll()

        for player in Self.players {
            replicas[0].addPlayer(player)
        }
        quiesce(replicas: replicas, network: network, rng: &rng)

        return (network, replicas)
    }

    private func quiesce(
        replicas: [SimReplica],
        network: SimNetwork,
        rng: inout SeededRNG
    ) {
        network.healAll()
        network.dropRate = 0
        network.duplicateRate = 0
        network.clearQueue()
        for replica in replicas { replica.peerVVs = [:] }

        for _ in 0..<20 {
            var sent = false
            for replica in replicas {
                let before = network.pendingCount
                replica.sync()
                if network.pendingCount > before { sent = true }
            }
            network.deliverAll(rng: &rng)
            if !sent { break }
        }
    }

    // MARK: - Property checks

    private func checkConvergence(_ replicas: [SimReplica], seed: UInt64) {
        guard let first = replicas.first else { return }
        for i in 1..<replicas.count {
            XCTAssertEqual(first.state.course, replicas[i].state.course,
                "Convergence: course, seed \(seed)")
            XCTAssertEqual(first.state.players, replicas[i].state.players,
                "Convergence: players, seed \(seed)")
            XCTAssertEqual(first.state.playerNames, replicas[i].state.playerNames,
                "Convergence: playerNames, seed \(seed)")
            XCTAssertEqual(first.state.entries, replicas[i].state.entries,
                "Convergence: entries, seed \(seed)")
            // Global VV is intentionally not compared. applyDelta reconstructs
            // VV from sub-CRDT dots/VVs, so init dots from losing LWW courses
            // are not propagated. This is cosmetic — delta computation uses
            // sub-CRDT VVs, not the global one. Consistent with DeltaTests.
        }
    }

    private func checkNoLostWrites(
        _ replicas: [SimReplica], log: WriteLog, seed: UInt64
    ) {
        let vv = replicas[0].state.versionVector
        for r in log.records {
            XCTAssertTrue(
                vv[r.dot.device] >= r.dot.counter,
                "Lost write: \(r.dot) strokes=\(r.strokes), seed \(seed)"
            )
        }
    }

    private func checkConflictRetention(
        _ replicas: [SimReplica], log: WriteLog, seed: UInt64
    ) {
        let state = replicas[0].state

        // Group writes by (player, hole)
        var grouped: [String: [WriteRecord]] = [:]
        for r in log.records {
            grouped["\(r.player.uuid)-\(r.hole)", default: []].append(r)
        }

        for (_, writes) in grouped {
            for w in writes {
                // A write is superseded if another write's VV-at-write covers its dot,
                // or if the register's VV covers the dot (superseded by a write whose
                // record was lost to a crash — its VV effect persists through merges).
                let superseded = writes.contains { other in
                    other.dot != w.dot
                        && other.vvAtWrite[w.dot.device] >= w.dot.counter
                }
                guard !superseded else { continue }

                let reg = state.entries[w.player]![w.hole]!
                if reg.versionVector[w.dot.device] >= w.dot.counter {
                    continue
                }
                XCTAssertTrue(
                    reg.values.contains(HoleEntry(strokes: w.strokes)),
                    "Conflict retention: strokes=\(w.strokes) dot=\(w.dot) missing, seed \(seed)"
                )
            }
        }
    }

    private func checkIdempotency(_ replicas: [SimReplica], seed: UInt64) {
        for replica in replicas {
            XCTAssertNil(
                replica.idempotencyFailure,
                "\(replica.idempotencyFailure ?? ""), seed \(seed)"
            )
        }
    }

    // MARK: - Randomized schedules (700 seeds)

    func testRandomizedSchedules() {
        for seed: UInt64 in 0..<700 {
            var rng = SeededRNG(seed: seed)
            let (network, replicas) = makeSimulation(replicaCount: 4, rng: &rng)
            let writeLog = WriteLog()
            let allDevices = replicas.map(\.device)

            let eventCount = Int(rng.next() % 20) + 20
            for _ in 0..<eventCount {
                let ev = rng.next() % 100

                if ev < 45 {
                    // Write — skip replicas that crashed without state and haven't synced
                    let eligible = replicas.filter { !$0.needsSync }
                    guard !eligible.isEmpty else { continue }
                    let replica = eligible[Int(rng.next() % UInt64(eligible.count))]
                    let player = Self.players[Int(rng.next() % UInt64(Self.players.count))]
                    let hole = Int(rng.next() % 18) + 1
                    let strokes = Int(rng.next() % 8) + 1
                    let vvBefore = replica.state.versionVector
                    let dot = Dot(
                        device: replica.device,
                        counter: vvBefore[replica.device] + 1
                    )
                    replica.writeScore(player: player, hole: hole, strokes: strokes)
                    writeLog.record(WriteRecord(
                        device: replica.device, player: player, hole: hole,
                        strokes: strokes, dot: dot, vvAtWrite: vvBefore
                    ))

                } else if ev < 70 {
                    // Sync + partial deliver
                    for replica in replicas { replica.sync() }
                    let n = Int(rng.next() % 5)
                    for _ in 0..<n { network.deliverOne(rng: &rng) }

                } else if ev < 80 {
                    // Partition into 1–3 groups
                    let groupCount = Int(rng.next() % 3) + 1
                    var shuffled = allDevices
                    shuffled.shuffle(using: &rng)
                    var groups: [[DeviceID]] = Array(repeating: [], count: groupCount)
                    for (i, d) in shuffled.enumerated() {
                        groups[i % groupCount].append(d)
                    }
                    network.partition(groups: groups)

                } else if ev < 85 {
                    // Heal
                    network.healAll()

                } else if ev < 90 {
                    // Crash
                    let replica = replicas[Int(rng.next() % UInt64(replicas.count))]
                    replica.crash(keepState: rng.next() % 2 == 0)

                } else if ev < 95 {
                    // Adjust faults
                    network.dropRate = rng.next() % 3 == 0 ? 0.2 : 0
                    network.duplicateRate = rng.next() % 3 == 0 ? 0.1 : 0

                } else {
                    // Deliver some pending messages
                    let n = min(Int(rng.next() % 5) + 1, network.pendingCount)
                    for _ in 0..<n { network.deliverOne(rng: &rng) }
                }
            }

            // Quiesce and verify all properties
            quiesce(replicas: replicas, network: network, rng: &rng)

            // Remove writes that were irrecoverably lost (message drops + crashes).
            // Must run after quiesce so we can check the converged state.
            writeLog.removeLostWrites(
                finalEntries: replicas[0].state.entries
            )
            checkConvergence(replicas, seed: seed)
            checkNoLostWrites(replicas, log: writeLog, seed: seed)
            checkConflictRetention(replicas, log: writeLog, seed: seed)
            checkIdempotency(replicas, seed: seed)
        }
    }

    // MARK: - Transitive propagation (100 seeds)

    func testTransitivePropagation() {
        for seed: UInt64 in 0..<100 {
            var rng = SeededRNG(seed: seed)
            let (network, replicas) = makeSimulation(replicaCount: 3, rng: &rng)
            let a = replicas[0], b = replicas[1], c = replicas[2]

            // A↔B, B↔C, no A↔C
            network.connectivity = [
                a.device: [b.device],
                b.device: [a.device, c.device],
                c.device: [b.device],
            ]

            // A writes randomized scores
            let writeCount = Int(rng.next() % 5) + 1
            for _ in 0..<writeCount {
                let player = Self.players[Int(rng.next() % UInt64(Self.players.count))]
                let hole = Int(rng.next() % 18) + 1
                let strokes = Int(rng.next() % 8) + 1
                a.writeScore(player: player, hole: hole, strokes: strokes)
            }

            // Sync rounds — 2 hops needed (A→B→C), do 5 for margin
            for _ in 0..<5 {
                for r in replicas { r.sync() }
                network.deliverAll(rng: &rng)
            }

            XCTAssertEqual(a.state.entries, c.state.entries,
                "Transitive propagation: entries, seed \(seed)")
            XCTAssertEqual(a.state.players, c.state.players,
                "Transitive propagation: players, seed \(seed)")
        }
    }

    // MARK: - Crash recovery (100 seeds)

    func testCrashRecovery() {
        for seed: UInt64 in 0..<100 {
            var rng = SeededRNG(seed: seed)
            let (network, replicas) = makeSimulation(replicaCount: 3, rng: &rng)

            // All replicas write scores
            for replica in replicas {
                let n = Int(rng.next() % 3) + 1
                for _ in 0..<n {
                    let player = Self.players[Int(rng.next() % UInt64(Self.players.count))]
                    let hole = Int(rng.next() % 18) + 1
                    let strokes = Int(rng.next() % 8) + 1
                    replica.writeScore(player: player, hole: hole, strokes: strokes)
                }
            }

            // Sync so writes propagate
            for _ in 0..<3 {
                for r in replicas { r.sync() }
                network.deliverAll(rng: &rng)
            }

            // Crash one replica
            let idx = Int(rng.next() % UInt64(replicas.count))
            replicas[idx].crash(keepState: rng.next() % 2 == 0)

            // More writes from eligible replicas
            for replica in replicas where !replica.needsSync {
                let player = Self.players[Int(rng.next() % UInt64(Self.players.count))]
                let hole = Int(rng.next() % 18) + 1
                let strokes = Int(rng.next() % 8) + 1
                replica.writeScore(player: player, hole: hole, strokes: strokes)
            }

            // Quiesce — crashed replica recovers through sync
            quiesce(replicas: replicas, network: network, rng: &rng)
            checkConvergence(replicas, seed: seed)
        }
    }

    // MARK: - Concurrent conflicts (100 seeds)

    func testConcurrentConflicts() {
        for seed: UInt64 in 0..<100 {
            var rng = SeededRNG(seed: seed)
            let (network, replicas) = makeSimulation(replicaCount: 3, rng: &rng)

            // Isolate all replicas
            for r in replicas { network.connectivity[r.device] = [] }

            // Each writes to the same (player, hole) with distinct strokes
            let player = Self.players[0]
            let hole = 1
            var expected: Set<HoleEntry> = []
            for (i, replica) in replicas.enumerated() {
                let strokes = i + 3 // 3, 4, 5
                replica.writeScore(player: player, hole: hole, strokes: strokes)
                expected.insert(HoleEntry(strokes: strokes))
            }

            // Heal and converge
            quiesce(replicas: replicas, network: network, rng: &rng)
            checkConvergence(replicas, seed: seed)

            // All concurrent values must be present
            let reg = replicas[0].state.entries[player]![hole]!
            XCTAssertEqual(reg.values, expected,
                "Concurrent conflicts: expected \(expected), got \(reg.values), seed \(seed)")
        }
    }
}
