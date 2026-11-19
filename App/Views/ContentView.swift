import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeTestView()
                .tabItem {
                    Label("体验", systemImage: "keyboard")
                }
                .tag(0)

            ThemeStudioView()
                .tabItem {
                    Label("皮肤", systemImage: "paintpalette")
                }
                .tag(1)

            AISettingsView()
                .tabItem {
                    Label("AI 助手", systemImage: "sparkles")
                }
                .tag(2)

            ClipboardPhrasesView()
                .tabItem {
                    Label("剪贴板", systemImage: "doc.on.clipboard")
                }
                .tag(3)

            DictionarySettingsView()
                .tabItem {
                    Label("词库设置", systemImage: "slider.horizontal.3")
                }
                .tag(4)
        }
    }
}
