import XCTest
import CRDTKit
@testable import CRDTTransport

// MARK: - Fake Transport

final class FakeTransport: Transport {
    let deviceID: DeviceID
    var onReceive: ((Data, DeviceID) -> Void)?
    var sentMessages: [(data: Data, to: DeviceID)] = []
    var broadcastMessages: [Data] = []

    init(deviceID: DeviceID) {
        self.deviceID = deviceID
    }

    func send(_ data: Data, to peer: DeviceID) {
        sentMessages.append((data: data, to: peer))
    }

    func broadcast(_ data: Data) {
        broadcastMessages.append(data)
    }

    /// Deliver all messages sent by this transport to target engines' transports.
    func deliverTo(_ transports: [DeviceID: FakeTransport]) {
        for msg in sentMessages {
            transports[msg.to]?.onReceive?(msg.data, deviceID)
        }
        sentMessages.removeAll()
    }
}

// MARK: - Delegate spy

final class SyncDelegateSpy: SyncEngineDelegate {
    var updatedRounds: [UUID] = []

    func syncEngine(_ engine: SyncEngine, didUpdateRound roundID: UUID) {
        updatedRounds.append(roundID)
    }
}

// MARK: - Tests

final class SyncEngineTests: XCTestCase {

    private func makeEngine() -> (SyncEngine, FakeTransport, DeviceID) {
        let device = DeviceID(UUID())
        let transport = FakeTransport(deviceID: device)
        let engine = SyncEngine(deviceID: device, transport: transport)
        return (engine, transport, device)
    }

    private func makeRound(id: UUID, device: DeviceID) -> RoundState {
        let clock = HLC(wall: 100, counter: 0, device: device)
        return RoundState(id: id, device: device, timestamp: clock)
    }

    // MARK: - Basic gossip

    func testDigestExchangeTriggersDeltas() {
        let (engineA, transportA, deviceA) = makeEngine()
        let (engineB, transportB, deviceB) = makeEngine()
        let transports: [DeviceID: FakeTransport] = [deviceA: transportA, deviceB: transportB]

        let roundID = UUID()
        var stateA = makeRound(id: roundID, device: deviceA)
        let player = PlayerID(UUID())
        stateA.addPlayer(player, device: deviceA)
        stateA.setScore(player: player, hole: 1,
                        entry: HoleEntry(strokes: 4), device: deviceA)

        engineA.addRound(stateA)
        engineB.addRound(makeRound(id: roundID, device: deviceB))

        let delegateB = SyncDelegateSpy()
        engineB.delegate = delegateB

        // A sends digest to B; B replies with its own digest; A sends delta
        engineA.addPeer(deviceB)
        engineB.addPeer(deviceA)

        for _ in 0..<3 {
            transportA.deliverTo(transports)
            transportB.deliverTo(transports)
        }

        // B should have received delta and updated
        XCTAssertTrue(delegateB.updatedRounds.contains(roundID))

        // B's state should now have the player and score
        let bState = engineB.round(for: roundID)!
        XCTAssertTrue(bState.players.elements.contains(player))
        XCTAssertEqual(bState.entries[player]?[1]?.values, [HoleEntry(strokes: 4)])
    }

    func testBidirectionalSync() {
        let (engineA, transportA, deviceA) = makeEngine()
        let (engineB, transportB, deviceB) = makeEngine()
        let transports: [DeviceID: FakeTransport] = [deviceA: transportA, deviceB: transportB]

        let roundID = UUID()
        var stateA = makeRound(id: roundID, device: deviceA)
        var stateB = makeRound(id: roundID, device: deviceB)

        let p1 = PlayerID(UUID())
        let p2 = PlayerID(UUID())
        stateA.addPlayer(p1, device: deviceA)
        stateA.setScore(player: p1, hole: 1, entry: HoleEntry(strokes: 4), device: deviceA)
        stateB.addPlayer(p2, device: deviceB)
        stateB.setScore(player: p2, hole: 1, entry: HoleEntry(strokes: 5), device: deviceB)

        engineA.addRound(stateA)
        engineB.addRound(stateB)

        engineA.addPeer(deviceB)
        engineB.addPeer(deviceA)

        // Round 1: exchange digests
        transportA.deliverTo(transports)
        transportB.deliverTo(transports)

        // Round 2: deliver any remaining responses
        transportA.deliverTo(transports)
        transportB.deliverTo(transports)

        // Both should converge
        let finalA = engineA.round(for: roundID)!
        let finalB = engineB.round(for: roundID)!
        XCTAssertEqual(finalA, finalB)
        XCTAssertTrue(finalA.players.elements.contains(p1))
        XCTAssertTrue(finalA.players.elements.contains(p2))
    }

