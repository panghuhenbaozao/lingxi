import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeTestView(onSelectTab: { selectedTab = $0 })
                .tabItem {
                    Label("首页", systemImage: "keyboard")
                }
                .tag(0)

            ThemeStudioView()
                .tabItem {
                    Label("外观", systemImage: "paintpalette")
                }
                .tag(1)

            AISettingsView()
                .tabItem {
                    Label("AI", systemImage: "sparkles")
                }
                .tag(2)

            ClipboardPhrasesView()
                .tabItem {
                    Label("工具", systemImage: "tray.full")
                }
                .tag(3)

            DictionarySettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(4)
        }
        .tint(Color(Design.Palette.accent))
        .onChange(of: selectedTab) { _ in
            appState.reloadSharedThemeAndSettingsIfNeeded()
        }
        .onChange(of: appState.requestedTab) { target in
            if let target {
                selectedTab = target
                appState.requestedTab = nil
            }
        }
        .sheet(isPresented: $appState.showPermissionsCenter) {
            PermissionsCenterSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showVoiceTranslator) {
            VoiceLiveTranslatorView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showScreenshotVision) {
            ScreenshotVisionView()
                .environmentObject(appState)
        }
    }
}
