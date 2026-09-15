import XCTest
@testable import CRDTKit

final class RoundStoreTests: XCTestCase {

    private var tmpDir: URL!
    private var store: FileRoundStore!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CRDTKitTests-\(UUID().uuidString)")
        store = try! FileRoundStore(directory: tmpDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private func makeState() -> RoundState {
        let device = DeviceID(UUID())
        let clock = HLC(wall: 100, counter: 0, device: device)
        var state = RoundState(id: UUID(), device: device, timestamp: clock)
        let player = PlayerID(UUID())
        state.addPlayer(player, device: device)
        state.setScore(
            player: player, hole: 1,
            entry: HoleEntry(strokes: 4), device: device
        )
        return state
    }

    func testSaveAndLoad() throws {
        let state = makeState()
        try store.save(state)

        let loaded = try store.load(id: state.id)
        XCTAssertEqual(loaded, state)
    }

    func testLoadNonexistent() throws {
        let result = try store.load(id: UUID())
        XCTAssertNil(result)
    }

    func testListRounds() throws {
        let s1 = makeState()
        let s2 = makeState()
        try store.save(s1)
        try store.save(s2)

        let ids = try store.listRounds()
        XCTAssertEqual(Set(ids), [s1.id, s2.id])
    }

    func testDelete() throws {
        let state = makeState()
        try store.save(state)
        try store.delete(id: state.id)

        XCTAssertNil(try store.load(id: state.id))
        XCTAssertTrue(try store.listRounds().isEmpty)
    }

    func testDeleteNonexistent() throws {
        // Should not throw
        try store.delete(id: UUID())
    }

    func testOverwrite() throws {
        let device = DeviceID(UUID())
        let clock = HLC(wall: 100, counter: 0, device: device)
        var state = RoundState(id: UUID(), device: device, timestamp: clock)
        let player = PlayerID(UUID())
        state.addPlayer(player, device: device)
        state.setScore(
            player: player, hole: 1,
            entry: HoleEntry(strokes: 4), device: device
        )
        try store.save(state)

        // Mutate and save again
        state.setScore(
            player: player, hole: 1,
            entry: HoleEntry(strokes: 3), device: device
        )
        try store.save(state)

        let loaded = try store.load(id: state.id)
        XCTAssertEqual(loaded, state)
    }

    func testFileIsAtomicAfterSave() throws {
        let state = makeState()
        try store.save(state)

        // No .tmp file should remain
        let contents = try FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil
        )
        for url in contents {
            XCTAssertNotEqual(url.pathExtension, "tmp",
                "Temp file should not persist after save")
        }
    }
}
