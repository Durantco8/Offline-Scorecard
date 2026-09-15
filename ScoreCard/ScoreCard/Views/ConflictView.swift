import SwiftUI
import CRDTKit

struct ConflictView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    let conflict: ConflictInfo
    let roundID: UUID

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Conflict on Hole \(conflict.hole)")
                    .font(.headline)

                Text("Two scores were entered at the same time. Tap the correct one.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                ForEach(conflict.values, id: \.strokes) { entry in
                    Button {
                        appState.activeRoundID = roundID
                        appState.resolveConflict(
                            player: conflict.player,
                            hole: conflict.hole,
                            strokes: entry.strokes
                        )
                        dismiss()
                    } label: {
                        HStack {
                            Text("\(entry.strokes)")
                                .font(.title.bold().monospacedDigit())
                            Text(entry.strokes == 1 ? "stroke" : "strokes")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Resolve Conflict")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
