import SwiftUI
import CRDTKit
import CRDTTransport

struct PeerStatusView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List {
            Section {
                HStack {
                    Text("This Device")
                        .font(.headline)
                    Spacer()
                    Text(appState.deviceID.uuid.uuidString.prefix(8))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Section("Connected Peers") {
                if appState.connectedPeers.isEmpty {
                    Text("No peers nearby")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(appState.connectedPeers.values), id: \.deviceID) { peer in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(peer.deviceID.uuid.uuidString.prefix(8))
                                .font(.body.monospaced())
                            HStack {
                                Label {
                                    Text("Seen \(peer.lastSeen, style: .relative) ago")
                                } icon: {
                                    Image(systemName: "eye")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                if let synced = peer.lastSynced {
                                    Label {
                                        Text("Synced \(synced, style: .relative) ago")
                                    } icon: {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            Section("Sync Status") {
                HStack {
                    Text("Rounds")
                    Spacer()
                    Text("\(appState.rounds.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Peers")
    }
}
