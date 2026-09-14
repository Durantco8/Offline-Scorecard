import XCTest
@testable import CRDTKit

// MARK: - Seeded RNG

struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 1 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

// MARK: - Random generators

private let testDevices = (1...4).map {
    DeviceID(UUID(uuidString: "00000000-0000-0000-0000-00000000000\($0)")!)
}

private func pickDevice(_ rng: inout SeededRNG) -> DeviceID {
    testDevices[Int(rng.next() % UInt64(testDevices.count))]
}

private func randomMVRegister(_ rng: inout SeededRNG) -> MVRegister<Int> {
    var reg = MVRegister<Int>()
    let opCount = Int(rng.next() % 4) + 1
    for _ in 0..<opCount {
        let device = pickDevice(&rng)
        let value = Int(rng.next() % 10)
        let counter = reg.versionVector[device] + 1
        reg.set(value: value, dot: Dot(device: device, counter: counter))
    }
    // Optionally merge with an independent register for multi-value states
    if rng.next() % 3 == 0 {
        var other = MVRegister<Int>()
        let n = Int(rng.next() % 3) + 1
        for _ in 0..<n {
            let device = pickDevice(&rng)
            let value = Int(rng.next() % 10)
            let counter = other.versionVector[device] + 1
            other.set(value: value, dot: Dot(device: device, counter: counter))
        }
        reg.merge(other)
    }
    return reg
}

private func randomORSet(_ rng: inout SeededRNG) -> ORSet<Int> {
    var set = ORSet<Int>()
    let opCount = Int(rng.next() % 6) + 1
    for _ in 0..<opCount {
        let device = pickDevice(&rng)
        let element = Int(rng.next() % 5)
        if rng.next() % 4 == 0 && !set.elements.isEmpty {
            let elements = Array(set.elements)
            let target = elements[Int(rng.next() % UInt64(elements.count))]
            set.remove(target)
        } else {
            let counter = set.versionVector[device] + 1
            set.add(element, dot: Dot(device: device, counter: counter))
        }
    }
    if rng.next() % 3 == 0 {
        var other = ORSet<Int>()
        let n = Int(rng.next() % 3) + 1
        for _ in 0..<n {
            let device = pickDevice(&rng)
            let element = Int(rng.next() % 5)
            let counter = other.versionVector[device] + 1
            other.add(element, dot: Dot(device: device, counter: counter))
        }
        set.merge(other)
    }
    return set
}

private func randomLWWRegister(_ rng: inout SeededRNG, device: DeviceID) -> LWWRegister<Int> {
    let wall = UInt64(rng.next() % 10000) + 1
    let value = Int(rng.next() % 100)
    return LWWRegister(
        value: value,
        timestamp: HLC(wall: wall, counter: 0, device: device),
        dot: Dot(device: device, counter: 1)
    )
}

private func randomVersionVector(_ rng: inout SeededRNG) -> VersionVector {
    var vv = VersionVector()
    let count = Int(rng.next() % 3) + 1
    for _ in 0..<count {
        let device = pickDevice(&rng)
        vv[device] = max(vv[device], UInt64(rng.next() % 10) + 1)
    }
    return vv
}

// MARK: - Algebraic law tests (randomized)

final class CRDTPropertyTests: XCTestCase {
    let d1 = testDevices[0]
    let d2 = testDevices[1]
    let d3 = testDevices[2]

    // MARK: - VersionVector (100 seeds)

    func testVersionVectorAlgebraicLaws() {
        for seed: UInt64 in 0..<100 {
            var rng = SeededRNG(seed: seed)
            let a = randomVersionVector(&rng)
            let b = randomVersionVector(&rng)
            let c = randomVersionVector(&rng)

            XCTAssertEqual(a.merged(with: a), a, "VV idempotent failed, seed \(seed)")
            XCTAssertEqual(a.merged(with: b), b.merged(with: a), "VV commutative failed, seed \(seed)")
            XCTAssertEqual(
                a.merged(with: b).merged(with: c),
                a.merged(with: b.merged(with: c)),
                "VV associative failed, seed \(seed)"
            )
        }
    }

