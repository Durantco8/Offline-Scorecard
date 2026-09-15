import SwiftUI
import CRDTKit

struct RoundHistoryView: View {
    @EnvironmentObject var appState: AppState

    private var completedRounds: [RoundState] {
        appState.rounds.values
            .filter { state in
                let holes = state.course.value.holes
                guard !holes.isEmpty, !state.players.elements.isEmpty else { return false }
                // A round is "complete" if every player has a score for every hole
                return state.players.elements.allSatisfy { pid in
                    holes.allSatisfy { hole in
                        state.entries[pid]?[hole.number] != nil
                    }
                }
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    var body: some View {
        List {
            if completedRounds.isEmpty {
                Text("No completed rounds yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(completedRounds, id: \.id) { round in
                    NavigationLink(value: round.id) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(round.course.value.holes.count) holes")
                                .font(.headline)
                            HStack {
                                Text("\(round.players.elements.count) players")
                                Text("Par \(round.course.value.holes.reduce(0) { $0 + $1.par })")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
    }
}
