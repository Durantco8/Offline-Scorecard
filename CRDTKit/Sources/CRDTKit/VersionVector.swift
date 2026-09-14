import Foundation

public struct VersionVector: Equatable, Codable, Hashable {
    public var entries: [DeviceID: UInt64]

    public init(_ entries: [DeviceID: UInt64] = [:]) {
        self.entries = entries
    }

    public subscript(device: DeviceID) -> UInt64 {
        get { entries[device] ?? 0 }
        set {
            if newValue == 0 {
                entries.removeValue(forKey: device)
            } else {
                entries[device] = newValue
            }
        }
    }

    @discardableResult
    public mutating func increment(for device: DeviceID) -> UInt64 {
        let next = self[device] + 1
        self[device] = next
        return next
    }

    public func dominates(_ other: VersionVector) -> Bool {
        for (device, counter) in other.entries {
            if self[device] < counter { return false }
        }
        return true
    }

    public mutating func merge(_ other: VersionVector) {
        for (device, counter) in other.entries {
            self[device] = max(self[device], counter)
        }
    }

    public func merged(with other: VersionVector) -> VersionVector {
        var result = self
        result.merge(other)
        return result
    }
}
