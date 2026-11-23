import SwiftUI
import UIKit

@main
struct LingxiApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onOpenURL { url in
                    guard url.scheme == "lingxi" else { return }
                    switch url.host {
                    case "auth-callback":
                        Task {
                            try? await appState.completeApplePasskeySignIn(callbackURL: url)
                        }
                    case "ai-settings":
                        appState.requestedTab = 2
                    case "permissions":
                        appState.showPermissionsCenter = true
                    default:
                        break
                    }
                }
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        appState.refreshAll()
                        appState.scheduleAutoSyncIfNeeded()
                        LiveLocationLexiconService.shared.autoRefreshIfStale()
                        let relayCfg = ClipboardRelayConfig.load()
                        if relayCfg.autoRelayEnabled, !relayCfg.pairCode.isEmpty {
                            Task {
                                if let items = try? await ClipboardRelayService.shared.pullLatest(pairCode: relayCfg.pairCode),
                                   let newest = items.first,
                                   newest.id > relayCfg.lastPulledID {
                                    await MainActor.run {
                                        UIPasteboard.general.string = newest.contentText
                                        appState.reloadClipboard()
                                    }
                                }
                            }
                        }
                    }
                }
        }
    }
}
