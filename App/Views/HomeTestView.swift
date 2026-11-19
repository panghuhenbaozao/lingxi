import SwiftUI
import UIKit

struct HomeTestView: View {
    @EnvironmentObject private var appState: AppState
    @State private var sandboxText: String = ""
    @State private var showGuide = false
    @FocusState private var isTestingFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroHeader
                    statusGrid
                    sandboxCard
                    tipsCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("灵犀输入法")
            .sheet(isPresented: $showGuide) {
                OnboardingGuideView()
            }
        }
    }

    private var heroHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.18, green: 0.44, blue: 0.93), Color(red: 0.08, green: 0.16, blue: 0.36)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 58, height: 58)
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("灵犀 AI 输入法")
                    .font(.title3.bold())
                Text("39.6万雾凇+五笔86 · 全拼/7双拼/九宫格 · 流式 AI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var statusGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                statusCard(
                    title: "系统键盘状态",
                    value: appState.isKeyboardEnabled ? "已添加启用" : "未添加到系统",
                    icon: appState.isKeyboardEnabled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    tint: appState.isKeyboardEnabled ? .green : .orange
                )
                statusCard(
                    title: "AI 引擎",
                    value: appState.aiConfig.isConfigured ? "密钥已就绪" : "待填写密钥",
                    icon: appState.aiConfig.isConfigured ? "sparkles" : "key.fill",
                    tint: appState.aiConfig.isConfigured ? .blue : .secondary
                )
            }

            HStack(spacing: 10) {
                statusCard(
                    title: "App Group 共享",
                    value: AppGroup.isAvailable ? "互通正常" : "容器受限",
                    icon: AppGroup.isAvailable ? "link.circle.fill" : "xmark.octagon.fill",
                    tint: AppGroup.isAvailable ? .green : .red
                )
                statusCard(
                    title: "当前输入方案",
                    value: appState.settings.inputScheme.displayName,
                    icon: "character.textbox",
                    tint: .purple
                )
            }

            if !appState.isKeyboardEnabled {
                HStack(spacing: 10) {
                    Button {
                        showGuide = true
                    } label: {
                        Label("查看开启教程", systemImage: "book.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("去设置开启", systemImage: "gear")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 4)
            }
        }
    }

    private func statusCard(title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.bold())
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var sandboxCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("实时打字与剪贴板测试区", systemImage: "pencil.and.outline")
                    .font(.headline)
                Spacer()
                if isTestingFocused {
                    Button("收起键盘") { isTestingFocused = false }
                        .font(.caption.bold())
                }
            }

            TextEditor(text: $sandboxText)
                .focused($isTestingFocused)
                .frame(minHeight: 120)
                .padding(8)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if sandboxText.isEmpty {
                        Text("点击这里切出「灵犀输入法」试打拼音、双拼、算式（如 125*8=）或点工具栏 AI…")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = "【灵犀测试】您的验证码是 849201，5分钟内有效。"
                    appState.addClipboardEntry("【灵犀测试】您的验证码是 849201，5分钟内有效。")
                } label: {
                    Label("模拟复制验证码短信", systemImage: "doc.on.doc")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)

                Spacer()

                if !sandboxText.isEmpty {
                    Button("清空") { sandboxText = "" }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("高频实用玩法速查")
                .font(.headline)
            tipItem(icon: "scribble.variable", title: "26 键中英文滑行输入", desc: "手指在 26 键上连续滑过字母即可成词（如 nihao→你好、hello），按一次 ⌫ 整词撤销")
            tipItem(icon: "magnifyingglass.circle", title: "u 模式 · 部件拆字与五笔画反查", desc: "全拼输 u（双拼/五笔长按 u 选 U）查生僻字并带读音：ushuishuishui→淼、ufangfangtu→堃、uhspn→木")
            tipItem(icon: "keyboard.badge.ellipsis", title: "全拼 + 7 种双拼 + 五笔 86 + 九宫格", desc: "内置 39.6 万雾凇词库与 9.3 万五笔 86 码表；五笔按 z 可临时拼音并实时反查编码")
            tipItem(icon: "arrow.up.and.down.and.arrow.left.and.right", title: "✥ 文本编辑与光标精控面板", desc: "点工具栏十字图标开启四向方向键、行首/行尾跳转、向前删 ⌦、复制粘贴与清空本行")
            tipItem(icon: "globe", title: "译 · 14 语种口语/正式边打边译", desc: "点工具栏「译」照常输中文，支持一键切换口语/正式语气，空格一键上屏译文")
            tipItem(icon: "function", title: "v / V 模式 · 大写金额/算式/15种日期", desc: "全拼输 v、双拼/五笔上划 v 输大写 V：v125*8 同时出 1000 与「壹仟元整」，vrq/vsj 查日期")
            tipItem(icon: "character.textbox", title: "以词定字 & 退格撤学", desc: "长按候选可单取首/尾字；上屏选错词立刻按 ⌫ 不仅恢复原拼音，还自动撤销误学词频")
            tipItem(icon: "face.smiling", title: "首位候选 Emoji 推荐 & 拼音搜表情", desc: "全方案自动推荐句尾表情（如「今天好开心😊」），支持拼音直搜表情、箭头与颜文字")
            tipItem(icon: "sparkles", title: "AI 自由问 & 剪贴板炸词", desc: "支持拼音自由问 AI、神回复剪贴板、长短信 BigBang 炸词、custom.tsv / user.tsv 导入导出")
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func tipItem(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
