import XCTest
@testable import CRDTKit

final class DeltaTests: XCTestCase {
    let d1 = DeviceID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    let d2 = DeviceID(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)

    // MARK: - LWWRegister delta

    func testLWWDeltaRoundTrip() {
        let a = LWWRegister(value: "old", timestamp: HLC(wall: 100, counter: 0, device: d1), dot: Dot(device: d1, counter: 1))
        let b = LWWRegister(value: "new", timestamp: HLC(wall: 200, counter: 0, device: d2), dot: Dot(device: d2, counter: 1))

        let fullMerge = a.merged(with: b)

        let delta = b.delta(since: VersionVector([d1: 1]))!
        let deltaMerge = a.merged(with: delta)

        XCTAssertEqual(fullMerge, deltaMerge)
    }

    func testLWWDeltaNilWhenKnown() {
        let reg = LWWRegister(value: "hello", timestamp: HLC(wall: 100, counter: 0, device: d1), dot: Dot(device: d1, counter: 1))
        // Querier already knows about dot (d1, 1)
        XCTAssertNil(reg.delta(since: VersionVector([d1: 1])))
    }

    func testLWWDeltaSentWhenDotNotCovered() {
        let reg = LWWRegister(value: "hello", timestamp: HLC(wall: 100, counter: 0, device: d1), dot: Dot(device: d1, counter: 3))
        // Querier only knows d1 up to 2
        XCTAssertNotNil(reg.delta(since: VersionVector([d1: 2])))
    }

    // MARK: - MVRegister delta

    func testMVDeltaRoundTrip() {
        var a = MVRegister<Int>()
        a.set(value: 4, dot: Dot(device: d1, counter: 1))

        var b = MVRegister<Int>()
        b.set(value: 5, dot: Dot(device: d2, counter: 1))

        let fullMerge = a.merged(with: b)

        let delta = b.delta(since: a.versionVector)!
        let deltaMerge = a.merged(with: delta)

        XCTAssertEqual(fullMerge, deltaMerge)
    }

    func testMVDeltaPropagatesRemoval() {
        // a and b start with the same value
        var a = MVRegister<Int>()
        a.set(value: 4, dot: Dot(device: d1, counter: 1))
        var b = a

        // b overwrites → old value removed
        b.set(value: 5, dot: Dot(device: d2, counter: 1))

        let fullMerge = a.merged(with: b)
        let delta = b.delta(since: a.versionVector)!
        let deltaMerge = a.merged(with: delta)

        XCTAssertEqual(fullMerge, deltaMerge)
        // Both should have only value 5 (b's write dominates a's since b saw a's dot)
        XCTAssertEqual(deltaMerge.values, [5])
    }

    func testMVDeltaPreservesConcurrency() {
        // Two independent writes — delta should preserve both
        var a = MVRegister<Int>()
        a.set(value: 4, dot: Dot(device: d1, counter: 1))

        var b = MVRegister<Int>()
        b.set(value: 5, dot: Dot(device: d2, counter: 1))

        let delta = b.delta(since: VersionVector())! // B sends everything
        let deltaMerge = a.merged(with: delta)

        XCTAssertEqual(deltaMerge.values.count, 2)
        XCTAssertTrue(deltaMerge.values.contains(4))
        XCTAssertTrue(deltaMerge.values.contains(5))
    }

    // MARK: - ORSet delta

    func testORSetDeltaRoundTrip() {
        var a = ORSet<String>()
        a.add("alice", dot: Dot(device: d1, counter: 1))

        var b = ORSet<String>()
        b.add("bob", dot: Dot(device: d2, counter: 1))

        let fullMerge = a.merged(with: b)
        let delta = b.delta(since: a.versionVector)!
        let deltaMerge = a.merged(with: delta)

        XCTAssertEqual(fullMerge, deltaMerge)
    }

    func testORSetDeltaPropagatesRemoval() {
        var a = ORSet<String>()
        a.add("alice", dot: Dot(device: d1, counter: 1))
        var b = a
        b.remove("alice")

        let fullMerge = a.merged(with: b)
        let delta = b.delta(since: VersionVector())!
        let deltaMerge = a.merged(with: delta)

        XCTAssertEqual(fullMerge, deltaMerge)
        XCTAssertFalse(deltaMerge.elements.contains("alice"))
    }

    // MARK: - RoundState delta

