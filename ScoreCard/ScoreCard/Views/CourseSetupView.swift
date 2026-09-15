import SwiftUI
import CRDTKit

struct CourseSetupView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    let roundID: UUID
    let isInitialSetup: Bool

    @State private var holeCount = 18
    @State private var pars: [Int] = Array(repeating: 4, count: 18)
    @State private var strokeIndexes: [Int] = Array(1...18)
    @State private var playerName = ""

    var body: some View {
        Form {
            Section("Players") {
                let players = playerList
                ForEach(players, id: \.id) { entry in
                    Text(entry.name)
                }
                HStack {
                    TextField("Add player", text: $playerName)
                        .textInputAutocapitalization(.words)
                    Button("Add") {
                        guard !playerName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        appState.activeRoundID = roundID
                        appState.addPlayer(name: playerName)
                        playerName = ""
                    }
                    .disabled(playerName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Holes") {
                Picker("Number of Holes", selection: $holeCount) {
                    Text("9").tag(9)
                    Text("18").tag(18)
                }
                .pickerStyle(.segmented)
                .onChange(of: holeCount) { newValue in
                    adjustHoleCount(newValue)
                }
            }

            Section("Par per Hole") {
                ForEach(0..<holeCount, id: \.self) { i in
                    HStack {
                        Text("Hole \(i + 1)")
                            .frame(width: 60, alignment: .leading)
                        Spacer()
                        Text("Par")
                            .foregroundStyle(.secondary)
                        Picker("", selection: $pars[i]) {
                            ForEach(3...5, id: \.self) { p in
                                Text("\(p)").tag(p)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                        Text("SI \(strokeIndexes[i])")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 40)
                    }
                }
            }
        }
        .navigationTitle("Course Setup")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    saveCourse()
                    dismiss()
                }
            }
            if isInitialSetup {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadExistingCourse()
        }
    }

    private var playerList: [(id: PlayerID, name: String)] {
        guard let state = appState.rounds[roundID] else { return [] }
        return state.players.elements.map { pid in
            let name = state.playerNames[pid]?.value ?? pid.uuid.uuidString.prefix(8).description
            return (id: pid, name: name)
        }.sorted { $0.name < $1.name }
    }

    private func loadExistingCourse() {
        guard let state = appState.rounds[roundID] else { return }
        let holes = state.course.value.holes
        guard !holes.isEmpty else { return }
        holeCount = holes.count
        pars = holes.map(\.par)
        strokeIndexes = holes.map(\.strokeIndex)
    }

    private func adjustHoleCount(_ count: Int) {
        while pars.count < count { pars.append(4) }
        while strokeIndexes.count < count { strokeIndexes.append(strokeIndexes.count + 1) }
    }

    private func saveCourse() {
        let holes = (0..<holeCount).map { i in
            Hole(number: i + 1, par: pars[i], strokeIndex: strokeIndexes[i])
        }
        appState.activeRoundID = roundID
        appState.setCourse(Course(holes: holes))
    }
}
