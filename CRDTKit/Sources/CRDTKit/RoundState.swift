import Foundation

public struct RoundState: Equatable, Codable {
    public let id: UUID
    public private(set) var versionVector: VersionVector
    public private(set) var course: LWWRegister<Course>
    public private(set) var players: ORSet<PlayerID>
    public private(set) var playerNames: [PlayerID: LWWRegister<String>]
    public private(set) var entries: [PlayerID: [HoleNumber: MVRegister<HoleEntry>]]

    public init(id: UUID, device: DeviceID, timestamp: HLC, course: Course = Course()) {
        self.id = id
        var vv = VersionVector()
        let counter = vv.increment(for: device)
        self.versionVector = vv
        self.course = LWWRegister(
            value: course,
            timestamp: timestamp,
            dot: Dot(device: device, counter: counter)
        )
        self.players = ORSet()
        self.playerNames = [:]
        self.entries = [:]
    }

    // MARK: - Mutations

    public mutating func setCourse(_ course: Course, timestamp: HLC, device: DeviceID) {
        let dot = nextDot(for: device)
        self.course.set(value: course, timestamp: timestamp, dot: dot)
    }

    public mutating func addPlayer(_ id: PlayerID, device: DeviceID) {
        let dot = nextDot(for: device)
        players.add(id, dot: dot)
    }

    public mutating func removePlayer(_ id: PlayerID) {
        players.remove(id)
        // Keep playerNames and entries — they're harmless and simplify merge.
    }

    public mutating func setPlayerName(_ id: PlayerID, name: String, timestamp: HLC, device: DeviceID) {
        let dot = nextDot(for: device)
        if var reg = playerNames[id] {
            reg.set(value: name, timestamp: timestamp, dot: dot)
            playerNames[id] = reg
        } else {
            playerNames[id] = LWWRegister(value: name, timestamp: timestamp, dot: dot)
        }
    }

    public mutating func setScore(player: PlayerID, hole: HoleNumber, entry: HoleEntry, device: DeviceID) {
        let dot = nextDot(for: device)
        if entries[player] == nil {
            entries[player] = [:]
        }
        if entries[player]![hole] != nil {
            entries[player]![hole]!.set(value: entry, dot: dot)
        } else {
            var reg = MVRegister<HoleEntry>()
            reg.set(value: entry, dot: dot)
            entries[player] = entries[player] ?? [:]
            entries[player]![hole] = reg
        }
    }

    // MARK: - Merge

    public mutating func merge(_ other: RoundState) {
        precondition(id == other.id, "Cannot merge rounds with different IDs")

        course.merge(other.course)
        players.merge(other.players)

        for (pid, otherReg) in other.playerNames {
            if var local = playerNames[pid] {
                local.merge(otherReg)
                playerNames[pid] = local
            } else {
                playerNames[pid] = otherReg
            }
        }

        for (pid, otherHoles) in other.entries {
            if entries[pid] == nil {
                entries[pid] = [:]
            }
            for (hole, otherReg) in otherHoles {
                if var local = entries[pid]![hole] {
                    local.merge(otherReg)
                    entries[pid]![hole] = local
                } else {
                    entries[pid]![hole] = otherReg
                }
            }
        }

        versionVector.merge(other.versionVector)
    }

    public func merged(with other: RoundState) -> RoundState {
        var result = self
        result.merge(other)
        return result
    }

    // MARK: - Delta

    public func delta(since vv: VersionVector) -> RoundDelta {
        var nameDeltas: [PlayerID: LWWRegister<String>] = [:]
        for (pid, reg) in playerNames {
            if let d = reg.delta(since: vv) {
                nameDeltas[pid] = d
            }
        }

        var entryDeltas: [PlayerID: [HoleNumber: MVRegister<HoleEntry>]] = [:]
        for (pid, holes) in entries {
            for (hole, reg) in holes {
                if let d = reg.delta(since: vv) {
                    if entryDeltas[pid] == nil { entryDeltas[pid] = [:] }
                    entryDeltas[pid]![hole] = d
                }
            }
        }

        return RoundDelta(
            roundID: id,
            course: course.delta(since: vv),
            players: players.delta(since: vv),
            playerNames: nameDeltas,
            entries: entryDeltas
        )
    }

    public mutating func applyDelta(_ delta: RoundDelta) {
        precondition(id == delta.roundID, "Delta round ID mismatch")

        if let courseDelta = delta.course {
            course.merge(courseDelta)
        }
        if let playersDelta = delta.players {
            players.merge(playersDelta)
        }
        for (pid, reg) in delta.playerNames {
            if var local = playerNames[pid] {
                local.merge(reg)
                playerNames[pid] = local
            } else {
                playerNames[pid] = reg
            }
        }
        for (pid, holes) in delta.entries {
            if entries[pid] == nil { entries[pid] = [:] }
            for (hole, reg) in holes {
                if var local = entries[pid]![hole] {
                    local.merge(reg)
                    entries[pid]![hole] = local
                } else {
                    entries[pid]![hole] = reg
                }
            }
        }

        // Update VV from merged sub-CRDTs
        versionVector.merge(course.dot.device == course.dot.device ? VersionVector([course.dot.device: course.dot.counter]) : VersionVector())
        versionVector.merge(players.versionVector)
        for (_, reg) in playerNames {
            versionVector.merge(VersionVector([reg.dot.device: reg.dot.counter]))
        }
        for (_, holes) in entries {
            for (_, reg) in holes {
                versionVector.merge(reg.versionVector)
            }
        }
    }

    // MARK: - Private

    private mutating func nextDot(for device: DeviceID) -> Dot {
        let counter = versionVector.increment(for: device)
        return Dot(device: device, counter: counter)
    }
}

public struct RoundDelta: Equatable, Codable {
    public let roundID: UUID
    public var course: LWWRegister<Course>?
    public var players: ORSet<PlayerID>?
    public var playerNames: [PlayerID: LWWRegister<String>]
    public var entries: [PlayerID: [HoleNumber: MVRegister<HoleEntry>]]

    public init(
        roundID: UUID,
        course: LWWRegister<Course>? = nil,
        players: ORSet<PlayerID>? = nil,
        playerNames: [PlayerID: LWWRegister<String>] = [:],
        entries: [PlayerID: [HoleNumber: MVRegister<HoleEntry>]] = [:]
    ) {
        self.roundID = roundID
        self.course = course
        self.players = players
        self.playerNames = playerNames
        self.entries = entries
    }
}
