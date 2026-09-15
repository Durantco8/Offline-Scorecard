import Foundation
import CRDTKit

/// Tracks a connected peer's sync state.
public struct PeerStatus {
    public let deviceID: DeviceID
    public internal(set) var lastSynced: Date?
    public internal(set) var lastSeen: Date

    public init(deviceID: DeviceID, lastSeen: Date = Date()) {
        self.deviceID = deviceID
        self.lastSeen = lastSeen
    }
}

/// Delegate for SyncEngine events that require app-layer action.
public protocol SyncEngineDelegate: AnyObject {
    /// Called when remote state has been merged into the local round.
    /// The app should persist the updated state.
    func syncEngine(_ engine: SyncEngine, didUpdateRound roundID: UUID)
}

/// Anti-entropy gossip engine.
///
/// Protocol:
/// 1. Periodically (or on-demand) send `.vvDigest` to each connected peer
/// 2. On receiving a digest, compare against local state:
///    - If local is ahead, send `.delta` with the diff
///    - Always reply with own `.vvDigest` so the peer can do the same
/// 3. On receiving a delta, merge it and notify the delegate
///
/// The engine owns no transport — it calls `send` on the Transport protocol
/// and registers as the `onReceive` handler.
public final class SyncEngine {
    public let deviceID: DeviceID
    public weak var delegate: SyncEngineDelegate?
    public private(set) var peers: [DeviceID: PeerStatus] = [:]

    private var rounds: [UUID: RoundState] = [:]
    private var peerVVs: [DeviceID: [UUID: VersionVector]] = [:]
    private let transport: Transport
    private var syncTimer: Timer?

    public init(deviceID: DeviceID, transport: Transport) {
        self.deviceID = deviceID
        self.transport = transport

        transport.onReceive = { [weak self] data, from in
            self?.handleReceive(data: data, from: from)
        }
    }

    // MARK: - Round management

    public func addRound(_ state: RoundState) {
        rounds[state.id] = state
    }

    public func updateRound(_ state: RoundState) {
        rounds[state.id] = state
    }

    public func round(for id: UUID) -> RoundState? {
        rounds[id]
    }

    public func removeRound(_ id: UUID) {
        rounds.removeValue(forKey: id)
        for peer in peerVVs.keys {
            peerVVs[peer]?.removeValue(forKey: id)
        }
    }

    // MARK: - Peer management

    public func addPeer(_ deviceID: DeviceID) {
        if peers[deviceID] == nil {
            peers[deviceID] = PeerStatus(deviceID: deviceID)
        }
        // New peer — send digests for all rounds immediately
        sendDigests(to: deviceID)
    }

    public func removePeer(_ deviceID: DeviceID) {
        peers.removeValue(forKey: deviceID)
        peerVVs.removeValue(forKey: deviceID)
    }

    // MARK: - Sync

    /// Send VV digests for all rounds to all connected peers.
    public func syncAll() {
        for peerID in peers.keys {
            sendDigests(to: peerID)
        }
    }

    /// Send VV digests for all rounds to a specific peer.
    public func sendDigests(to peerID: DeviceID) {
        for (roundID, state) in rounds {
            let msg = SyncMessage.vvDigest(roundID: roundID, vv: state.versionVector)
            transport.send(msg.encode(), to: peerID)
        }
    }

    /// Start periodic sync at the given interval.
    public func startPeriodicSync(interval: TimeInterval = 2.0) {
        stopPeriodicSync()
        syncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.syncAll()
        }
    }

    public func stopPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    // MARK: - Receive handling

    private func handleReceive(data: Data, from peerID: DeviceID) {
        guard let message = try? SyncMessage.decode(data) else { return }

        // Update peer tracking
        peers[peerID]?.lastSeen = Date()

        switch message {
        case .vvDigest(let roundID, let remoteVV):
            handleDigest(roundID: roundID, remoteVV: remoteVV, from: peerID)
        case .delta(let delta):
            handleDelta(delta, from: peerID)
        }
    }

    private func handleDigest(roundID: UUID, remoteVV: VersionVector, from peerID: DeviceID) {
        guard let state = rounds[roundID] else { return }

        // If we have state the peer hasn't seen, send a delta
        let peerVV = peerVVs[peerID]?[roundID] ?? remoteVV
        let delta = state.delta(since: peerVV)

        if !delta.isEmpty {
            transport.send(SyncMessage.delta(delta).encode(), to: peerID)
            peerVVs[peerID, default: [:]][roundID] = state.versionVector
        }

        // Reply with our own digest so the peer can send us what we're missing.
        // Only reply if the peer's VV shows they might have state we lack.
        if !state.versionVector.dominates(remoteVV) {
            let reply = SyncMessage.vvDigest(roundID: roundID, vv: state.versionVector)
            transport.send(reply.encode(), to: peerID)
        }
    }

    private func handleDelta(_ delta: RoundDelta, from peerID: DeviceID) {
        guard var state = rounds[delta.roundID] else { return }

        state.applyDelta(delta)
        rounds[delta.roundID] = state

        // Update peer VV tracking — peer has at least this state
        peerVVs[peerID, default: [:]][delta.roundID] = state.versionVector

        // Track sync time
        peers[peerID]?.lastSynced = Date()

        delegate?.syncEngine(self, didUpdateRound: delta.roundID)
    }
}
