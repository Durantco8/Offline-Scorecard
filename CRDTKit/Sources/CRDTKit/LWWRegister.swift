import Foundation

public struct LWWRegister<T: Equatable & Codable & Hashable>: Equatable, Codable, Hashable {
    public private(set) var value: T
    public private(set) var timestamp: HLC
    public private(set) var dot: Dot

    public init(value: T, timestamp: HLC, dot: Dot) {
        self.value = value
        self.timestamp = timestamp
        self.dot = dot
    }

    public mutating func set(value: T, timestamp: HLC, dot: Dot) {
        if timestamp > self.timestamp {
            self.value = value
            self.timestamp = timestamp
            self.dot = dot
        }
    }

    public mutating func merge(_ other: LWWRegister<T>) {
        if other.timestamp > timestamp {
            value = other.value
            timestamp = other.timestamp
            dot = other.dot
        }
    }

    public func merged(with other: LWWRegister<T>) -> LWWRegister<T> {
        var result = self
        result.merge(other)
        return result
    }

    public func delta(since vv: VersionVector) -> LWWRegister<T>? {
        vv[dot.device] < dot.counter ? self : nil
    }
}
