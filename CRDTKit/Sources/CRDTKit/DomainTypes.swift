import Foundation

public struct PlayerID: Hashable, Codable, Comparable {
    public let uuid: UUID

    public init() { self.uuid = UUID() }
    public init(_ uuid: UUID) { self.uuid = uuid }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.uuid.uuidString < rhs.uuid.uuidString
    }
}

public typealias HoleNumber = Int

public enum Lie: Int, Hashable, Codable, CaseIterable {
    case tee = 0
    case fairway = 1
    case rough = 2
    case sand = 3
    case green = 4
    case recovery = 5
}

public struct Shot: Hashable, Codable {
    public var startLie: Lie
    public var startDistanceToPin: Double
    public var endLie: Lie
    public var endDistanceToPin: Double

    public init(startLie: Lie, startDistanceToPin: Double, endLie: Lie, endDistanceToPin: Double) {
        self.startLie = startLie
        self.startDistanceToPin = startDistanceToPin
        self.endLie = endLie
        self.endDistanceToPin = endDistanceToPin
    }
}

public struct Hole: Hashable, Codable {
    public var number: HoleNumber
    public var par: Int
    public var strokeIndex: Int

    public init(number: HoleNumber, par: Int, strokeIndex: Int) {
        self.number = number
        self.par = par
        self.strokeIndex = strokeIndex
    }
}

public struct Course: Hashable, Codable {
    public var holes: [Hole]

    public init(holes: [Hole] = []) {
        self.holes = holes
    }
}

public struct HoleEntry: Hashable, Codable {
    public var strokes: Int
    public var shots: [Shot]?

    public init(strokes: Int, shots: [Shot]? = nil) {
        self.strokes = strokes
        self.shots = shots
    }
}
