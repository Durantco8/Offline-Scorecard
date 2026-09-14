import Foundation

public indirect enum CBORValue {
    case unsigned(UInt64)
    case negative(Int64)
    case bytes(Data)
    case text(String)
    case array([CBORValue])
    case map([(CBORValue, CBORValue)])
    case null
    case bool(Bool)
    case float64(Double)
}

public enum CBORError: Error {
    case unexpectedEnd
    case unsupported
    case invalidUTF8
    case typeMismatch(expected: String, got: CBORValue)
    case missingKey(UInt64)
}

// MARK: - Encoder

public struct CBOREncoder {
    private var data = Data()

    public init() {}

    public mutating func encode(_ value: CBORValue) -> Data {
        data = Data()
        write(value)
        return data
    }

    private mutating func write(_ value: CBORValue) {
        switch value {
        case .unsigned(let n):
            writeHeader(majorType: 0, value: n)
        case .negative(let n):
            writeHeader(majorType: 1, value: UInt64(-(n + 1)))
        case .bytes(let b):
            writeHeader(majorType: 2, value: UInt64(b.count))
            data.append(b)
        case .text(let s):
            let utf8 = Array(s.utf8)
            writeHeader(majorType: 3, value: UInt64(utf8.count))
            data.append(contentsOf: utf8)
        case .array(let items):
            writeHeader(majorType: 4, value: UInt64(items.count))
            for item in items { write(item) }
        case .map(let pairs):
            writeHeader(majorType: 5, value: UInt64(pairs.count))
            for (k, v) in pairs { write(k); write(v) }
        case .null:
            data.append(0xf6)
        case .bool(let b):
            data.append(b ? 0xf5 : 0xf4)
        case .float64(let d):
            data.append(0xfb)
            var bits = d.bitPattern.bigEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
    }

    private mutating func writeHeader(majorType: UInt8, value: UInt64) {
        let mt = majorType << 5
        if value <= 23 {
            data.append(mt | UInt8(value))
        } else if value <= UInt8.max {
            data.append(mt | 24)
            data.append(UInt8(value))
        } else if value <= UInt16.max {
            data.append(mt | 25)
            var v = UInt16(value).bigEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        } else if value <= UInt32.max {
            data.append(mt | 26)
            var v = UInt32(value).bigEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        } else {
            data.append(mt | 27)
            var v = value.bigEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
    }
}

// MARK: - Decoder

public struct CBORDecoder {
    private let data: Data
    private var offset: Int = 0

    public init(data: Data) {
        self.data = data
    }

    public mutating func decode() throws -> CBORValue {
        let initial = try readByte()
        let majorType = initial >> 5
        let additional = initial & 0x1f

        switch majorType {
        case 0:
            return .unsigned(try readArgument(additional))
        case 1:
            return .negative(-1 - Int64(try readArgument(additional)))
        case 2:
            let len = Int(try readArgument(additional))
            return .bytes(try readBytes(len))
        case 3:
            let len = Int(try readArgument(additional))
            let bytes = try readBytes(len)
            guard let s = String(data: bytes, encoding: .utf8) else {
                throw CBORError.invalidUTF8
            }
            return .text(s)
        case 4:
            let count = Int(try readArgument(additional))
            var items: [CBORValue] = []
            items.reserveCapacity(count)
            for _ in 0..<count { items.append(try decode()) }
            return .array(items)
        case 5:
            let count = Int(try readArgument(additional))
            var pairs: [(CBORValue, CBORValue)] = []
            pairs.reserveCapacity(count)
            for _ in 0..<count {
                let k = try decode()
                let v = try decode()
                pairs.append((k, v))
            }
            return .map(pairs)
        case 7:
            switch additional {
            case 20: return .bool(false)
            case 21: return .bool(true)
            case 22: return .null
            case 27:
                let bytes = try readBytes(8)
                let bits = bytes.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
                return .float64(Double(bitPattern: bits))
            default:
                throw CBORError.unsupported
            }
        default:
            throw CBORError.unsupported
        }
    }

    private mutating func readByte() throws -> UInt8 {
        guard offset < data.count else { throw CBORError.unexpectedEnd }
        let b = data[data.startIndex + offset]
        offset += 1
        return b
    }

    private mutating func readBytes(_ count: Int) throws -> Data {
        guard offset + count <= data.count else { throw CBORError.unexpectedEnd }
        let start = data.startIndex + offset
        let result = data[start..<start + count]
        offset += count
        return Data(result)
    }

    private mutating func readArgument(_ additional: UInt8) throws -> UInt64 {
        if additional <= 23 {
            return UInt64(additional)
        }
        switch additional {
        case 24:
            return UInt64(try readByte())
        case 25:
            let bytes = try readBytes(2)
            return UInt64(bytes.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian })
        case 26:
            let bytes = try readBytes(4)
            return UInt64(bytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
        case 27:
            let bytes = try readBytes(8)
            return bytes.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
        default:
            throw CBORError.unsupported
        }
    }
}
