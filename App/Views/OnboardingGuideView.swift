import SwiftUI
import UIKit

struct OnboardingGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("第一步：添加灵犀输入法") {
                    guideRow(step: "1", title: "前往系统设置", detail: "点击下方「打开系统设置」，进入「灵犀输入法 -> 键盘」。")
                    guideRow(step: "2", title: "开启灵犀键盘", detail: "打开「灵犀输入法」开关；如果列表里没有，请在 系统设置 -> 通用 -> 键盘 -> 键盘 -> 添加新键盘 中选择「灵犀输入法」。")
                }

                Section("第二步：开启「允许完全访问」") {
                    guideRow(step: "3", title: "打开允许完全访问", detail: "用于：AI 联网润色翻译、读取系统按键音效、以及主 App 与键盘之间同步皮肤/词库/剪贴板。")
                    Text("隐私承诺：普通拼音打字完全在本地 SQLite 引擎运行，绝不上传您的按键记录。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("第三步：切出键盘即可开打") {
                    guideRow(step: "4", title: "切换键盘", detail: "在任意输入框长按左下角地球仪 🌐 图标，选择「灵犀输入法」。")
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
                }
            }
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
        HStack(alignment: .top, spacing: 12) {
            Text(step)
                .font(.caption.bold())
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.15))
                .foregroundStyle(Color.accentColor)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