    func testNoDeltaSentWhenPeerIsUpToDate() {
        let (engineA, transportA, deviceA) = makeEngine()
        let (_, _, deviceB) = makeEngine()

        let roundID = UUID()
        engineA.addRound(makeRound(id: roundID, device: deviceA))
        engineA.addPeer(deviceB)

        // A sends digest. Since B isn't here, messages go to sentMessages.
        // Count messages: should be one digest
        let initialCount = transportA.sentMessages.count
        XCTAssertEqual(initialCount, 1)

        // Decode it — should be a vvDigest
        let msg = try! SyncMessage.decode(transportA.sentMessages[0].data)
        guard case .vvDigest = msg else {
            XCTFail("Expected vvDigest"); return
        }
    }

    // MARK: - Peer management

    func testAddRemovePeer() {
        let (engine, _, _) = makeEngine()
        let peer = DeviceID(UUID())

        engine.addPeer(peer)
        XCTAssertNotNil(engine.peers[peer])

        engine.removePeer(peer)
        XCTAssertNil(engine.peers[peer])
    }

    // MARK: - Round management

    func testAddRemoveRound() {
        let (engine, _, device) = makeEngine()
        let roundID = UUID()
        let state = makeRound(id: roundID, device: device)

        engine.addRound(state)
        XCTAssertNotNil(engine.round(for: roundID))

        engine.removeRound(roundID)
        XCTAssertNil(engine.round(for: roundID))
    }

    // MARK: - Transitive propagation via gossip

    func testTransitivePropagation() {
        let (engineA, transportA, deviceA) = makeEngine()
        let (engineB, transportB, deviceB) = makeEngine()
        let (engineC, transportC, deviceC) = makeEngine()
        let transports: [DeviceID: FakeTransport] = [
            deviceA: transportA, deviceB: transportB, deviceC: transportC
        ]

        let roundID = UUID()
        var stateA = makeRound(id: roundID, device: deviceA)
        let player = PlayerID(UUID())
        stateA.addPlayer(player, device: deviceA)
        stateA.setScore(player: player, hole: 1,
                        entry: HoleEntry(strokes: 3), device: deviceA)

        engineA.addRound(stateA)
        engineB.addRound(makeRound(id: roundID, device: deviceB))
        engineC.addRound(makeRound(id: roundID, device: deviceC))

        // A ↔ B only, B ↔ C only
        engineA.addPeer(deviceB)
        engineB.addPeer(deviceA)
        engineB.addPeer(deviceC)
        engineC.addPeer(deviceB)

        // Sync rounds until convergence
        for _ in 0..<5 {
            transportA.deliverTo(transports)
            transportB.deliverTo(transports)
            transportC.deliverTo(transports)
        }

        // C should have A's write via B
        let cState = engineC.round(for: roundID)!
        XCTAssertTrue(cState.players.elements.contains(player))
        XCTAssertEqual(cState.entries[player]?[1]?.values, [HoleEntry(strokes: 3)])
    }

    // MARK: - Idempotent delta application

    func testDuplicateDeltaIsIdempotent() {
        let (engineA, transportA, deviceA) = makeEngine()
        let (engineB, transportB, deviceB) = makeEngine()
        let transports: [DeviceID: FakeTransport] = [deviceA: transportA, deviceB: transportB]

        let roundID = UUID()
        var stateA = makeRound(id: roundID, device: deviceA)
        let player = PlayerID(UUID())
        stateA.addPlayer(player, device: deviceA)
        stateA.setScore(player: player, hole: 1,
                        entry: HoleEntry(strokes: 4), device: deviceA)
        engineA.addRound(stateA)
        engineB.addRound(makeRound(id: roundID, device: deviceB))

        engineA.addPeer(deviceB)
        engineB.addPeer(deviceA)

        // Sync once
        transportA.deliverTo(transports)
        transportB.deliverTo(transports)
        transportA.deliverTo(transports)
        transportB.deliverTo(transports)

        let afterFirst = engineB.round(for: roundID)!

        // Sync again — should be no-op
        engineA.syncAll()
        transportA.deliverTo(transports)
        transportB.deliverTo(transports)

        let afterSecond = engineB.round(for: roundID)!
        XCTAssertEqual(afterFirst, afterSecond)
    }
}
