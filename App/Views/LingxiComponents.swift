import SwiftUI
import UIKit

// MARK: - 灵犀 App 共享 UI 组件（极简白设计系统 · DESIGN.md）
// 所有 App 页面统一使用：图标块 / 胶囊标签 / 可删词条 / 新增输入行 / 空状态 / 胶囊按钮 / 流式换行 / 卡片 / 底部浮动提示条

/// 极简悬浮卡片容器（柔和环境阴影 + 0.5px 细边 + 充裕留白）
struct LXCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(Design.Palette.canvas), in: RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                    .stroke(Color(Design.Palette.hairline), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.035), radius: 10, x: 0, y: 3)
    }
}

/// 极简分组卡片容器（替代厚重 List，提供 Apple / Linear 级净白分组视觉）
struct LXGroupCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(Design.Palette.canvas), in: RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                .stroke(Color(Design.Palette.hairline), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
    }
}

/// 极简分区标题（轻字重 + 微字距，不抢主内容视觉）
struct LXSectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color(Design.Palette.stone))
            .padding(.leading, 6)
            .padding(.bottom, 2)
    }
}

/// 单行精炼入口行（左图标 + 标题 + 右侧短状态值 + 箭头，杜绝大段文字堆砌）
struct LXCleanRow: View {
    let icon: String
    let title: String
    var value: String? = nil
    var tint: Color = Color(Design.Palette.ink)
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            LXIconTile(icon: icon, tint: tint, size: 30)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(Design.Palette.ink))
                .lineLimit(1)
            Spacer(minLength: 8)
            if let value, !value.isEmpty {
                Text(value)
                    .font(.footnote)
                    .foregroundStyle(Color(Design.Palette.stone))
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(Design.Palette.muted))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

/// 圆角图标块：克制中性浅底 + 柔和语义色，避免满屏刺眼同色方块
struct LXIconTile: View {
    let icon: String
    var tint: Color = Color(Design.Palette.ink)
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.44, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                tint == Color(Design.Palette.ink)
                    ? Color(Design.Palette.surface)
                    : tint.opacity(0.11),
                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

/// 小胶囊标签：默认中性灰描边；filled 时用主题色浅底
struct LXTag: View {
    let text: String
    var icon: String? = nil
    var tint: Color = Color(Design.Palette.slate)
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(filled ? tint.opacity(0.12) : Color(Design.Palette.surface), in: Capsule())
        .overlay(Capsule().stroke(filled ? Color.clear : Color(Design.Palette.hairline), lineWidth: 0.5))
    }
}

/// 可点按移除的词条胶囊
struct LXRemovableChip: View {
    let text: String
    let tint: Color
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 5) {
                Text(text)
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.7)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(tint.opacity(0.10), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("移除 \(text)")
    }
}

/// 「+ 新增」输入行：回车或点「添加」提交，提交后清空
struct LXAddFieldRow: View {
    let placeholder: String
    @Binding var text: String
    let onAdd: (String) -> Void

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color(Design.Palette.accent))
            TextField(placeholder, text: $text)
                .font(.subheadline)
                .submitLabel(.done)
                .onSubmit { commit() }
            if !trimmed.isEmpty {
                Button("添加") { commit() }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: true))
            }
        }
        .frame(minHeight: 36)
    }

    private func commit() {
        let w = trimmed
        guard !w.isEmpty else { return }
        onAdd(w)
        text = ""
    }
}

/// 设置开关行：标题 + 可选说明，统一主题色
struct LXToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Color(Design.Palette.ink))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, subtitle == nil ? 0 : 2)
        }
        .tint(Color(Design.Palette.accent))
    }
}

/// 导航入口行：图标块 + 标题 + 一行说明 + 可选徽标（放在 NavigationLink 的 label 里）
struct LXNavRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var badge: String? = nil
    var tint: Color = Color(Design.Palette.accent)

    var body: some View {
        HStack(spacing: 12) {
            LXIconTile(icon: icon, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if let badge, !badge.isEmpty {
                LXTag(text: badge)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// 空状态：图标 + 标题 + 说明
struct LXEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Color(Design.Palette.muted))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(Design.Palette.ink))
            Text(message)
                .font(.caption)
                .foregroundStyle(Color(Design.Palette.stone))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 8)
    }
}

/// 胶囊按钮：prominent 实底白字 / 否则浅底主题色字；wide 时撑满宽度、高 46pt
struct LXCapsuleButtonStyle: ButtonStyle {
    var prominent: Bool = true
    var wide: Bool = false
    var tint: Color = Color(Design.Palette.accent)

