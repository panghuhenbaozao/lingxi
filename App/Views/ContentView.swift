import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeTestView(onSelectTab: { selectedTab = $0 })
                .lxToast($appState.globalToastMessage)
                .lxToast($appState.globalErrorMessage, isError: true)
                .tabItem {
                    Label("首页", systemImage: "keyboard")
                }
                .tag(0)

            ThemeStudioView()
                .tabItem {
                    Label("外观", systemImage: "paintbrush")
                }
                .tag(1)

            AISettingsView()
                .tabItem {
                    Label("AI", systemImage: "sparkles")
                }
                .tag(2)

            ClipboardPhrasesView()
                .tabItem {
                    Label("剪贴板", systemImage: "doc.on.clipboard")
                }
                .tag(3)

            DictionarySettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(4)
        }
        .tint(Color(Design.Palette.accent))
        // 跟随系统字号；最大辅助字号下卡片会严重变形，上限设为 accessibility3
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
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
