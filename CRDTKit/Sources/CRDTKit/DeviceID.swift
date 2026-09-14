import Foundation

public struct DeviceID: Hashable, Codable, Comparable {
    public let uuid: UUID

    public init() { self.uuid = UUID() }
    public init(_ uuid: UUID) { self.uuid = uuid }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.uuid.uuidString < rhs.uuid.uuidString
    }
}