    // MARK: - LWWRegister (100 seeds)

    func testLWWRegisterAlgebraicLaws() {
        for seed: UInt64 in 0..<100 {
            var rng = SeededRNG(seed: seed)
            // Distinct devices guarantee distinct HLC total order → commutativity
            let a = randomLWWRegister(&rng, device: testDevices[0])
            let b = randomLWWRegister(&rng, device: testDevices[1])
            let c = randomLWWRegister(&rng, device: testDevices[2])

            XCTAssertEqual(a.merged(with: a), a, "LWW idempotent failed, seed \(seed)")
            XCTAssertEqual(a.merged(with: b), b.merged(with: a), "LWW commutative failed, seed \(seed)")
            XCTAssertEqual(
                a.merged(with: b).merged(with: c),
                a.merged(with: b.merged(with: c)),
                "LWW associative failed, seed \(seed)"
            )
        }
    }

    // MARK: - MVRegister (100 seeds)

    func testMVRegisterAlgebraicLaws() {
        for seed: UInt64 in 0..<100 {
            var rng = SeededRNG(seed: seed)
            let a = randomMVRegister(&rng)
            let b = randomMVRegister(&rng)
            let c = randomMVRegister(&rng)

            XCTAssertEqual(a.merged(with: a), a, "MV idempotent failed, seed \(seed)")
            XCTAssertEqual(a.merged(with: b), b.merged(with: a), "MV commutative failed, seed \(seed)")
            XCTAssertEqual(
                a.merged(with: b).merged(with: c),
                a.merged(with: b.merged(with: c)),
                "MV associative failed, seed \(seed)"
            )
        }
    }

    // MARK: - ORSet (100 seeds)

    func testORSetAlgebraicLaws() {
        for seed: UInt64 in 0..<100 {
            var rng = SeededRNG(seed: seed)
            let a = randomORSet(&rng)
            let b = randomORSet(&rng)
            let c = randomORSet(&rng)

            XCTAssertEqual(a.merged(with: a), a, "ORSet idempotent failed, seed \(seed)")
            XCTAssertEqual(a.merged(with: b), b.merged(with: a), "ORSet commutative failed, seed \(seed)")
            XCTAssertEqual(
                a.merged(with: b).merged(with: c),
                a.merged(with: b.merged(with: c)),
                "ORSet associative failed, seed \(seed)"
            )
        }
    }

    // MARK: - RoundState (50 seeds)

    func testRoundStateAlgebraicLaws() {
        let sharedPlayers = (0..<3).map { _ in PlayerID() }
        let roundID = UUID()

        for seed: UInt64 in 0..<50 {
            var rng = SeededRNG(seed: seed)

            func randomState(device: DeviceID) -> RoundState {
                let wall = UInt64(rng.next() % 10000) + 100
                var state = RoundState(
                    id: roundID,
                    device: device,
                    timestamp: HLC(wall: wall, counter: 0, device: device)
                )
                let ops = Int(rng.next() % 4) + 1
                for _ in 0..<ops {
                    let p = sharedPlayers[Int(rng.next() % UInt64(sharedPlayers.count))]
                    switch rng.next() % 3 {
                    case 0:
                        state.addPlayer(p, device: device)
                    case 1:
                        let w = wall + UInt64(rng.next() % 1000)
                        state.setPlayerName(p, name: "N\(rng.next() % 50)",
                            timestamp: HLC(wall: w, counter: 0, device: device), device: device)
                    default:
                        let hole = Int(rng.next() % 18) + 1
                        let strokes = Int(rng.next() % 8) + 1
                        state.setScore(player: p, hole: hole, entry: HoleEntry(strokes: strokes), device: device)
                    }
                }
                return state
            }

            let a = randomState(device: testDevices[0])
            let b = randomState(device: testDevices[1])
            let c = randomState(device: testDevices[2])

            XCTAssertEqual(a.merged(with: a), a, "RoundState idempotent failed, seed \(seed)")
            XCTAssertEqual(a.merged(with: b), b.merged(with: a), "RoundState commutative failed, seed \(seed)")
            XCTAssertEqual(
                a.merged(with: b).merged(with: c),
                a.merged(with: b.merged(with: c)),
                "RoundState associative failed, seed \(seed)"
            )
        }
    }

