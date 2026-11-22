import SwiftUI
import UIKit

/// 键盘工具栏自定义：按钮显隐/排序、拼音预览条、候选栏高度与字号。
struct ToolbarSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    private var previewPreset: KeyboardThemePreset {
        appState.theme.activePreset(isSystemDark: colorScheme == .dark)
    }

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

    /// v4 极简方案：与 defaultToolbarLayout 一致——AI/译/剪贴板/设置/撤销上栏，低频按钮收纳
    private static let minimalVisible: Set<ToolbarButtonID> = [.ai, .translate, .clipboard, .settings, .undo]

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
                toolbarLivePreview
                Picker("预设方案", selection: presetBinding) {
                    ForEach(ToolbarPreset.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("顶部工具栏与智能胶囊预览")
            } footer: {
                Text("日常空闲时左置『灵犀 AI / 译』胶囊、右置轻量工具按钮；当收到短信验证码或新复制内容时，顶栏会自动切换为全宽智能粘贴胶囊。低频的表情与光标移动已从顶栏移除。")
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
                Text("功能按钮显隐与排序")
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
                candidateBarPreview
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("候选栏高度")
                        Spacer()
                        Text("\(Int(appState.settings.candidateBarHeight)) pt")
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                    Slider(value: $appState.settings.candidateBarHeight, in: 44...64, step: 1)
                        .accessibilityLabel("候选栏高度")
                        .accessibilityValue("\(Int(appState.settings.candidateBarHeight)) pt")
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("候选词字号")
                        Spacer()
                        Text(String(format: "%.1f", appState.settings.candidateFontSize))
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                    Slider(value: $appState.settings.candidateFontSize, in: 14...22, step: 0.5)
                        .accessibilityLabel("候选词字号")
                        .accessibilityValue(String(format: "%.1f", appState.settings.candidateFontSize))
                }
                if !isDefaultCandidateAppearance {
                    Button("恢复默认（50 pt / 16.5）") {
                        appState.settings.candidateBarHeight = LingxiSettings().candidateBarHeight
                        appState.settings.candidateFontSize = LingxiSettings().candidateFontSize
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Color(Design.Palette.ink))
                    .accessibilityHint("将候选栏高度恢复为 50 pt，字号恢复为 16.5")
                }
            } header: {
                Text("候选栏外观")
            } footer: {
                Text("调整后键盘会自动重新加载，立即生效。开启拼音预览条且栏高较低时，候选字号会自动适当收敛以适配空间。")
            }
        }
        .navigationTitle("键盘工具栏")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
    }

    /// 与默认外观一致时隐藏恢复按钮（默认：高度 50 pt，字号 16.5）
    private var isDefaultCandidateAppearance: Bool {
        let d = LingxiSettings()
        return appState.settings.candidateBarHeight == d.candidateBarHeight
            && appState.settings.candidateFontSize == d.candidateFontSize
    }

    /// 模拟键盘顶部栏的两种核心形态（实时同步用户当前键盘皮肤/调色，且支持长文本左右滑动）：
    /// 1) 常规空闲态（左置灵犀 AI + 译，右置剪贴板与设置）
    /// 2) 收到短信验证码或新复制内容时的「全栏独占接管胶囊」
    private var toolbarLivePreview: some View {
        let p = previewPreset
        let barBg = Color(uiColor: HexColor.color(p.toolbarBackground))
        let keyFill = Color(uiColor: HexColor.color(p.keyFill))
        let ink = Color(uiColor: HexColor.color(p.keyText))
        let accent = Color(uiColor: HexColor.color(p.accentFill))
        let accentText = Color(uiColor: HexColor.color(p.accentText))
        let hint = Color(uiColor: HexColor.color(p.keyHintText))

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("常规空闲态（跟随当前外观与调色）")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(Design.Palette.stone))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if isButtonVisible(.ai) {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("灵犀 AI")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(accent)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(accent.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(accent.opacity(0.28), lineWidth: 0.5))
                        }
                        if isButtonVisible(.translate) {
                            HStack(spacing: 4) {
                                Image(systemName: "character.bubble")
                                    .font(.system(size: 11, weight: .medium))
                                Text("译")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(keyFill)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(ink.opacity(0.12), lineWidth: 0.5))
                        }
                        if isButtonVisible(.layout) {
                            Text("九键")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(ink)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(keyFill)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(ink.opacity(0.12), lineWidth: 0.5))
                        }
                        if isButtonVisible(.clipboard) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(ink)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(keyFill)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(ink.opacity(0.12), lineWidth: 0.5))
                        }
                        if isButtonVisible(.settings) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(ink)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(keyFill)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(ink.opacity(0.12), lineWidth: 0.5))
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .frame(height: 44)
                .background(barBg)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(Design.Palette.hairline), lineWidth: 0.5))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("复制文本 / 收到短信验证码时（文本区支持左右滑动查看完整内容）")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(Design.Palette.stone))
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "message.badge.filled.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("验证码")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.12))
                    .clipShape(Capsule())

                    ScrollView(.horizontal, showsIndicators: false) {
                        Text("849201 · 【灵犀】您的登录验证码为 849201，5分钟内有效，请勿泄露给他人")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(ink)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("填入 849201")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(accentText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(accent)
                        .clipShape(Capsule())

                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(hint)
                        .padding(4)
                }
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(keyFill)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(accent.opacity(0.24), lineWidth: 0.5))
            }
        }
        .padding(.vertical, 4)
    }

    private func isButtonVisible(_ id: ToolbarButtonID) -> Bool {
        sortedItems.first(where: { $0.buttonID == id })?.isVisible ?? true
    }

    /// 模拟候选栏预览：高度/字号/配色随设置与调色即时变化；支持左右滑动浏览更多候选
    private var candidateBarPreview: some View {
        let p = previewPreset
        let barBg = Color(uiColor: HexColor.color(p.toolbarBackground))
        let ink = Color(uiColor: HexColor.color(p.keyText))
        let accent = Color(uiColor: HexColor.color(p.accentFill))
        let words = ["灵犀", "输入法", "纯白圆角", "候选栏", "左右滑动"]
        let fontSizeText = String(format: "%.1f", appState.settings.candidateFontSize)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                    Text(word)
                        .lineLimit(1)
                        .font(.system(
                            size: CGFloat(appState.settings.candidateFontSize),
                            weight: idx == 0 ? .semibold : .regular
                        ))
                        .foregroundStyle(idx == 0 ? accent : ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            idx == 0 ? accent.opacity(0.12) : Color.clear
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    idx == 0 ? Color.clear : ink.opacity(0.14),
                                    lineWidth: 0.5
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 6)
        }
        .frame(height: CGFloat(appState.settings.candidateBarHeight))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(barBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("候选栏预览")
        .accessibilityValue("高度 \(Int(appState.settings.candidateBarHeight)) pt，字号 \(fontSizeText)")
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
            // 全部可见的完整布局（不再引用 defaultToolbarLayout——它自 v4 起为极简默认）
            settings.toolbarLayout = ToolbarButtonID.allCases.enumerated().map { idx, bid in
                ToolbarItemConfig(buttonID: bid, isVisible: true, order: idx)
            }
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