    func makeBody(configuration: Configuration) -> some View {
        LXCapsuleButtonLabel(configuration: configuration, prominent: prominent, wide: wide, tint: tint)
    }
}

struct LXCapsuleButtonLabel: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let wide: Bool
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(wide ? .system(size: 15, weight: .semibold) : .caption.bold())
            .lineLimit(1)
            .padding(.horizontal, wide ? 16 : 12)
            .frame(maxWidth: wide ? CGFloat.infinity : nil, minHeight: wide ? 46 : 32)
            .foregroundStyle(prominent ? Color.white : tint)
            .background(prominent ? tint : tint.opacity(0.12), in: Capsule())
            // 视觉高度 32pt，点按热区补足到 44pt（DESIGN.md §9）
            .padding(.vertical, wide ? 0 : 6)
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 流式换行布局（iOS 16 Layout）：词条胶囊按行自动折行
struct LXFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth: CGFloat = {
            if let w = proposal.width, w.isFinite, w > 0 { return w }
            return .infinity
        }()
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if !size.width.isFinite || size.width < 0 { size.width = 0 }
            if !size.height.isFinite || size.height < 0 { size.height = 0 }
            if maxWidth.isFinite {
                size.width = min(size.width, maxWidth)
            }
            if maxWidth.isFinite && x > 0 && x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            let candidateW = max(0, x - spacing)
            if candidateW.isFinite {
                widest = max(widest, candidateW)
            }
        }
        let resolvedWidth: CGFloat
        if let w = proposal.width, w.isFinite, w >= 0 {
            resolvedWidth = w
        } else {
            resolvedWidth = widest.isFinite ? widest : 0
        }
        let resolvedHeight = (y + lineHeight).isFinite ? max(0, y + lineHeight) : 0
        return CGSize(width: resolvedWidth, height: resolvedHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard bounds.width.isFinite, bounds.width > 0 else { return }
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if !size.width.isFinite || size.width < 0 { size.width = 0 }
            if !size.height.isFinite || size.height < 0 { size.height = 0 }
            size.width = min(size.width, bounds.width)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// 底部浮动提示条（全 App 统一）：成功 / 提示 2.5 秒、失败 5 秒后自动消失；
/// 语气按文案自动判断；开启「减弱动态效果」时只淡入淡出不位移。
struct LXToastModifier: ViewModifier {
    @Binding var message: String?
    var isError: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func resolvedTone(_ msg: String) -> LXToastText.Tone {
        isError ? .error : LXToastText.tone(of: msg)
    }

    private func icon(_ tone: LXToastText.Tone) -> (String, Color) {
        switch tone {
        case .success: return ("checkmark.circle.fill", Color(Design.Palette.success))
        case .info: return ("info.circle.fill", Color(Design.Palette.stone))
        case .error: return ("exclamationmark.triangle.fill", Color(Design.Palette.error))
        }
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if let msg = message {
                    let style = icon(resolvedTone(msg))
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: style.0)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(style.1)
                        Text(LXToastText.clean(msg))
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color(Design.Palette.ink))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            message = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("关闭提示")
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 4)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous)
                            .stroke(Color(Design.Palette.hairline), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityElement(children: .combine)
                }
            }
            .animation(.easeOut(duration: 0.2), value: message)
            .task(id: message) {
                guard let msg = message else { return }
                let isErr = resolvedTone(msg) == .error
                try? await Task.sleep(nanoseconds: isErr ? 5_000_000_000 : 2_500_000_000)
                if !Task.isCancelled {
                    message = nil
                }
            }
            .onChange(of: message) { newValue in
                guard let newValue else { return }
                // 轻触觉反馈：成功 / 失败各一种；普通提示不震动，避免打扰
                switch resolvedTone(newValue) {
                case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
                case .error: UINotificationFeedbackGenerator().notificationOccurred(.error)
                case .info: break
                }
                // 让 VoiceOver 用户也能听到提示
                UIAccessibility.post(notification: .announcement, argument: LXToastText.clean(newValue))
            }
    }
}

extension View {
    /// 限制内容的可读宽度并居中：iPhone 上无影响，iPad 横屏时卡片不会被拉满整屏
    func lxReadableWidth(_ maxWidth: CGFloat = 680) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }

    func lxToast(_ message: Binding<String?>, isError: Bool = false) -> some View {
        modifier(LXToastModifier(message: message, isError: isError))
    }
}
