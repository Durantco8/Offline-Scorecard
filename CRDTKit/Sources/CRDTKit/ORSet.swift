import Foundation

public struct ORSet<T: Hashable & Codable>: Equatable, Codable {
    public struct Entry: Hashable, Codable {
        public let element: T
        public let dot: Dot

        public init(element: T, dot: Dot) {
            self.element = element
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

    public var elements: Set<T> {
        Set(entries.map(\.element))
    }

    public mutating func add(_ element: T, dot: Dot) {
        entries.insert(Entry(element: element, dot: dot))
        versionVector[dot.device] = max(versionVector[dot.device], dot.counter)
    }

    public mutating func remove(_ element: T) {
        entries = entries.filter { $0.element != element }
    }

    public mutating func merge(_ other: ORSet<T>) {
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

    public func merged(with other: ORSet<T>) -> ORSet<T> {
        var result = self
        result.merge(other)
        return result
    }

    /// Returns self if this set has state the querier hasn't seen, nil otherwise.
    ///
    /// Full-state granularity. Entry-level deltas require per-mutation delta
    /// accumulation (see MVRegister.delta docs). Players set is small enough
    /// that full-state deltas are effectively free.
    public func delta(since vv: VersionVector) -> ORSet<T>? {
        for (device, counter) in versionVector.entries {
            if counter > vv[device] { return self }
        }
        return nil
    }
}
