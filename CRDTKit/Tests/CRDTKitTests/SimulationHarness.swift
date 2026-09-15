import Foundation
@testable import CRDTKit

// MARK: - SimNetwork

final class SimNetwork {
    private(set) var transports: [DeviceID: SimTransport] = [:]
    var connectivity: [DeviceID: Set<DeviceID>] = [:]
    private(set) var messageQueue: [(from: DeviceID, to: DeviceID, data: Data)] = []
    var dropRate: Double = 0
    var duplicateRate: Double = 0

    func register(_ transport: SimTransport) {
        transports[transport.deviceID] = transport
    }

    func enqueue(from: DeviceID, to: DeviceID, data: Data) {
        guard connectivity[from]?.contains(to) == true else { return }
        messageQueue.append((from: from, to: to, data: data))
    }

    @discardableResult
    func deliverOne(rng: inout SeededRNG) -> Bool {
        guard !messageQueue.isEmpty else { return false }
        let index = Int(rng.next() % UInt64(messageQueue.count))
        let msg = messageQueue.remove(at: index)

        // Drop
        if dropRate > 0, Double(rng.next() % 1000) / 1000.0 < dropRate {
            return true
        }
        // Duplicate — put a copy back before delivering
        if duplicateRate > 0, Double(rng.next() % 1000) / 1000.0 < duplicateRate {
            messageQueue.append(msg)
        }

        transports[msg.to]?.onReceive?(msg.data, msg.from)
        return true
    }

    func deliverAll(rng: inout SeededRNG) {
        while deliverOne(rng: &rng) {}
    }

    func partition(groups: [[DeviceID]]) {
        connectivity = [:]
        for group in groups {
            for a in group {
                for b in group where a != b {
                    connectivity[a, default: []].insert(b)
                }
            }
        }
    }

    func healAll() {
        partition(groups: [Array(transports.keys)])
    }

    func peers(of device: DeviceID) -> Set<DeviceID> {
        connectivity[device] ?? []
    }

    var pendingCount: Int { messageQueue.count }

    func clearQueue() { messageQueue.removeAll() }
}

// MARK: - SimTransport

final class SimTransport: Transport {
    let deviceID: DeviceID
    unowned let network: SimNetwork
    var onReceive: ((Data, DeviceID) -> Void)?

    init(deviceID: DeviceID, network: SimNetwork) {
        self.deviceID = deviceID
        self.network = network
        network.register(self)
    }

    func send(_ data: Data, to peer: DeviceID) {
        network.enqueue(from: deviceID, to: peer, data: data)
    }

    func broadcast(_ data: Data) {
        for peer in network.peers(of: deviceID) {
            network.enqueue(from: deviceID, to: peer, data: data)
        }
    }
}

// MARK: - SimReplica

final class SimReplica {
    var state: RoundState
    let device: DeviceID
    var clock: HLC
    let transport: SimTransport
    var peerVVs: [DeviceID: VersionVector] = [:]
    let roundID: UUID
    private let network: SimNetwork
    var idempotencyFailure: String?
    var needsSync = false
    private var preCrashCounter: UInt64 = 0

    init(roundID: UUID, device: DeviceID, network: SimNetwork, wallClock: UInt64) {
        self.roundID = roundID
        self.device = device
        self.network = network
        self.clock = HLC(wall: wallClock, counter: 0, device: device)
        self.transport = SimTransport(deviceID: device, network: network)
        self.state = RoundState(id: roundID, device: device, timestamp: clock)

        self.transport.onReceive = { [weak self] data, from in
            self?.handleReceive(data: data, from: from)
        }
    }

    func writeScore(player: PlayerID, hole: HoleNumber, strokes: Int) {
        clock.tick(now: clock.wall + 1)
        state.setScore(player: player, hole: hole, entry: HoleEntry(strokes: strokes), device: device)
    }

    func addPlayer(_ id: PlayerID) {
        state.addPlayer(id, device: device)
    }

    func sync() {
        for peerID in network.peers(of: device) {
            let peerVV = peerVVs[peerID] ?? VersionVector()
            let delta = state.delta(since: peerVV)
            guard !delta.isEmpty else { continue }
            let data = Wire.encode(delta)
            transport.send(data, to: peerID)
            peerVVs[peerID] = state.versionVector
        }
    }

    func handleReceive(data: Data, from: DeviceID) {
        guard let delta = try? Wire.decode(data) else { return }
        guard delta.roundID == roundID else { return }

        state.applyDelta(delta)

        // Idempotency: applying the same delta again must be a no-op
        let afterFirst = state
        state.applyDelta(delta)
        if state != afterFirst {
            idempotencyFailure = "Delta not idempotent on \(device)"
        }

        // Only safe to write once VV for our device recovers to pre-crash level
        if state.versionVector[device] >= preCrashCounter {
            needsSync = false
        }
    }

    func crash(keepState: Bool) {
        peerVVs = [:]
        if !keepState {
            // Remember highest counter before wiping so we don't reuse dots.
            // Models persisting the counter separately from CRDT state.
            // max() handles double-crash: state VV resets but counter must not go down.
            preCrashCounter = max(preCrashCounter, state.versionVector[device])
            // Fresh state with wall=0 so the init course loses LWW to any established course
            state = RoundState(id: roundID, device: device,
                timestamp: HLC(wall: 0, counter: 0, device: device))
            needsSync = true
        }
    }
}

// MARK: - Write tracking

struct WriteRecord {
    let device: DeviceID
    let player: PlayerID
    let hole: HoleNumber
    let strokes: Int
    let dot: Dot
    let vvAtWrite: VersionVector
}

final class WriteLog {
    var records: [WriteRecord] = []

    func record(_ r: WriteRecord) {
        records.append(r)
    }

    /// Remove writes that were irrecoverably lost (message drops + crashes).
    /// Uses the converged state to determine which writes actually survived.
    func removeLostWrites(
        finalEntries: [PlayerID: [HoleNumber: MVRegister<HoleEntry>]]
    ) {
        records.removeAll { record in
            guard let reg = finalEntries[record.player]?[record.hole] else {
                return true  // register absent — write lost
            }
            // If the register's VV covers this dot, the write was seen
            // (possibly superseded). Keep it for the superseded check.
            if reg.versionVector[record.dot.device] >= record.dot.counter {
                return false
            }
            // VV doesn't cover it — keep only if the entry is actually present
            return !reg.entries.contains { $0.dot == record.dot }
        }
    }
}

// MARK: - RoundDelta convenience

extension RoundDelta {
    var isEmpty: Bool {
        course == nil && players == nil && playerNames.isEmpty && entries.isEmpty
    }
}
