import SwiftUI
import UIKit

@main
struct LingxiApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        LingxiAppShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onOpenURL { url in
                    guard url.scheme == "lingxi" else { return }
                    switch url.host {
                    case "auth-callback":
                        Task {
                            // 从浏览器回到 App 完成登录：成功或失败都要告诉用户，不能悄无声息
                            do {
                                try await appState.completeApplePasskeySignIn(callbackURL: url)
                                appState.requestedTab = 0
                                appState.globalToastMessage = "已登录云端账号"
                            } catch {
                                appState.requestedTab = 0
                                appState.globalErrorMessage = "登录没有完成：\(error.localizedDescription)"
                            }
                        }
                    case "ai-settings":
                        appState.requestedTab = 2
                    case "permissions":
                        appState.showPermissionsCenter = true
                    case "voice-warmup":
                        appState.requestedTab = 0
                        appState.voiceEngineBannerMessage = "正在准备键盘内的语音输入…"
                        Task {
                            try? await Task.sleep(nanoseconds: 150_000_000)
                            let res = await BackgroundVoiceEngine.shared.warmUp()
                            await MainActor.run {
                                appState.voiceEngineBannerMessage = res.message
                            }
                        }
                    case "voice-translate":
                        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
                        let autoStart = comps?.queryItems?.contains(where: { $0.name == "autostart" && $0.value == "1" }) == true
                        let modeRaw = comps?.queryItems?.first(where: { $0.name == "mode" })?.value
                        appState.voiceTranslatorInitialMode = modeRaw.flatMap { VoiceTranslateMode(rawValue: $0) }
                        appState.voiceTranslatorAutoStart = autoStart
                        appState.showVoiceTranslator = true
                    case "screenshot-ai":
                        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
                        let auto = comps?.queryItems?.contains(where: { $0.name == "auto" && $0.value == "1" }) == true
                        let delID = comps?.queryItems?.first(where: { $0.name == "deleteId" })?.value
                        appState.screenshotAutoAnalyze = auto
                        appState.pendingDeleteScreenshotAssetID = delID
                        appState.showScreenshotVision = true
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
                                   newest.id > relayCfg.lastPulledID,
                                   !newest.contentText.hasPrefix(ClipboardRelayCrypto.prefix),
                                   !ClipboardClassifier.isSensitiveContent(newest.contentText) {
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
