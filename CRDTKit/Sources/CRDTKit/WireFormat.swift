import Foundation

public protocol WireCodable {
    func toCBOR() -> CBORValue
    static func fromCBOR(_ cbor: CBORValue) throws -> Self
}

// MARK: - Helpers

func cborMap(_ pairs: (UInt64, CBORValue)...) -> CBORValue {
    .map(pairs.map { (.unsigned($0.0), $0.1) })
}

func readCBORMap(_ cbor: CBORValue) throws -> [UInt64: CBORValue] {
    guard case .map(let pairs) = cbor else {
        throw CBORError.typeMismatch(expected: "map", got: cbor)
    }
    var result: [UInt64: CBORValue] = [:]
    for (k, v) in pairs {
        guard case .unsigned(let key) = k else {
            throw CBORError.typeMismatch(expected: "unsigned key", got: k)
        }
        result[key] = v
    }
    return result
}

func requireKey(_ m: [UInt64: CBORValue], _ key: UInt64) throws -> CBORValue {
    guard let v = m[key] else { throw CBORError.missingKey(key) }
    return v
}

func requireUnsigned(_ v: CBORValue) throws -> UInt64 {
    guard case .unsigned(let n) = v else {
        throw CBORError.typeMismatch(expected: "unsigned", got: v)
    }
    return n
}

func requireBytes(_ v: CBORValue) throws -> Data {
    guard case .bytes(let d) = v else {
        throw CBORError.typeMismatch(expected: "bytes", got: v)
    }
    return d
}

func requireText(_ v: CBORValue) throws -> String {
    guard case .text(let s) = v else {
        throw CBORError.typeMismatch(expected: "text", got: v)
    }
    return s
}

func requireArray(_ v: CBORValue) throws -> [CBORValue] {
    guard case .array(let a) = v else {
        throw CBORError.typeMismatch(expected: "array", got: v)
    }
    return a
}

func requireFloat64(_ v: CBORValue) throws -> Double {
    guard case .float64(let d) = v else {
        throw CBORError.typeMismatch(expected: "float64", got: v)
    }
    return d
}

// MARK: - UUID

func uuidToCBOR(_ uuid: UUID) -> CBORValue {
    var bytes = [UInt8](repeating: 0, count: 16)
    let u = uuid.uuid
    bytes[0] = u.0; bytes[1] = u.1; bytes[2] = u.2; bytes[3] = u.3
    bytes[4] = u.4; bytes[5] = u.5; bytes[6] = u.6; bytes[7] = u.7
    bytes[8] = u.8; bytes[9] = u.9; bytes[10] = u.10; bytes[11] = u.11
    bytes[12] = u.12; bytes[13] = u.13; bytes[14] = u.14; bytes[15] = u.15
    return .bytes(Data(bytes))
}

func uuidFromCBOR(_ cbor: CBORValue) throws -> UUID {
    let data = try requireBytes(cbor)
    guard data.count == 16 else {
        throw CBORError.typeMismatch(expected: "16-byte UUID", got: cbor)
    }
    let b = [UInt8](data)
    return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                       b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
}

// MARK: - Primitive conformances

extension DeviceID: WireCodable {
    public func toCBOR() -> CBORValue { uuidToCBOR(uuid) }
    public static func fromCBOR(_ cbor: CBORValue) throws -> DeviceID {
        DeviceID(try uuidFromCBOR(cbor))
    }
}

extension PlayerID: WireCodable {
    public func toCBOR() -> CBORValue { uuidToCBOR(uuid) }
    public static func fromCBOR(_ cbor: CBORValue) throws -> PlayerID {
        PlayerID(try uuidFromCBOR(cbor))
    }
}

extension Dot: WireCodable {
    public func toCBOR() -> CBORValue {
        .array([device.toCBOR(), .unsigned(counter)])
    }
    public static func fromCBOR(_ cbor: CBORValue) throws -> Dot {
        let a = try requireArray(cbor)
        return Dot(device: try DeviceID.fromCBOR(a[0]), counter: try requireUnsigned(a[1]))
    }
}

extension HLC: WireCodable {
    public func toCBOR() -> CBORValue {
        .array([.unsigned(wall), .unsigned(UInt64(counter)), device.toCBOR()])
    }
    public static func fromCBOR(_ cbor: CBORValue) throws -> HLC {
        let a = try requireArray(cbor)
        return HLC(
            wall: try requireUnsigned(a[0]),
            counter: UInt32(try requireUnsigned(a[1])),
            device: try DeviceID.fromCBOR(a[2])
        )
    }
}

extension VersionVector: WireCodable {
    public func toCBOR() -> CBORValue {
        .map(entries.map { (key: $0.key.toCBOR(), value: .unsigned($0.value)) })
    }
    public static func fromCBOR(_ cbor: CBORValue) throws -> VersionVector {
        guard case .map(let pairs) = cbor else {
            throw CBORError.typeMismatch(expected: "map", got: cbor)
        }
        var vv = VersionVector()
        for (k, v) in pairs {
            let device = try DeviceID.fromCBOR(k)
            let counter = try requireUnsigned(v)
            vv[device] = counter
        }
        return vv
    }
}

