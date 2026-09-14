import XCTest
@testable import CRDTKit

final class CRDTPropertyTests: XCTestCase {
    let d1 = DeviceID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    let d2 = DeviceID(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
    let d3 = DeviceID(UUID(uuidString: "00000000-0000-0000-0000-000000000003")!)

    // MARK: - VersionVector

    func testVersionVectorMergeIdempotent() {
        let vv = VersionVector([d1: 3, d2: 5])
        XCTAssertEqual(vv.merged(with: vv), vv)
    }

    func testVersionVectorMergeCommutative() {
        let a = VersionVector([d1: 3, d2: 5])
        let b = VersionVector([d1: 7, d3: 2])
        XCTAssertEqual(a.merged(with: b), b.merged(with: a))
    }

    func testVersionVectorMergeAssociative() {
        let a = VersionVector([d1: 3])
        let b = VersionVector([d2: 5])
        let c = VersionVector([d1: 7, d2: 2])
        XCTAssertEqual(a.merged(with: b).merged(with: c), a.merged(with: b.merged(with: c)))
    }

    func testVersionVectorDominates() {
        let a = VersionVector([d1: 5, d2: 3])
        let b = VersionVector([d1: 3, d2: 3])
        XCTAssertTrue(a.dominates(b))
        XCTAssertFalse(b.dominates(a))
    }

    // MARK: - HLC

    func testHLCTotalOrder() {
        let a = HLC(wall: 100, counter: 0, device: d1)
        let b = HLC(wall: 100, counter: 0, device: d2)
        // Same wall and counter, different device — still ordered
        XCTAssertNotEqual(a, b)
        XCTAssert(a < b || b < a)
    }

    func testHLCTick() {
        var clock = HLC(wall: 100, counter: 0, device: d1)
        clock.tick(now: 100) // same wall → counter increments
        XCTAssertEqual(clock.wall, 100)
        XCTAssertEqual(clock.counter, 1)

        clock.tick(now: 200) // wall advances → counter resets
        XCTAssertEqual(clock.wall, 200)
        XCTAssertEqual(clock.counter, 0)
    }

    func testHLCReceive() {
        var local = HLC(wall: 100, counter: 2, device: d1)
        let remote = HLC(wall: 100, counter: 5, device: d2)
        local.receive(remote: remote, now: 100)
        // All three equal → max(counter, remote.counter) + 1
        XCTAssertEqual(local.wall, 100)
        XCTAssertEqual(local.counter, 6)
    }

    // MARK: - LWWRegister

    func testLWWMergeIdempotent() {
        let reg = LWWRegister(value: "hello", timestamp: HLC(wall: 100, counter: 0, device: d1), dot: Dot(device: d1, counter: 1))
        XCTAssertEqual(reg.merged(with: reg), reg)
    }

    func testLWWMergeCommutative() {
        let a = LWWRegister(value: "a", timestamp: HLC(wall: 100, counter: 0, device: d1), dot: Dot(device: d1, counter: 1))
        let b = LWWRegister(value: "b", timestamp: HLC(wall: 200, counter: 0, device: d2), dot: Dot(device: d2, counter: 1))
        XCTAssertEqual(a.merged(with: b), b.merged(with: a))
    }

    func testLWWMergeAssociative() {
        let a = LWWRegister(value: "a", timestamp: HLC(wall: 100, counter: 0, device: d1), dot: Dot(device: d1, counter: 1))
        let b = LWWRegister(value: "b", timestamp: HLC(wall: 200, counter: 0, device: d2), dot: Dot(device: d2, counter: 1))
        let c = LWWRegister(value: "c", timestamp: HLC(wall: 150, counter: 0, device: d3), dot: Dot(device: d3, counter: 1))
        XCTAssertEqual(a.merged(with: b).merged(with: c), a.merged(with: b.merged(with: c)))
    }

    func testLWWHigherTimestampWins() {
        let a = LWWRegister(value: "old", timestamp: HLC(wall: 100, counter: 0, device: d1), dot: Dot(device: d1, counter: 1))
        let b = LWWRegister(value: "new", timestamp: HLC(wall: 200, counter: 0, device: d2), dot: Dot(device: d2, counter: 1))
        XCTAssertEqual(a.merged(with: b).value, "new")
    }

    // MARK: - MVRegister

    func testMVMergeIdempotent() {
        var reg = MVRegister<Int>()
        reg.set(value: 4, dot: Dot(device: d1, counter: 1))
        XCTAssertEqual(reg.merged(with: reg), reg)
    }

    func testMVMergeCommutative() {
        var a = MVRegister<Int>()
        a.set(value: 4, dot: Dot(device: d1, counter: 1))
        var b = MVRegister<Int>()
        b.set(value: 5, dot: Dot(device: d2, counter: 1))
        XCTAssertEqual(a.merged(with: b), b.merged(with: a))
    }

    func testMVMergeAssociative() {
        var a = MVRegister<Int>()
        a.set(value: 4, dot: Dot(device: d1, counter: 1))
        var b = MVRegister<Int>()
        b.set(value: 5, dot: Dot(device: d2, counter: 1))
        var c = MVRegister<Int>()
        c.set(value: 6, dot: Dot(device: d3, counter: 1))
        XCTAssertEqual(a.merged(with: b).merged(with: c), a.merged(with: b.merged(with: c)))
    }

    func testMVConflictRetention() {
        // Two devices concurrently write different scores — both values survive
        var a = MVRegister<Int>()
        a.set(value: 4, dot: Dot(device: d1, counter: 1))

        var b = MVRegister<Int>()
        b.set(value: 5, dot: Dot(device: d2, counter: 1))

        let merged = a.merged(with: b)
        XCTAssertEqual(merged.values, [4, 5])
    }

    func testMVOverwriteDominates() {
        // Device d1 writes 4, then overwrites with 5 — only 5 survives
        var reg = MVRegister<Int>()
        reg.set(value: 4, dot: Dot(device: d1, counter: 1))
        reg.set(value: 5, dot: Dot(device: d1, counter: 2))
        XCTAssertEqual(reg.values, [5])
    }

    func testMVConflictResolution() {
        // Two concurrent writes produce a conflict; a new write that dominates both resolves it
        var a = MVRegister<Int>()
        a.set(value: 4, dot: Dot(device: d1, counter: 1))

        var b = MVRegister<Int>()
        b.set(value: 5, dot: Dot(device: d2, counter: 1))

        var merged = a.merged(with: b)
        XCTAssertEqual(merged.values.count, 2)

        // Resolve by writing a new value that has seen both
        merged.set(value: 5, dot: Dot(device: d1, counter: 2))
        XCTAssertEqual(merged.values, [5])
    }

    // MARK: - ORSet

    func testORSetMergeIdempotent() {
        var set = ORSet<String>()
        set.add("alice", dot: Dot(device: d1, counter: 1))
        XCTAssertEqual(set.merged(with: set), set)
    }

    func testORSetMergeCommutative() {
        var a = ORSet<String>()
        a.add("alice", dot: Dot(device: d1, counter: 1))
        var b = ORSet<String>()
        b.add("bob", dot: Dot(device: d2, counter: 1))
        XCTAssertEqual(a.merged(with: b), b.merged(with: a))
    }

    func testORSetMergeAssociative() {
        var a = ORSet<String>()
        a.add("alice", dot: Dot(device: d1, counter: 1))
        var b = ORSet<String>()
        b.add("bob", dot: Dot(device: d2, counter: 1))
        var c = ORSet<String>()
        c.add("carol", dot: Dot(device: d3, counter: 1))
        XCTAssertEqual(a.merged(with: b).merged(with: c), a.merged(with: b.merged(with: c)))
    }

    func testORSetAddWins() {
        // d1 adds "alice", d2 independently adds then removes "alice"
        var a = ORSet<String>()
        a.add("alice", dot: Dot(device: d1, counter: 1))

        var b = ORSet<String>()
        b.add("alice", dot: Dot(device: d2, counter: 1))
        b.remove("alice") // removes d2's dot

        // a's add is concurrent with b's remove — add wins
        let merged = a.merged(with: b)
        XCTAssertTrue(merged.elements.contains("alice"))
    }

    func testORSetRemovePropagates() {
        // Both devices have alice via same dot. One removes.
        var a = ORSet<String>()
        a.add("alice", dot: Dot(device: d1, counter: 1))

        var b = a // same state
        b.remove("alice")

        let merged = a.merged(with: b)
        // b saw the add (dot is in b's VV) and removed it → gone
        XCTAssertFalse(merged.elements.contains("alice"))
    }
}
