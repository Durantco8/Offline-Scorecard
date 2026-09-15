import Foundation
import CRDTKit
import CRDTTransport
import Combine

@MainActor
final class AppState: ObservableObject {
    let deviceID: DeviceID
    let store: FileRoundStore
    let syncEngine: SyncEngine
    let mcTransport: MCTransport
    private var syncDelegate: SyncDelegate?

    @Published var rounds: [UUID: RoundState] = [:]
    @Published var activeRoundID: UUID?
    @Published var connectedPeers: [DeviceID: PeerStatus] = [:]

    var activeRound: RoundState? {
        get { activeRoundID.flatMap { rounds[$0] } }
        set {
            guard let state = newValue else { return }
            rounds[state.id] = state
            syncEngine.updateRound(state)
            try? store.save(state)
        }
    }

    init() {
        let deviceID = Self.loadOrCreateDeviceID()
        self.deviceID = deviceID

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let storeDir = docs.appendingPathComponent("rounds")
        self.store = try! FileRoundStore(directory: storeDir)

        let transport = MCTransport(deviceID: deviceID)
        self.mcTransport = transport
        self.syncEngine = SyncEngine(deviceID: deviceID, transport: transport)

        // Load persisted rounds
        if let ids = try? store.listRounds() {
            for id in ids {
                if let state = try? store.load(id: id) {
                    rounds[id] = state
                    syncEngine.addRound(state)
                }
            }
        }

        // Wire up callbacks
        let delegate = SyncDelegate(appState: self)
        self.syncDelegate = delegate
        syncEngine.delegate = delegate

        mcTransport.onPeerChange = { [weak self] peerDeviceID, connected in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if connected {
                    self.syncEngine.addPeer(peerDeviceID)
                } else {
                    self.syncEngine.removePeer(peerDeviceID)
                }
                self.connectedPeers = self.syncEngine.peers
            }
        }
    }

    // MARK: - Round lifecycle

    func createRound() -> RoundState {
        let clock = HLC.now(device: deviceID)
        let state = RoundState(id: UUID(), device: deviceID, timestamp: clock)
        rounds[state.id] = state
        syncEngine.addRound(state)
        try? store.save(state)
        activeRoundID = state.id
        return state
    }

    func addPlayer(name: String) {
        guard var state = activeRound else { return }
        let player = PlayerID(UUID())
        state.addPlayer(player, device: deviceID)
        let clock = HLC.now(device: deviceID)
        state.setPlayerName(player, name: name, timestamp: clock, device: deviceID)
        activeRound = state
    }

    func setScore(player: PlayerID, hole: Int, strokes: Int) {
        guard var state = activeRound else { return }
        state.setScore(player: player, hole: hole,
                       entry: HoleEntry(strokes: strokes), device: deviceID)
        activeRound = state
    }

    func resolveConflict(player: PlayerID, hole: Int, strokes: Int) {
        setScore(player: player, hole: hole, strokes: strokes)
    }

    func setCourse(_ course: Course) {
        guard var state = activeRound else { return }
        let clock = HLC.now(device: deviceID)
        state.setCourse(course, timestamp: clock, device: deviceID)
        activeRound = state
    }

    func deleteRound(_ id: UUID) {
        rounds.removeValue(forKey: id)
        syncEngine.removeRound(id)
        try? store.delete(id: id)
        if activeRoundID == id { activeRoundID = nil }
    }

    // MARK: - Networking

    func startNetworking() {
        mcTransport.start()
        syncEngine.startPeriodicSync(interval: 2.0)
    }

    func stopNetworking() {
        syncEngine.stopPeriodicSync()
        mcTransport.stop()
    }

    // MARK: - DeviceID persistence

    private static let deviceIDKey = "com.scorecard.deviceID"

    private static func loadOrCreateDeviceID() -> DeviceID {
        if let str = UserDefaults.standard.string(forKey: deviceIDKey),
           let uuid = UUID(uuidString: str) {
            return DeviceID(uuid)
        }
        let id = DeviceID(UUID())
        UserDefaults.standard.set(id.uuid.uuidString, forKey: deviceIDKey)
        return id
    }
}

// MARK: - SyncEngine delegate (bridges back to MainActor)

private final class SyncDelegate: SyncEngineDelegate {
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    func syncEngine(_ engine: SyncEngine, didUpdateRound roundID: UUID) {
        Task { @MainActor [weak self] in
            guard let self, let appState = self.appState else { return }
            if let state = engine.round(for: roundID) {
                appState.rounds[roundID] = state
                try? appState.store.save(state)
                appState.connectedPeers = engine.peers
            }
        }
    }
}

// MARK: - HLC convenience

extension HLC {
    static func now(device: DeviceID) -> HLC {
        HLC(wall: UInt64(Date().timeIntervalSince1970 * 1000),
            counter: 0, device: device)
    }
}