// MARK: - Domain type conformances

extension Lie: WireCodable {
    public func toCBOR() -> CBORValue { .unsigned(UInt64(rawValue)) }
    public static func fromCBOR(_ cbor: CBORValue) throws -> Lie {
        let n = try requireUnsigned(cbor)
        guard let lie = Lie(rawValue: Int(n)) else {
            throw CBORError.typeMismatch(expected: "Lie (0-5)", got: cbor)
        }
        return lie
    }
}

extension Shot: WireCodable {
    public func toCBOR() -> CBORValue {
        .array([startLie.toCBOR(), .float64(startDistanceToPin),
                endLie.toCBOR(), .float64(endDistanceToPin)])
    }
    public static func fromCBOR(_ cbor: CBORValue) throws -> Shot {
        let a = try requireArray(cbor)
        return Shot(
            startLie: try Lie.fromCBOR(a[0]),
            startDistanceToPin: try requireFloat64(a[1]),
            endLie: try Lie.fromCBOR(a[2]),
            endDistanceToPin: try requireFloat64(a[3])
        )
    }
}

extension Hole: WireCodable {
    public func toCBOR() -> CBORValue {
        .array([.unsigned(UInt64(number)), .unsigned(UInt64(par)), .unsigned(UInt64(strokeIndex))])
    }
    public static func fromCBOR(_ cbor: CBORValue) throws -> Hole {
        let a = try requireArray(cbor)
        return Hole(
            number: Int(try requireUnsigned(a[0])),
            par: Int(try requireUnsigned(a[1])),
            strokeIndex: Int(try requireUnsigned(a[2]))
        )
    }
}

extension Course: WireCodable {
    public func toCBOR() -> CBORValue {
        .array(holes.map { $0.toCBOR() })
    }
    public static func fromCBOR(_ cbor: CBORValue) throws -> Course {
        let a = try requireArray(cbor)
        return Course(holes: try a.map { try Hole.fromCBOR($0) })
    }
}

extension HoleEntry: WireCodable {
    public func toCBOR() -> CBORValue {
        let shotsValue: CBORValue = shots.map { .array($0.map { $0.toCBOR() }) } ?? .null
        return cborMap((0, .unsigned(UInt64(strokes))), (1, shotsValue))
    }
    public static func fromCBOR(_ cbor: CBORValue) throws -> HoleEntry {
        let m = try readCBORMap(cbor)
        let strokes = Int(try requireUnsigned(try requireKey(m, 0)))
        let shotsValue = try requireKey(m, 1)
        let shots: [Shot]?
        if case .null = shotsValue {
            shots = nil
        } else {
            shots = try requireArray(shotsValue).map { try Shot.fromCBOR($0) }
        }
        return HoleEntry(strokes: strokes, shots: shots)
    }
}

// MARK: - CRDT conformances

extension LWWRegister: WireCodable where T: WireCodable {
    public func toCBOR() -> CBORValue {
        cborMap((0, value.toCBOR()), (1, timestamp.toCBOR()), (2, dot.toCBOR()))
    }
    public static func fromCBOR(_ cbor: CBORValue) throws -> LWWRegister<T> {
        let m = try readCBORMap(cbor)
        return LWWRegister(
            value: try T.fromCBOR(try requireKey(m, 0)),
            timestamp: try HLC.fromCBOR(try requireKey(m, 1)),
            dot: try Dot.fromCBOR(try requireKey(m, 2))
        )
    }
}

extension MVRegister.Entry: WireCodable where T: WireCodable {
    public func toCBOR() -> CBORValue {
        .array([value.toCBOR(), dot.toCBOR()])
    }
    public static func fromCBOR(_ cbor: CBORValue) throws -> MVRegister<T>.Entry {
        let a = try requireArray(cbor)
        return MVRegister<T>.Entry(value: try T.fromCBOR(a[0]), dot: try Dot.fromCBOR(a[1]))
    }
}

extension MVRegister: WireCodable where T: WireCodable {
    public func toCBOR() -> CBORValue {
        cborMap(
            (0, .array(entries.map { $0.toCBOR() })),
            (1, versionVector.toCBOR())
        )
    }
    public static func fromCBOR(_ cbor: CBORValue) throws -> MVRegister<T> {
        let m = try readCBORMap(cbor)
        let entryArray = try requireArray(try requireKey(m, 0))
        let entries = Set(try entryArray.map { try MVRegister<T>.Entry.fromCBOR($0) })
        let vv = try VersionVector.fromCBOR(try requireKey(m, 1))
        return MVRegister(entries: entries, versionVector: vv)
    }
}

