import Foundation

public struct HLC: Hashable, Codable, Comparable {
    public var wall: UInt64
    public var counter: UInt32
    public var device: DeviceID

    public init(wall: UInt64, counter: UInt32, device: DeviceID) {
        self.wall = wall
        self.counter = counter
        self.device = device
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.wall != rhs.wall { return lhs.wall < rhs.wall }
        if lhs.counter != rhs.counter { return lhs.counter < rhs.counter }
        return lhs.device < rhs.device
    }

    public mutating func tick(now: UInt64) {
        let newWall = max(wall, now)
        counter = (newWall == wall) ? counter + 1 : 0
        wall = newWall
    }

    public mutating func receive(remote: HLC, now: UInt64) {
        let newWall = max(wall, max(remote.wall, now))
        if newWall == wall && newWall == remote.wall {
            counter = max(counter, remote.counter) + 1
        } else if newWall == wall {
            counter += 1
        } else if newWall == remote.wall {
            counter = remote.counter + 1
        } else {
            counter = 0
        }
        wall = newWall
    }
}
