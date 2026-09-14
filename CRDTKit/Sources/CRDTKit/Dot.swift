import Foundation

public struct Dot: Hashable, Codable {
    public let device: DeviceID
    public let counter: UInt64

    public init(device: DeviceID, counter: UInt64) {
        self.device = device
        self.counter = counter
    }
}