    func testRoundStateDeltaRoundTrip() {
        let roundID = UUID()
        let p1 = PlayerID()
        let p2 = PlayerID()

        var a = RoundState(id: roundID, device: d1, timestamp: HLC(wall: 100, counter: 0, device: d1))
        a.addPlayer(p1, device: d1)
        a.setPlayerName(p1, name: "Alice", timestamp: HLC(wall: 101, counter: 0, device: d1), device: d1)
        a.setScore(player: p1, hole: 1, entry: HoleEntry(strokes: 4), device: d1)

        var b = RoundState(id: roundID, device: d2, timestamp: HLC(wall: 100, counter: 0, device: d2))
        b.addPlayer(p2, device: d2)
        b.setPlayerName(p2, name: "Bob", timestamp: HLC(wall: 102, counter: 0, device: d2), device: d2)
        b.setScore(player: p2, hole: 1, entry: HoleEntry(strokes: 5), device: d2)

        let fullMerge = a.merged(with: b)

        let delta = b.delta(since: a.versionVector)
        var aWithDelta = a
        aWithDelta.applyDelta(delta)

        XCTAssertEqual(fullMerge.players, aWithDelta.players)
        XCTAssertEqual(fullMerge.playerNames, aWithDelta.playerNames)
        XCTAssertEqual(fullMerge.entries, aWithDelta.entries)
        XCTAssertEqual(fullMerge.course, aWithDelta.course)
    }

    func testRoundStateMergeIdempotent() {
        let roundID = UUID()
        var state = RoundState(id: roundID, device: d1, timestamp: HLC(wall: 100, counter: 0, device: d1))
        let p1 = PlayerID()
        state.addPlayer(p1, device: d1)
        state.setScore(player: p1, hole: 1, entry: HoleEntry(strokes: 4), device: d1)

        XCTAssertEqual(state.merged(with: state), state)
    }

    func testRoundStateMergeCommutative() {
        let roundID = UUID()
        let p1 = PlayerID()

        var a = RoundState(id: roundID, device: d1, timestamp: HLC(wall: 100, counter: 0, device: d1))
        a.addPlayer(p1, device: d1)
        a.setScore(player: p1, hole: 1, entry: HoleEntry(strokes: 4), device: d1)

        var b = RoundState(id: roundID, device: d2, timestamp: HLC(wall: 100, counter: 0, device: d2))
        b.addPlayer(p1, device: d2)
        b.setScore(player: p1, hole: 1, entry: HoleEntry(strokes: 5), device: d2)

        XCTAssertEqual(a.merged(with: b), b.merged(with: a))
    }

    func testRoundStateMergeAssociative() {
        let roundID = UUID()
        let p1 = PlayerID()

        var a = RoundState(id: roundID, device: d1, timestamp: HLC(wall: 100, counter: 0, device: d1))
        a.addPlayer(p1, device: d1)

        var b = RoundState(id: roundID, device: d2, timestamp: HLC(wall: 100, counter: 0, device: d2))
        b.setScore(player: p1, hole: 1, entry: HoleEntry(strokes: 4), device: d2)

        let d3 = DeviceID(UUID(uuidString: "00000000-0000-0000-0000-000000000003")!)
        var c = RoundState(id: roundID, device: d3, timestamp: HLC(wall: 100, counter: 0, device: d3))
        c.setScore(player: p1, hole: 2, entry: HoleEntry(strokes: 3), device: d3)

        XCTAssertEqual(a.merged(with: b).merged(with: c), a.merged(with: b.merged(with: c)))
    }

    func testConcurrentScoreWritesProduceConflict() {
        let roundID = UUID()
        let p1 = PlayerID()

        var a = RoundState(id: roundID, device: d1, timestamp: HLC(wall: 100, counter: 0, device: d1))
        a.setScore(player: p1, hole: 1, entry: HoleEntry(strokes: 4), device: d1)

        var b = RoundState(id: roundID, device: d2, timestamp: HLC(wall: 100, counter: 0, device: d2))
        b.setScore(player: p1, hole: 1, entry: HoleEntry(strokes: 5), device: d2)

        let merged = a.merged(with: b)
        let values = merged.entries[p1]![1]!.values
        XCTAssertEqual(values.count, 2)
        XCTAssertTrue(values.contains(HoleEntry(strokes: 4)))
        XCTAssertTrue(values.contains(HoleEntry(strokes: 5)))
    }
}
