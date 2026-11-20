import SwiftUI
import UIKit

struct ClipboardPhrasesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var segment = 0
    @State private var showAddPhrase = false
    @State private var newPhraseTitle = ""
    @State private var newPhraseContent = ""
    @State private var newPhraseCategory = "常用"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("内容类型", selection: $segment) {
                    Text("剪贴板历史").tag(0)
                    Text("快捷短语").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if segment == 0 {
                    clipboardList
                } else {
                    phrasesList
                }
            }
            .navigationTitle("剪贴板与短语")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if segment == 0 {
                        Menu {
                            Button("从系统剪贴板导入当前内容") {
                                if let text = UIPasteboard.general.string, !text.isEmpty {
                                    appState.addClipboardEntry(text)
                                }
                            }
                            Button("清空未置顶记录", role: .destructive) {
                                appState.clearUnpinnedClipboard()
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    } else {
                        Button {
                            showAddPhrase = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddPhrase) {
                addPhraseSheet
            }
        }
    }

    private var clipboardList: some View {
        List {
            if appState.clipboardItems.isEmpty {
                Section {
                    Text("暂无剪贴板历史。在键盘顶部看到「新复制」胶囊后点击粘贴，或点右上角导入，就会安全保存到本地历史与常用置顶中。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            } else {
                ForEach(appState.clipboardItems) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.text)
                            .font(.body)
                            .lineLimit(4)
                        HStack(spacing: 8) {
                            Label(item.category.badgeText, systemImage: item.category.systemIconName)
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            if let code = item.extractedCode {
                                Text("验证码: \(code)")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(Design.Palette.surfaceSoft))
                                    .foregroundStyle(Color(Design.Palette.ink))
                                    .clipShape(Capsule())
                            }
                            if item.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                            Text(item.createdAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            appState.togglePinClipboard(id: item.id)
                        } label: {
                            Label(item.isPinned ? "取消置顶" : "置顶", systemImage: item.isPinned ? "pin.slash" : "pin")
                        }
                        .tint(.orange)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            appState.deleteClipboard(id: item.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button("复制到剪贴板") {
                            UIPasteboard.general.string = item.text
                        }
                        Button(item.isPinned ? "取消置顶" : "置顶") {
                            appState.togglePinClipboard(id: item.id)
                        }
                        Button("删除", role: .destructive) {
                            appState.deleteClipboard(id: item.id)
                        }
                    }
                }
            }
        }
    }

    private var phrasesList: some View {
        List {
            ForEach(appState.quickPhrases) { phrase in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(phrase.title).font(.headline)
                        Spacer()
                        Text(phrase.category)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    Text(phrase.content)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        appState.deleteQuickPhrase(id: phrase.id)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var addPhraseSheet: some View {
        NavigationStack {
            Form {
                TextField("标题（如：收货地址）", text: $newPhraseTitle)
                TextField("分类（如：生活、职场、趣味）", text: $newPhraseCategory)
                TextField("短语正文", text: $newPhraseContent, axis: .vertical)
                    .lineLimit(3...6)
            }
            .navigationTitle("新增快捷短语")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { showAddPhrase = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        let t = newPhraseTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        let c = newPhraseContent.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cat = newPhraseCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty && !c.isEmpty {
                            appState.addQuickPhrase(title: t, content: c, category: cat.isEmpty ? "常用" : cat)
                            newPhraseTitle = ""
                            newPhraseContent = ""
                            showAddPhrase = false
                        }
                    }
                    .disabled(newPhraseTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              newPhraseContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
