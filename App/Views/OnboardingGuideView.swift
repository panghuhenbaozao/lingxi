import SwiftUI
import UIKit

struct OnboardingGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    guideRow(step: "1", title: "前往系统设置", detail: "点击下方「打开系统设置」，进入「灵犀输入法 -> 键盘」。")
                    guideRow(step: "2", title: "开启灵犀键盘", detail: "打开「灵犀输入法」开关；如果列表里没有，请在 系统设置 -> 通用 -> 键盘 -> 键盘 -> 添加新键盘 中选择「灵犀输入法」。")
                } header: {
                    Text("第一步：添加灵犀输入法").font(.headline)
                }

                Section {
                    guideRow(step: "3", title: "打开允许完全访问", detail: "用于：主 App 与键盘之间通过 App Group 加密容器共享皮肤/词库/剪贴板预览、系统按键震动音效，以及您主动触发的 AI 辅助功能。")
                    Text("架构铁律：普通拼音/双拼/五笔打字 100% 在本地 SQLite 引擎离线运行，永不上传任何按键或输入原文；云同步采用端侧 E2EE 零知识加密。")
                        .font(.footnote)
                        .foregroundStyle(Color(Design.Palette.slate))
                        .padding(.top, Design.Spacing.xs)
                } header: {
                    Text("第二步：开启「允许完全访问」").font(.headline)
                }

                Section {
                    guideRow(step: "4", title: "切换键盘", detail: "在任意输入框长按左下角地球仪 🌐 图标，选择「灵犀输入法」。")
                } header: {
                    Text("第三步：切出键盘即可开打").font(.headline)
                }

                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Label("打开系统设置", systemImage: "gearshape.fill")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(Design.Palette.ink))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("启用灵犀输入法")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func guideRow(step: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(step)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(Design.Palette.ink))
                .frame(width: 26, height: 26)
                .background(Color(Design.Palette.surface))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color(Design.Palette.hairline), lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color(Design.Palette.ink))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color(Design.Palette.slate))
            }
        }
        .padding(.vertical, 6)
    }
}
