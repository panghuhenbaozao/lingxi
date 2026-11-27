import SwiftUI
import UIKit

/// Cherry Studio 级纯 SwiftUI 富文本 Markdown + 代码块一键复制渲染组件（100% iOS 16 原生，零第三方依赖）：
/// - 独立代码块卡片：自动展示语言徽标、横向滚动等宽代码与一键「复制代码」按钮；
/// - 结构化排版：标题层级、无序/有序列表、左侧墨色竖线引用块与行内加粗/斜体/行内代码。
struct LXMarkdownMessageView: View {
    let text: String
    var font: Font = .subheadline

    @State private var copiedBlockIndex: Int? = nil

    var body: some View {
        let blocks = MarkdownBlockParser.parse(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { idx, block in
                renderBlock(block, index: idx)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock, index: Int) -> some View {
        switch block {
        case .heading(let level, let content):
            inlineMarkdownText(content)
                .font(level == 1 ? .headline : (level == 2 ? .subheadline.weight(.bold) : .footnote.weight(.bold)))
                .foregroundStyle(Color(Design.Palette.ink))
                .padding(.top, level == 1 ? 4 : 2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

        case .codeBlock(let language, let code, let isClosed):
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(language.isEmpty ? "CODE" : language.uppercased())
                        .font(.caption2.weight(.bold).monospaced())
                        .foregroundStyle(Color(Design.Palette.stone))
                    if !isClosed {
                        ProgressView().controlSize(.mini)
                    }
                    Spacer()
                    Button {
                        UIPasteboard.general.string = code
                        copiedBlockIndex = index
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedBlockIndex == index { copiedBlockIndex = nil }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedBlockIndex == index ? "checkmark" : "doc.on.doc")
                                .font(.caption2.weight(.semibold))
                            Text(copiedBlockIndex == index ? "已复制" : "复制代码")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(copiedBlockIndex == index ? Color(Design.Palette.success) : Color(Design.Palette.accent))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(Design.Palette.canvas), in: Capsule())
                        .overlay(Capsule().stroke(Color(Design.Palette.hairline), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(Design.Palette.surfaceSoft))

                Divider().overlay(Color(Design.Palette.hairline))

                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.caption.monospaced())
                        .foregroundStyle(Color(Design.Palette.ink))
                        .lineSpacing(3)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .background(Color(Design.Palette.surface))
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(Design.Palette.hairline), lineWidth: 0.6)
            )

        case .bullet(let content):
            HStack(alignment: .top, spacing: 7) {
                Text("•")
                    .font(font.weight(.bold))
                    .foregroundStyle(Color(Design.Palette.accent))
                inlineMarkdownText(content)
                    .font(font)
                    .foregroundStyle(Color(Design.Palette.ink))
                    .lineSpacing(3.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

        case .numbered(let prefix, let content):
            HStack(alignment: .top, spacing: 6) {
                Text(prefix)
                    .font(font.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color(Design.Palette.accent))
                inlineMarkdownText(content)
                    .font(font)
                    .foregroundStyle(Color(Design.Palette.ink))
                    .lineSpacing(3.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

        case .quote(let content):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color(Design.Palette.accent).opacity(0.65))
                    .frame(width: 3)
                inlineMarkdownText(content)
                    .font(font)
                    .foregroundStyle(Color(Design.Palette.slate))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 3)

        case .divider:
            Divider().overlay(Color(Design.Palette.hairline))

        case .paragraph(let content):
            inlineMarkdownText(content)
                .font(font)
                .foregroundStyle(Color(Design.Palette.ink))
                .lineSpacing(3.5)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func inlineMarkdownText(_ raw: String) -> Text {
        let opts = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let attr = try? AttributedString(markdown: raw, options: opts) {
            return Text(attr)
        }
        return Text(raw)
    }
}
