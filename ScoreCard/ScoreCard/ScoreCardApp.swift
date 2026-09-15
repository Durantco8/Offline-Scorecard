import SwiftUI

@main
struct ScoreCardApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                RoundListView()
            }
            .environmentObject(appState)
            .onAppear { appState.startNetworking() }
            .onDisappear { appState.stopNetworking() }
        }
    }
}
