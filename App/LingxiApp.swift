import SwiftUI

@main
struct LingxiApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        appState.refreshAll()
                        appState.scheduleAutoSyncIfNeeded()
                    }
                }
        }
    }
}
