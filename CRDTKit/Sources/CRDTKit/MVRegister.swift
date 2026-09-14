import Foundation

public struct MVRegister<T: Hashable & Codable>: Equatable, Codable {
    public struct Entry: Hashable, Codable {
        public let value: T
        public let dot: Dot

        public init(value: T, dot: Dot) {
            self.value = value
            self.dot = dot
        }
    }

    public private(set) var entries: Set<Entry>
    public private(set) var versionVector: VersionVector

    public init() {
        self.entries = []
        self.versionVector = VersionVector()
    }

    init(entries: Set<Entry>, versionVector: VersionVector) {
        self.entries = entries
        self.versionVector = versionVector
    }

    public var values: Set<T> {
        Set(entries.map(\.value))
    }

    public mutating func set(value: T, dot: Dot) {
        entries = [Entry(value: value, dot: dot)]
        versionVector[dot.device] = max(versionVector[dot.device], dot.counter)
    }

    public mutating func merge(_ other: MVRegister<T>) {
        var merged: Set<Entry> = []

        for entry in entries {
            if other.entries.contains(entry)
                || other.versionVector[entry.dot.device] < entry.dot.counter
            {
                merged.insert(entry)
            }
        }
        for entry in other.entries {
            if entries.contains(entry)
                || versionVector[entry.dot.device] < entry.dot.counter
            {
                merged.insert(entry)
            }
        }

        entries = merged
        versionVector.merge(other.versionVector)
    }

    public func merged(with other: MVRegister<T>) -> MVRegister<T> {
        var result = self
        result.merge(other)
        return result
    }

    public func delta(since vv: VersionVector) -> MVRegister<T>? {
        for (device, counter) in versionVector.entries {
            if counter > vv[device] { return self }
        }
        for entry in entries {
            if vv[entry.dot.device] < entry.dot.counter { return self }
        }
        return nil
    }
}
