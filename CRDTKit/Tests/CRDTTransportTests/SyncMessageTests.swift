import XCTest
import CRDTKit
@testable import CRDTTransport

final class SyncMessageTests: XCTestCase {

    func testVVDigestRoundTrip() throws {
        let roundID = UUID()
        let d1 = DeviceID(UUID())
        let d2 = DeviceID(UUID())
        var vv = VersionVector()
        vv[d1] = 5
        vv[d2] = 3

        let msg = SyncMessage.vvDigest(roundID: roundID, vv: vv)
        let data = msg.encode()
        let decoded = try SyncMessage.decode(data)

        guard case .vvDigest(let decodedID, let decodedVV) = decoded else {
            XCTFail("Expected vvDigest"); return
        }
        XCTAssertEqual(decodedID, roundID)
        XCTAssertEqual(decodedVV, vv)
    }

    func testDeltaRoundTrip() throws {
        let roundID = UUID()
        let player = PlayerID(UUID())
        let device = DeviceID(UUID())
        let clock = HLC(wall: 100, counter: 0, device: device)

        var state = RoundState(id: roundID, device: device, timestamp: clock)
        state.addPlayer(player, device: device)
        state.setScore(player: player, hole: 1,
                       entry: HoleEntry(strokes: 4), device: device)

        let delta = state.delta(since: VersionVector())
        let msg = SyncMessage.delta(delta)
        let data = msg.encode()
        let decoded = try SyncMessage.decode(data)

        guard case .delta(let decodedDelta) = decoded else {
            XCTFail("Expected delta"); return
        }
        XCTAssertEqual(decodedDelta.roundID, roundID)
        XCTAssertNotNil(decodedDelta.course)
        XCTAssertNotNil(decodedDelta.players)
    }

    func testEmptyVVDigest() throws {
        let msg = SyncMessage.vvDigest(roundID: UUID(), vv: VersionVector())
        let decoded = try SyncMessage.decode(msg.encode())
        guard case .vvDigest(_, let vv) = decoded else {
            XCTFail("Expected vvDigest"); return
        }
        XCTAssertEqual(vv, VersionVector())
    }

    func testInvalidDataReturnsNil() {
        XCTAssertThrowsError(try SyncMessage.decode(Data([0x00, 0x01])))
    }
}
