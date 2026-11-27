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

    /// v5.8 极简默认方案：与 defaultToolbarLayout 一致——AI/译/截屏识图/语音/表情符号/剪贴板/设置/撤销上栏，低频按钮收纳
    private static let minimalVisible: Set<ToolbarButtonID> = [.ai, .translate, .screenshot, .voice, .symbols, .clipboard, .settings, .undo]

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
                Text("预览")
            } footer: {
                Text("收到短信验证码或复制新内容时，工具栏会临时变成一键粘贴条，粘贴或关闭后恢复。")
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
                            .tint(Color(Design.Palette.accent))
                            .accessibilityLabel("显示\(item.buttonID.displayName)")
                    }
                }
                .onMove(perform: moveItems)
            } header: {
                Text("按钮 · 已显示 \(sortedItems.filter { $0.isVisible && $0.buttonID != .undo }.count) 个")
            } footer: {
                Text("拖动右侧把手调整顺序。AI、译、截屏、语音固定在左侧，其余在右侧；按钮太多时左侧可以左右滑动。撤销只在刚删除内容时出现。")
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
        let barBg = Color(hexColor: p.toolbarBackground)
        let keyFill = Color(hexColor: p.keyFill)
        let ink = Color(hexColor: p.keyText)
        let accent = Color(hexColor: p.accentFill)
        let accentText = Color(hexColor: p.accentText)
        let hint = Color(hexColor: p.keyHintText)

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("平时（与键盘里的排列完全一致）")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(Design.Palette.stone))
                // 与键盘 TopToolbarView 相同的分簇规则：AI / 译 / 截屏 / 语音在左，其余在右；
                // 撤销只在刚删除内容时出现，右端固定一个「收起键盘」
                let visible = sortedItems.filter { $0.isVisible && $0.buttonID != .undo }
                let left = visible.filter { $0.buttonID.isPrimaryLeftAction }
                let right = visible.filter { !$0.buttonID.isPrimaryLeftAction }
                HStack(spacing: 6) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(left) { item in
                                previewButton(item.buttonID, accent: accent, keyFill: keyFill, ink: ink)
                            }
                        }
                        .padding(.leading, 10)
                    }
                    Spacer(minLength: 4)
                    HStack(spacing: 6) {
                        ForEach(right) { item in
                            previewButton(item.buttonID, accent: accent, keyFill: keyFill, ink: ink)
                        }
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(hint)
                            .padding(.horizontal, 6)
                    }
                    .padding(.trailing, 8)
                }
                .frame(height: 44)
                .background(barBg)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(Design.Palette.hairline), lineWidth: 0.5))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("工具栏预览：\((left + right).map(\.buttonID.displayName).joined(separator: "、"))")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("收到验证码 / 复制新内容时")
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

    /// 预览里的单个按钮：AI 为强调胶囊，「译」为文字胶囊，其余为图标
    @ViewBuilder
    private func previewButton(_ id: ToolbarButtonID, accent: Color, keyFill: Color, ink: Color) -> some View {
        switch id {
        case .ai:
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                Text("灵犀 AI")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(accent.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(accent.opacity(0.28), lineWidth: 0.5))
        case .translate:
            Text("译")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(keyFill, in: Capsule())
                .overlay(Capsule().stroke(ink.opacity(0.12), lineWidth: 0.5))
        case .layout:
            Text("九键")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(keyFill, in: Capsule())
                .overlay(Capsule().stroke(ink.opacity(0.12), lineWidth: 0.5))
        default:
            Image(systemName: id.symbolName)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(ink)
                .frame(width: 28, height: 28)
                .background(keyFill, in: Capsule())
                .overlay(Capsule().stroke(ink.opacity(0.12), lineWidth: 0.5))
        }
    }

    private func isButtonVisible(_ id: ToolbarButtonID) -> Bool {
        sortedItems.first(where: { $0.buttonID == id })?.isVisible ?? true
    }

    /// 模拟候选栏预览：高度/字号/配色随设置与调色即时变化；支持左右滑动浏览更多候选
    private var candidateBarPreview: some View {
        let p = previewPreset
        let barBg = Color(hexColor: p.toolbarBackground)
        let ink = Color(hexColor: p.keyText)
        let accent = Color(hexColor: p.accentFill)
        let words = ["灵犀", "输入法", "纯白圆角", "候选栏", "左右滑动"]
        let fontSize = CGFloat(appState.settings.candidateFontSize)
        let fontSizeText = String(format: "%.1f", appState.settings.candidateFontSize)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(0..<words.count, id: \.self) { idx in
                    candidatePreviewChip(
                        word: words[idx],
                        isPrimary: idx == 0,
                        fontSize: fontSize,
                        ink: ink,
                        accent: accent
                    )
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

    private func candidatePreviewChip(
        word: String,
        isPrimary: Bool,
        fontSize: CGFloat,
        ink: Color,
        accent: Color
    ) -> some View {
        Text(word)
            .lineLimit(1)
            .font(.system(size: fontSize, weight: isPrimary ? .semibold : .regular))
            .foregroundStyle(isPrimary ? accent : ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isPrimary ? accent.opacity(0.12) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isPrimary ? Color.clear : ink.opacity(0.14), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
