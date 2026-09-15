import SwiftUI
import CRDTKit

struct RoundListView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingNewRound = false

    private var sortedRounds: [RoundState] {
        appState.rounds.values.sorted { a, b in
            a.id.uuidString < b.id.uuidString
        }
    }

    var body: some View {
        List {
            if !appState.connectedPeers.isEmpty {
                Section("Nearby Devices") {
                    ForEach(Array(appState.connectedPeers.values), id: \.deviceID) { peer in
                        HStack {
                            Image(systemName: "iphone.radiowaves.left.and.right")
                                .foregroundStyle(.green)
                            Text(peer.deviceID.uuid.uuidString.prefix(8))
                                .font(.caption.monospaced())
                            Spacer()
                            if let lastSync = peer.lastSynced {
                                Text(lastSync, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Rounds") {
                if sortedRounds.isEmpty {
                    Text("No rounds yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedRounds, id: \.id) { round in
                        NavigationLink(value: round.id) {
                            RoundRow(round: round)
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            appState.deleteRound(sortedRounds[index].id)
                        }
                    }
                }
            }
        }
        .navigationTitle("ScoreCard")
        .navigationDestination(for: UUID.self) { roundID in
            ScorecardView(roundID: roundID)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    _ = appState.createRound()
                    showingNewRound = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    PeerStatusView()
                } label: {
                    peerIndicator
                }
            }
        }
        .sheet(isPresented: $showingNewRound) {
            if let id = appState.activeRoundID {
                NavigationStack {
                    CourseSetupView(roundID: id, isInitialSetup: true)
                }
            }
        }
    }

    @ViewBuilder
    private var peerIndicator: some View {
        let count = appState.connectedPeers.count
        HStack(spacing: 4) {
            Image(systemName: count > 0 ? "wifi" : "wifi.slash")
                .foregroundStyle(count > 0 ? .green : .secondary)
            if count > 0 {
                Text("\(count)")
                    .font(.caption)
            }
        }
    }
}

private struct RoundRow: View {
    let round: RoundState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(round.course.value.holes.isEmpty
                 ? "New Round"
                 : "\(round.course.value.holes.count) holes")
                .font(.headline)
            HStack {
                Text("\(round.players.elements.count) players")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("ID: \(round.id.uuidString.prefix(8))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