extension ORSet.Entry: WireCodable where T: WireCodable {
    public func toCBOR() -> CBORValue {
        .array([element.toCBOR(), dot.toCBOR()])
    }
    public static func fromCBOR(_ cbor: CBORValue) throws -> ORSet<T>.Entry {
        let a = try requireArray(cbor)
        return ORSet<T>.Entry(element: try T.fromCBOR(a[0]), dot: try Dot.fromCBOR(a[1]))
    }
}

extension ORSet: WireCodable where T: WireCodable {
    public func toCBOR() -> CBORValue {
        cborMap(
            (0, .array(entries.map { $0.toCBOR() })),
            (1, versionVector.toCBOR())
        )
    }
    public static func fromCBOR(_ cbor: CBORValue) throws -> ORSet<T> {
        let m = try readCBORMap(cbor)
        let entryArray = try requireArray(try requireKey(m, 0))
        let entries = Set(try entryArray.map { try ORSet<T>.Entry.fromCBOR($0) })
        let vv = try VersionVector.fromCBOR(try requireKey(m, 1))
        return ORSet(entries: entries, versionVector: vv)
    }
}

// MARK: - String conformance for LWWRegister<String>

extension String: WireCodable {
    public func toCBOR() -> CBORValue { .text(self) }
    public static func fromCBOR(_ cbor: CBORValue) throws -> String {
        try requireText(cbor)
    }
}

// MARK: - RoundDelta wire format

extension RoundDelta: WireCodable {
    public func toCBOR() -> CBORValue {
        let courseValue: CBORValue = course?.toCBOR() ?? .null
        let playersValue: CBORValue = players?.toCBOR() ?? .null

        let namesPairs: [(CBORValue, CBORValue)] = playerNames.map {
            ($0.key.toCBOR(), $0.value.toCBOR())
        }

        let entriesPairs: [(CBORValue, CBORValue)] = entries.map { (pid, holes) in
            let holePairs: [(CBORValue, CBORValue)] = holes.map { (hole, reg) in
                (.unsigned(UInt64(hole)), reg.toCBOR())
            }
            return (pid.toCBOR(), CBORValue.map(holePairs))
        }

        return cborMap(
            (0, uuidToCBOR(roundID)),
            (1, courseValue),
            (2, playersValue),
            (3, .map(namesPairs)),
            (4, .map(entriesPairs)),
            (5, .unsigned(1))
        )
    }

    public static func fromCBOR(_ cbor: CBORValue) throws -> RoundDelta {
        let m = try readCBORMap(cbor)

        let version = try requireUnsigned(try requireKey(m, 5))
        guard version == 1 else {
            throw CBORError.typeMismatch(expected: "version 1", got: .unsigned(version))
        }

        let roundID = try uuidFromCBOR(try requireKey(m, 0))

        let courseValue = try requireKey(m, 1)
        let course: LWWRegister<Course>?
        if case .null = courseValue { course = nil }
        else { course = try LWWRegister<Course>.fromCBOR(courseValue) }

        let playersValue = try requireKey(m, 2)
        let players: ORSet<PlayerID>?
        if case .null = playersValue { players = nil }
        else { players = try ORSet<PlayerID>.fromCBOR(playersValue) }

        let namesMap = try requireKey(m, 3)
        var playerNames: [PlayerID: LWWRegister<String>] = [:]
        if case .map(let pairs) = namesMap {
            for (k, v) in pairs {
                let pid = try PlayerID.fromCBOR(k)
                playerNames[pid] = try LWWRegister<String>.fromCBOR(v)
            }
        }

        let entriesMap = try requireKey(m, 4)
        var entries: [PlayerID: [HoleNumber: MVRegister<HoleEntry>]] = [:]
        if case .map(let pidPairs) = entriesMap {
            for (pidCbor, holesCbor) in pidPairs {
                let pid = try PlayerID.fromCBOR(pidCbor)
                guard case .map(let holePairs) = holesCbor else {
                    throw CBORError.typeMismatch(expected: "map", got: holesCbor)
                }
                var holes: [HoleNumber: MVRegister<HoleEntry>] = [:]
                for (holeCbor, regCbor) in holePairs {
                    let hole = Int(try requireUnsigned(holeCbor))
                    holes[hole] = try MVRegister<HoleEntry>.fromCBOR(regCbor)
                }
                entries[pid] = holes
            }
        }

        return RoundDelta(
            roundID: roundID,
            course: course,
            players: players,
            playerNames: playerNames,
            entries: entries
        )
    }
}

// MARK: - Convenience encode/decode

public enum Wire {
    public static func encode(_ delta: RoundDelta) -> Data {
        var encoder = CBOREncoder()
        return encoder.encode(delta.toCBOR())
    }

    public static func decode(_ data: Data) throws -> RoundDelta {
        var decoder = CBORDecoder(data: data)
        let cbor = try decoder.decode()
        return try RoundDelta.fromCBOR(cbor)
    }
}
