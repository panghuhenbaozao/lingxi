import SwiftUI
import UIKit

/// 启用灵犀输入法引导（v6）：3 步，每步实时显示完成状态，主按钮随进度切换；从系统设置返回自动刷新。
struct OnboardingGuideView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private var step1Done: Bool { appState.isKeyboardEnabled }
    private var step2Done: Bool { appState.isKeyboardFullAccessConfirmed }
    private var allDone: Bool { step1Done && step2Done }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        LXIconTile(
                            icon: allDone ? "checkmark.seal.fill" : "keyboard",
                            tint: allDone ? Color(Design.Palette.success) : Color(Design.Palette.accent),
                            size: 60
                        )
                        Text(allDone ? "灵犀输入法已可以使用" : "3 步启用灵犀输入法")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text(allDone
                             ? "在任意 App 的输入框里切换到灵犀键盘就能开始打字。"
                             : "大约 30 秒。完成后回到这里，状态会自动更新。")
                            .font(.footnote)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }

                Section {
                    stepRow(
                        number: 1,
                        title: "添加键盘",
                        detail: "点下方按钮进入系统设置，依次点「键盘」→ 打开「灵犀输入法」。",
                        hint: "找不到？也可以在 设置 → 通用 → 键盘 → 键盘 → 添加新键盘 里选择「灵犀输入法」。",
                        done: step1Done,
                        isCurrent: !step1Done
                    )
                    stepRow(
                        number: 2,
                        title: "允许完全访问",
                        detail: "在同一页面打开「允许完全访问」，然后切到灵犀键盘一次，这一步就会自动打勾。",
                        hint: "平时打字完全在本机离线运行，不会上传你输入的内容；只有主动用 AI、翻译、跨屏接力时才联网。",
                        done: step2Done,
                        isCurrent: step1Done && !step2Done
                    )
                    stepRow(
                        number: 3,
                        title: "切换到灵犀键盘",
                        detail: "在任意输入框长按键盘左下角的地球图标，选择「灵犀输入法」。",
                        hint: nil,
                        done: allDone,
                        isCurrent: allDone
                    )
                }
            }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .bottom) {
                Group {
                    if allDone {
                        Button {
                            appState.requestedTab = 0
                            dismiss()
                        } label: {
                            Label("去首页试打", systemImage: "keyboard")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                    } else {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("打开系统设置", systemImage: "gearshape.fill")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
            .navigationTitle("启用灵犀输入法")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { appState.refreshAll() }
            .onChange(of: scenePhase) { phase in
                if phase == .active { appState.refreshAll() }
            }
        }
    }

    private func stepRow(number: Int, title: String, detail: String, hint: String?, done: Bool, isCurrent: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(done ? Color(Design.Palette.success) : (isCurrent ? Color(Design.Palette.accent) : Color(Design.Palette.surface)))
                    .frame(width: 28, height: 28)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(isCurrent ? Color.white : Color(Design.Palette.stone))
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Color(Design.Palette.charcoal))
                    .fixedSize(horizontal: false, vertical: true)
                if let hint, !done {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 6)
        .opacity(done && !isCurrent ? 0.7 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第 \(number) 步，\(title)，\(done ? "已完成" : "未完成")。\(detail)")
    }
}