    // MARK: - Behavioral tests (hand-written, kept)

    func testHLCTotalOrder() {
        let a = HLC(wall: 100, counter: 0, device: d1)
        let b = HLC(wall: 100, counter: 0, device: d2)
        XCTAssertNotEqual(a, b)
        XCTAssert(a < b || b < a)
    }

    func testHLCTick() {
        var clock = HLC(wall: 100, counter: 0, device: d1)
        clock.tick(now: 100)
        XCTAssertEqual(clock.wall, 100)
        XCTAssertEqual(clock.counter, 1)

        clock.tick(now: 200)
        XCTAssertEqual(clock.wall, 200)
        XCTAssertEqual(clock.counter, 0)
    }

    func testHLCReceive() {
        var local = HLC(wall: 100, counter: 2, device: d1)
        let remote = HLC(wall: 100, counter: 5, device: d2)
        local.receive(remote: remote, now: 100)
        XCTAssertEqual(local.wall, 100)
        XCTAssertEqual(local.counter, 6)
    }

    func testLWWHigherTimestampWins() {
        let a = LWWRegister(value: "old", timestamp: HLC(wall: 100, counter: 0, device: d1), dot: Dot(device: d1, counter: 1))
        let b = LWWRegister(value: "new", timestamp: HLC(wall: 200, counter: 0, device: d2), dot: Dot(device: d2, counter: 1))
        XCTAssertEqual(a.merged(with: b).value, "new")
    }

    func testMVConflictRetention() {
        var a = MVRegister<Int>()
        a.set(value: 4, dot: Dot(device: d1, counter: 1))
        var b = MVRegister<Int>()
        b.set(value: 5, dot: Dot(device: d2, counter: 1))
        let merged = a.merged(with: b)
        XCTAssertEqual(merged.values, [4, 5])
    }

    func testMVOverwriteDominates() {
        var reg = MVRegister<Int>()
        reg.set(value: 4, dot: Dot(device: d1, counter: 1))
        reg.set(value: 5, dot: Dot(device: d1, counter: 2))
        XCTAssertEqual(reg.values, [5])
    }

    func testMVConflictResolution() {
        var a = MVRegister<Int>()
        a.set(value: 4, dot: Dot(device: d1, counter: 1))
        var b = MVRegister<Int>()
        b.set(value: 5, dot: Dot(device: d2, counter: 1))
        var merged = a.merged(with: b)
        XCTAssertEqual(merged.values.count, 2)
        merged.set(value: 5, dot: Dot(device: d1, counter: 2))
        XCTAssertEqual(merged.values, [5])
    }

    func testORSetAddWins() {
        var a = ORSet<String>()
        a.add("alice", dot: Dot(device: d1, counter: 1))
        var b = ORSet<String>()
        b.add("alice", dot: Dot(device: d2, counter: 1))
        b.remove("alice")
        let merged = a.merged(with: b)
        XCTAssertTrue(merged.elements.contains("alice"))
    }

    func testORSetRemovePropagates() {
        var a = ORSet<String>()
        a.add("alice", dot: Dot(device: d1, counter: 1))
        var b = a
        b.remove("alice")
        let merged = a.merged(with: b)
        XCTAssertFalse(merged.elements.contains("alice"))
    }

    func testVersionVectorDominates() {
        let a = VersionVector([d1: 5, d2: 3])
        let b = VersionVector([d1: 3, d2: 3])
        XCTAssertTrue(a.dominates(b))
        XCTAssertFalse(b.dominates(a))
    }
}
