import SwiftUI
import UIKit

/// 键盘工具栏自定义：按钮显隐/排序、拼音预览条、候选栏高度与字号。
struct ToolbarSettingsView: View {
    @EnvironmentObject private var appState: AppState

    /// 预设方案
    private enum ToolbarPreset: String, CaseIterable, Identifiable {
        case standard
        case minimal
        case custom
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .standard: return "默认"
            case .minimal: return "极简"
            case .custom: return "自定义"
            }
        }
    }

    /// 极简方案：仅保留 AI、剪贴板、快捷设置
    private static let minimalVisible: Set<ToolbarButtonID> = [.ai, .clipboard, .settings]

    private var sortedItems: [ToolbarItemConfig] {
        LingxiSettings.normalizedToolbarLayout(appState.settings.toolbarLayout)
    }

    private var currentPreset: ToolbarPreset {
        let items = sortedItems
        if items.allSatisfy({ $0.isVisible }) && items.map({ $0.buttonID }) == ToolbarButtonID.allCases {
            return .standard
        }
        let visible = Set(items.filter(\.isVisible).map(\.buttonID))
        if visible == Self.minimalVisible {
            return .minimal
        }
        return .custom
    }

    var body: some View {
        Form {
            Section {
                Picker("预设方案", selection: presetBinding) {
                    ForEach(ToolbarPreset.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("选择预设快速应用；手动调整后自动变为自定义。")
            }

            Section {
                ForEach(sortedItems) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.buttonID.symbolName)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text(item.buttonID.displayName)
                        Spacer()
                        Toggle("", isOn: visibilityBinding(for: item.buttonID))
                            .labelsHidden()
                    }
                }
                .onMove(perform: moveItems)
            } header: {
                Text("功能按钮")
            } footer: {
                Text("开关控制按钮是否显示，拖动右侧手柄调整顺序。撤销按钮仅在刚删除内容时出现。")
            }

            Section {
                Toggle("显示拼音预览条", isOn: $appState.settings.showComposingStrip)
            } header: {
                Text("输入提示")
            } footer: {
                Text("关闭后，打字时不再显示拼音/组合串预览，候选栏占满整个顶部区域。")
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("候选栏高度")
                        Spacer()
                        Text("\(Int(appState.settings.candidateBarHeight)) pt")
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                    Slider(value: $appState.settings.candidateBarHeight, in: 44...64, step: 1)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("候选词字号")
                        Spacer()
                        Text(String(format: "%.1f", appState.settings.candidateFontSize))
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                    Slider(value: $appState.settings.candidateFontSize, in: 14...22, step: 0.5)
                }
            } header: {
                Text("候选栏外观")
            } footer: {
                Text("调整后键盘会自动重新加载，立即生效。")
            }
        }
        .navigationTitle("键盘工具栏")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
    }

    private var presetBinding: Binding<ToolbarPreset> {
        Binding(
            get: { currentPreset },
            set: { applyPreset($0) }
        )
    }

    private func applyPreset(_ preset: ToolbarPreset) {
        var settings = appState.settings
        switch preset {
        case .standard:
            settings.toolbarLayout = defaultToolbarLayout
        case .minimal:
            settings.toolbarLayout = ToolbarButtonID.allCases.enumerated().map { idx, bid in
                ToolbarItemConfig(buttonID: bid, isVisible: Self.minimalVisible.contains(bid), order: idx)
            }
        case .custom:
            return
        }
        appState.settings = settings
    }

    private func visibilityBinding(for id: ToolbarButtonID) -> Binding<Bool> {
        Binding(
            get: {
                sortedItems.first(where: { $0.buttonID == id })?.isVisible ?? true
            },
            set: { newValue in
                var settings = appState.settings
                var items = LingxiSettings.normalizedToolbarLayout(settings.toolbarLayout)
                if let idx = items.firstIndex(where: { $0.buttonID == id }) {
                    items[idx].isVisible = newValue
                    settings.toolbarLayout = items
                    appState.settings = settings
                }
            }
        )
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        var settings = appState.settings
        var items = LingxiSettings.normalizedToolbarLayout(settings.toolbarLayout)
        items.move(fromOffsets: source, toOffset: destination)
        settings.toolbarLayout = items.enumerated().map { idx, item in
            var copy = item
            copy.order = idx
            return copy
        }
        appState.settings = settings
    }
}
