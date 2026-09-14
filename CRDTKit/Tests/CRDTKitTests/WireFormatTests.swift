import XCTest
@testable import CRDTKit

final class WireFormatTests: XCTestCase {
    let d1 = DeviceID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    let d2 = DeviceID(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)

    func testCBORRoundTrip() throws {
        // Build a delta with all field types populated
        let roundID = UUID()
        let p1 = PlayerID()

        var state = RoundState(id: roundID, device: d1, timestamp: HLC(wall: 100, counter: 0, device: d1))
        state.addPlayer(p1, device: d1)
        state.setPlayerName(p1, name: "Alice", timestamp: HLC(wall: 101, counter: 0, device: d1), device: d1)
        state.setScore(player: p1, hole: 1, entry: HoleEntry(strokes: 4), device: d1)

        let delta = state.delta(since: VersionVector())

        // Encode to CBOR bytes
        let encoded = Wire.encode(delta)
        XCTAssertFalse(encoded.isEmpty)

        // Decode back
        let decoded = try Wire.decode(encoded)

        XCTAssertEqual(decoded.roundID, delta.roundID)
        XCTAssertEqual(decoded.course, delta.course)
        XCTAssertEqual(decoded.players, delta.players)
        XCTAssertEqual(decoded.playerNames, delta.playerNames)
        XCTAssertEqual(decoded.entries, delta.entries)
    }

    func testCBORRoundTripWithNilFields() throws {
        let roundID = UUID()
        let delta = RoundDelta(roundID: roundID)

        let encoded = Wire.encode(delta)
        let decoded = try Wire.decode(encoded)

        XCTAssertEqual(decoded.roundID, roundID)
        XCTAssertNil(decoded.course)
        XCTAssertNil(decoded.players)
        XCTAssertTrue(decoded.playerNames.isEmpty)
        XCTAssertTrue(decoded.entries.isEmpty)
    }

    func testCBORPrimitiveRoundTrips() throws {
        // DeviceID
        let device = DeviceID()
        let deviceDecoded = try DeviceID.fromCBOR(device.toCBOR())
        XCTAssertEqual(device, deviceDecoded)

        // HLC
        let hlc = HLC(wall: 12345, counter: 7, device: d1)
        let hlcDecoded = try HLC.fromCBOR(hlc.toCBOR())
        XCTAssertEqual(hlc, hlcDecoded)

        // Dot
        let dot = Dot(device: d1, counter: 42)
        let dotDecoded = try Dot.fromCBOR(dot.toCBOR())
        XCTAssertEqual(dot, dotDecoded)

        // VersionVector
        let vv = VersionVector([d1: 5, d2: 3])
        let vvDecoded = try VersionVector.fromCBOR(vv.toCBOR())
        XCTAssertEqual(vv, vvDecoded)
    }

    func testCBORDomainTypeRoundTrips() throws {
        // Hole
        let hole = Hole(number: 1, par: 4, strokeIndex: 7)
        let holeDecoded = try Hole.fromCBOR(hole.toCBOR())
        XCTAssertEqual(hole, holeDecoded)

        // Course
        let course = Course(holes: [
            Hole(number: 1, par: 4, strokeIndex: 7),
            Hole(number: 2, par: 3, strokeIndex: 15),
        ])
        let courseDecoded = try Course.fromCBOR(course.toCBOR())
        XCTAssertEqual(course, courseDecoded)

        // Shot
        let shot = Shot(startLie: .tee, startDistanceToPin: 420.0, endLie: .fairway, endDistanceToPin: 150.0)
        let shotDecoded = try Shot.fromCBOR(shot.toCBOR())
        XCTAssertEqual(shot, shotDecoded)

        // HoleEntry with shots
        let entry = HoleEntry(strokes: 4, shots: [shot])
        let entryDecoded = try HoleEntry.fromCBOR(entry.toCBOR())
        XCTAssertEqual(entry, entryDecoded)

        // HoleEntry without shots
        let entryNil = HoleEntry(strokes: 3)
        let entryNilDecoded = try HoleEntry.fromCBOR(entryNil.toCBOR())
        XCTAssertEqual(entryNil, entryNilDecoded)

        // Lie round-trips
        for lie in Lie.allCases {
            let decoded = try Lie.fromCBOR(lie.toCBOR())
            XCTAssertEqual(lie, decoded)
        }
    }

    func testNoNetworkingImports() throws {
        // Verify no networking frameworks are imported in the library source
        let sourceDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/CRDTKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // CRDTKit
            .appendingPathComponent("Sources/CRDTKit")

        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        let forbidden = ["MultipeerConnectivity", "Network", "NWConnection"]
        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            for keyword in forbidden {
                XCTAssertFalse(
                    content.contains("import \(keyword)"),
                    "\(file.lastPathComponent) imports \(keyword)"
                )
            }
        }
    }
}
