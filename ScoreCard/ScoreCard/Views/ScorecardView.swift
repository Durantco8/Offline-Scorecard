import SwiftUI
import CRDTKit

struct ScorecardView: View {
    @EnvironmentObject var appState: AppState
    let roundID: UUID

    @State private var editingCell: CellID?
    @State private var editText = ""
    @State private var showingConflict: ConflictInfo?

    private var state: RoundState? { appState.rounds[roundID] }

    private var players: [(id: PlayerID, name: String)] {
        guard let state else { return [] }
        return state.players.elements.map { pid in
            let name = state.playerNames[pid]?.value ?? pid.uuid.uuidString.prefix(4).description
            return (id: pid, name: name)
        }.sorted { $0.name < $1.name }
    }

    private var holes: [Hole] {
        state?.course.value.holes ?? []
    }

    var body: some View {
        Group {
            if holes.isEmpty && players.isEmpty {
                VStack(spacing: 12) {
                    Text("Set up the course and add players to get started.")
                        .foregroundStyle(.secondary)
                    NavigationLink("Course Setup") {
                        CourseSetupView(roundID: roundID, isInitialSetup: false)
                    }
                }
            } else {
                ScrollView([.horizontal, .vertical]) {
                    scoreGrid
                }
            }
        }
        .navigationTitle("Scorecard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    CourseSetupView(roundID: roundID, isInitialSetup: false)
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .alert("Edit Score", isPresented: showEditAlert) {
            TextField("Strokes", text: $editText)
                .keyboardType(.numberPad)
            Button("Save") { saveEdit() }
            if let cell = editingCell, state?.entries[cell.player]?[cell.hole] != nil {
                Button("Clear", role: .destructive) { clearScore() }
            }
            Button("Cancel", role: .cancel) { editingCell = nil }
        }
        .sheet(item: $showingConflict) { conflict in
            ConflictView(conflict: conflict, roundID: roundID)
        }
    }

    private var showEditAlert: Binding<Bool> {
        Binding(
            get: { editingCell != nil },
            set: { if !$0 { editingCell = nil } }
        )
    }

    // MARK: - Grid

    @ViewBuilder
    private var scoreGrid: some View {
        let colWidth: CGFloat = 44
        let nameWidth: CGFloat = 80
        let totalWidth: CGFloat = 50

        Grid(alignment: .center, horizontalSpacing: 0, verticalSpacing: 0) {
            // Header row
            GridRow {
                Text("")
                    .frame(width: nameWidth)
                    .gridCellAnchor(.leading)
                ForEach(holes, id: \.number) { hole in
                    Text("\(hole.number)")
                        .font(.caption.bold())
                        .frame(width: colWidth)
                }
                Text("Tot")
                    .font(.caption.bold())
                    .frame(width: totalWidth)
                Text("+/-")
                    .font(.caption.bold())
                    .frame(width: totalWidth)
            }

            // Par row
            GridRow {
                Text("Par")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: nameWidth, alignment: .leading)
                ForEach(holes, id: \.number) { hole in
                    Text("\(hole.par)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: colWidth)
                }
                Text("\(holes.reduce(0) { $0 + $1.par })")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: totalWidth)
                Text("")
                    .frame(width: totalWidth)
            }

            Divider()

            // Player rows
            ForEach(players, id: \.id) { player in
                GridRow {
                    Text(player.name)
                        .font(.caption)
                        .lineLimit(1)
                        .frame(width: nameWidth, alignment: .leading)
                    ForEach(holes, id: \.number) { hole in
                        scoreCell(player: player.id, hole: hole)
                            .frame(width: colWidth)
                    }
                    totalCell(player: player.id)
                        .frame(width: totalWidth)
                    relativeCell(player: player.id)
                        .frame(width: totalWidth)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Cells

    @ViewBuilder
    private func scoreCell(player: PlayerID, hole: Hole) -> some View {
        let register = state?.entries[player]?[hole.number]
        let hasConflict = (register?.values.count ?? 0) > 1

        Group {
            if hasConflict {
                Button {
                    showingConflict = ConflictInfo(
                        player: player, hole: hole.number,
                        values: Array(register!.values)
                    )
                } label: {
                    Text("!")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.orange, in: RoundedRectangle(cornerRadius: 4))
                }
            } else if let entry = register?.values.first, entry.strokes > 0 {
                Button {
                    editingCell = CellID(player: player, hole: hole.number)
                    editText = "\(entry.strokes)"
                } label: {
                    Text("\(entry.strokes)")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(scoreColor(strokes: entry.strokes, par: hole.par))
                        .frame(width: 30, height: 30)
                }
            } else {
                Button {
                    editingCell = CellID(player: player, hole: hole.number)
                    editText = ""
                } label: {
                    Text("-")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 30, height: 30)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func totalCell(player: PlayerID) -> some View {
        let total = totalStrokes(player: player)
        if total > 0 {
            Text("\(total)")
                .font(.caption.bold().monospacedDigit())
        } else {
            Text("-")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func relativeCell(player: PlayerID) -> some View {
        let total = totalStrokes(player: player)
        let holesPlayed = holesWithScore(player: player)
        let parForPlayed = holes.filter { holesPlayed.contains($0.number) }
            .reduce(0) { $0 + $1.par }

        if holesPlayed.isEmpty {
            Text("")
        } else {
            let rel = total - parForPlayed
            Text(rel == 0 ? "E" : (rel > 0 ? "+\(rel)" : "\(rel)"))
                .font(.caption.monospacedDigit())
                .foregroundStyle(rel < 0 ? .green : (rel > 0 ? .red : .primary))
        }
    }

    // MARK: - Helpers

    private func totalStrokes(player: PlayerID) -> Int {
        guard let entries = state?.entries[player] else { return 0 }
        return entries.values.compactMap { reg in
            guard reg.values.count == 1, let s = reg.values.first?.strokes, s > 0 else { return nil }
            return s
        }.reduce(0, +)
    }

    private func holesWithScore(player: PlayerID) -> Set<Int> {
        guard let entries = state?.entries[player] else { return [] }
        var result: Set<Int> = []
        for (hole, reg) in entries {
            if reg.values.count == 1, let s = reg.values.first?.strokes, s > 0 {
                result.insert(hole)
            }
        }
        return result
    }

    private func scoreColor(strokes: Int, par: Int) -> Color {
        let diff = strokes - par
        switch diff {
        case ..<(-1): return .green
        case -1: return .green
        case 0: return .primary
        case 1: return .red
        default: return .red
        }
    }

    private func saveEdit() {
        guard let cell = editingCell,
              let strokes = Int(editText), strokes > 0 else {
            editingCell = nil
            return
        }
        appState.activeRoundID = roundID
        appState.setScore(player: cell.player, hole: cell.hole, strokes: strokes)
        editingCell = nil
    }

    private func clearScore() {
        guard let cell = editingCell else { return }
        appState.activeRoundID = roundID
        appState.setScore(player: cell.player, hole: cell.hole, strokes: 0)
        editingCell = nil
    }
}

// MARK: - Supporting types

private struct CellID {
    let player: PlayerID
    let hole: Int
}

struct ConflictInfo: Identifiable {
    let id = UUID()
    let player: PlayerID
    let hole: Int
    let values: [HoleEntry]
}
