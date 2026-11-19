import SwiftUI
import UIKit

struct DictionarySettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var showClearConfirm = false
    @State private var newCustomCode = ""
    @State private var newCustomWord = ""
    @State private var showTSVSheet = false
    @State private var tsvDraft = ""
    @State private var customStatusMessage: String?
    @State private var showUserLexiconTSVSheet = false
    @State private var userLexiconDraft = ""
    @State private var userLexiconStatusMessage: String?

    private var filteredWords: [UserWordEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return appState.userWords }
        return appState.userWords.filter {
            $0.word.lowercased().contains(q) || $0.py.lowercased().contains(q) || $0.abbr.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("输入方案与布局") {
                    Picker("键盘布局", selection: $appState.settings.layoutMode) {
                        ForEach(KeyboardLayoutMode.allCases) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    Picker("输入方案", selection: $appState.settings.inputScheme) {
                        ForEach(InputScheme.allCases) { s in
                            Text(s.displayName).tag(s)
                        }
                    }
                    Picker("中文标点样式", selection: $appState.settings.punctuationStyle) {
                        ForEach(PunctuationStyle.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    Picker("单手模式", selection: $appState.settings.handedness) {
                        ForEach(HandednessMode.allCases) { h in
                            Text(h.displayName).tag(h)
                        }
                    }
                    Picker("键盘高度", selection: $appState.settings.heightPreset) {
                        ForEach(KeyboardHeightPreset.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                }

                Section {
                    Toggle("四码唯一自动上屏", isOn: $appState.settings.wubiAutoCommitUnique4)
                    Toggle("显示剩余编码与 z 拼音反查码", isOn: $appState.settings.wubiShowCodeHints)
                } header: {
                    Text("五笔 86 专属设置")
                } footer: {
                    Text("内置 9.3 万标准五笔 86 码表（固定序不调频），支持第 5 码顶字上屏、空码重敲清空，以及按 z 临时拼音并实时反查五笔编码（如 znihao）。")
                }

                Section("手感与交互增强") {
                    Picker("震动反馈", selection: $appState.settings.hapticStrength) {
                        ForEach(HapticStrength.allCases) { h in
                            Text(h.displayName).tag(h)
                        }
                    }
                    Toggle("按键音效", isOn: $appState.settings.keySoundEnabled)
                    Toggle("按键放大气泡", isOn: $appState.settings.keyPopupEnabled)
                    Toggle("显示顶部副字符（1-0 / 符号 / 双拼助记）", isOn: $appState.settings.showSecondaryHints)
                    Toggle("显示独立顶部数字行 (1-0 五行布局)", isOn: $appState.settings.showNumberRow)
                    Toggle("26键滑行输入 (Glide Typing 中英轨迹成词)", isOn: $appState.settings.glideTypingEnabled)
                    Toggle("动态下一键热区防误触 (Apple 级键缝吸附)", isOn: $appState.settings.dynamicKeyHitBoxEnabled)
                    Toggle("显示底部下划标点提示", isOn: $appState.settings.showDownwardHints)
                    Toggle("上滑直接输入副字符", isOn: $appState.settings.swipeUpForHint)
                    Toggle("下划按键快速输入标点", isOn: $appState.settings.swipeDownForPunctuation)
                    Toggle("宿主输入框内嵌拼音预览", isOn: $appState.settings.inlineComposingEnabled)
                    Toggle("空格键触控板移光标", isOn: $appState.settings.spacebarTrackpadEnabled)
                }

                Section("智能输入与剪贴板") {
                    Toggle("输出繁体中文（OpenCC 词组级简繁切换）", isOn: $appState.settings.traditionalChineseEnabled)
                    Toggle("智能拼写纠错（4 路容错 + 鼻音/换位）", isOn: $appState.settings.typoCorrectionEnabled)
                    Toggle("模糊音未开时智能兜底（yingai→应该 / zidao→知道）", isOn: $appState.settings.fuzzyFallbackEnabled)
                    Toggle("中文与英文之间自动加空格", isOn: $appState.settings.panguSpaceLetters)
                    Toggle("中文与数字之间自动加空格", isOn: $appState.settings.panguSpaceDigits)
                    Toggle("首位候选 Emoji 实时联想（全方案通用）", isOn: $appState.settings.emojiSuggestionEnabled)
                    Toggle("自造词学习与词频记忆（30天半衰期）", isOn: $appState.settings.userLearningEnabled)
                    if appState.settings.userLearningEnabled {
                        Stepper(
                            "自动学习阈值：\(appState.settings.autoLearnThreshold) 次生效",
                            value: $appState.settings.autoLearnThreshold,
                            in: 1...5
                        )
                    }
                    Toggle("上下文二元消歧与下一词预测", isOn: $appState.settings.bigramPredictionEnabled)
                    Toggle("中英混输与英文词库直出排位", isOn: $appState.settings.smartEnglishCandidate)
                    Toggle("自动配对括号", isOn: $appState.settings.autoPairPunctuation)
                    Toggle("中文弯引号自动交替配对（“” / ‘’）", isOn: $appState.settings.smartQuotePairing)
                    Toggle("双击空格输入句号", isOn: $appState.settings.doubleSpacePeriod)
                    Toggle("英文句首自动大写", isOn: $appState.settings.autoCapitalizeEnglish)
                    Toggle("顶部剪贴板快速粘贴胶囊", isOn: $appState.settings.clipboardBannerEnabled)
                    Toggle("智能提取短信验证码", isOn: $appState.settings.smartOTPExtraction)
                    Toggle("自动读取剪贴板预览（需允许系统授权）", isOn: $appState.settings.autoReadClipboardPreview)
                }

                Section("趣味英文花样字体") {
                    Picker("当前英文字体", selection: $appState.settings.stylishFontID) {
                        ForEach(StylishFontStyle.allCases) { style in
                            Text("\(style.displayName)  \(style.previewSample)").tag(style.rawValue)
                        }
                    }
                }

                Section("模糊音设置（16 组全覆盖）") {
                    Toggle("zh ↔ z", isOn: $appState.settings.fuzzy.zhZ)
                    Toggle("ch ↔ c", isOn: $appState.settings.fuzzy.chC)
                    Toggle("sh ↔ s", isOn: $appState.settings.fuzzy.shS)
                    Toggle("n ↔ l", isOn: $appState.settings.fuzzy.nl)
                    Toggle("r ↔ l", isOn: $appState.settings.fuzzy.rl)
                    Toggle("f ↔ h", isOn: $appState.settings.fuzzy.fh)
                    Toggle("huang ↔ wang", isOn: $appState.settings.fuzzy.huangWang)
                    Toggle("an ↔ ang", isOn: $appState.settings.fuzzy.anAng)
                    Toggle("en ↔ eng", isOn: $appState.settings.fuzzy.enEng)
                    Toggle("in ↔ ing", isOn: $appState.settings.fuzzy.inIng)
                    Toggle("ian ↔ iang", isOn: $appState.settings.fuzzy.ianIang)
                    Toggle("uan ↔ uang", isOn: $appState.settings.fuzzy.uanUang)
                    Toggle("un ↔ ong", isOn: $appState.settings.fuzzy.unOng)
                    Toggle("an ↔ ai", isOn: $appState.settings.fuzzy.anAi)
                    Toggle("un ↔ iong", isOn: $appState.settings.fuzzy.unIong)
                    Toggle("eng ↔ ong", isOn: $appState.settings.fuzzy.engOng)
                }

                Section {
                    HStack(spacing: 8) {
                        TextField("编码 (如 mail)", text: $newCustomCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .frame(maxWidth: 110)
                        Divider()
                        TextField("短语内容（可用 \\n 换行）", text: $newCustomWord)
                        Button("添加") {
                            appState.addCustomWord(code: newCustomCode, word: newCustomWord)
                            customStatusMessage = "已添加自定义短语「\(newCustomCode.lowercased())」"
                            newCustomCode = ""
                            newCustomWord = ""
                        }
                        .disabled(newCustomCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  newCustomWord.isEmpty)
                    }

                    ForEach(appState.customWords) { entry in
                        HStack(spacing: 10) {
                            Text(entry.compactCode)
                                .font(.caption.monospaced().bold())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(entry.word)
                                .font(.body)
                                .lineLimit(2)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                appState.deleteCustomWord(id: entry.id)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }

                    HStack {
                        Button("导入 TSV (WowType)") {
                            tsvDraft = appState.exportCustomWordsTSV()
                            showTSVSheet = true
                        }
                        Spacer()
                        Button("复制导出 TSV") {
                            UIPasteboard.general.string = appState.exportCustomWordsTSV()
                            customStatusMessage = "已复制 \(appState.customWords.count) 条 TSV 短语到剪贴板"
                        }
                    }
                    .font(.subheadline)

                    if let status = customStatusMessage {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("自定义短语 / 快捷编码 (\(appState.customWords.count))")
                } footer: {
                    Text("兼容 WowType custom.tsv（编码<TAB>词，可用 \\n 换行）。输入对应字母编码时优先级最高，排在候选栏第 1 位。")
                }

                Section {
                    HStack {
                        Button("导入个人词库 (user.tsv)") {
                            userLexiconDraft = appState.exportUserLexiconTSV()
                            showUserLexiconTSVSheet = true
                        }
                        Spacer()
                        Button("复制导出 user.tsv") {
                            UIPasteboard.general.string = appState.exportUserLexiconTSV()
                            userLexiconStatusMessage = "已复制 \(appState.userWords.count) 条个人词库到剪贴板"
                        }
                    }
                    .font(.subheadline)

                    if let status = userLexiconStatusMessage {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if appState.userWords.isEmpty {
                        Text("暂无已学习的个人词条。平时打字选词或分段造词后会自动记忆在这里；若选错词立即按 ⌫ 退格，还会自动撤销误学记录。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        TextField("搜索自造词或拼音…", text: $searchText)
                        ForEach(filteredWords) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        if entry.isPinned {
                                            Image(systemName: "pin.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.orange)
                                        }
                                        Text(entry.word).font(.body.bold())
                                    }
                                    Text(entry.py)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(entry.freq)次")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    appState.togglePinUserWord(entry)
                                } label: {
                                    Label(entry.isPinned ? "取消置顶" : "置顶", systemImage: "pin")
                                }
                                .tint(.orange)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    appState.forgetUserWord(entry)
                                } label: {
                                    Label("遗忘", systemImage: "trash")
                                }
                            }
                        }
                        Button("清空全部个人词库", role: .destructive) {
                            showClearConfirm = true
                        }
                    }
                } header: {
                    Text("个人自造词与调频词库 (\(appState.userWords.count))")
                }
            }
            .navigationTitle("词库与设置")
            .sheet(isPresented: $showTSVSheet) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("每行一条：编码<TAB>短语（或逗号分隔），支持 \\n 换行")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $tsvDraft)
                            .font(.body.monospaced())
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding()
                    .navigationTitle("导入 TSV 短语码表")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { showTSVSheet = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("导入") {
                                let count = appState.importCustomWordsTSV(tsvDraft)
                                customStatusMessage = "成功导入 \(count) 条短语"
                                showTSVSheet = false
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showUserLexiconTSVSheet) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("每行一条：拼音<TAB>词条[<TAB>频次[<TAB>置顶]]（拼音可用空格或撇号分隔）")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $userLexiconDraft)
                            .font(.body.monospaced())
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding()
                    .navigationTitle("导入个人词库 (user.tsv)")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { showUserLexiconTSVSheet = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("导入") {
                                let count = appState.importUserLexiconTSV(userLexiconDraft)
                                userLexiconStatusMessage = "成功导入 \(count) 条个人词条"
                                showUserLexiconTSVSheet = false
                            }
                        }
                    }
                }
            }
            .alert("确定清空个人词库吗？", isPresented: $showClearConfirm) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) {
                    appState.clearUserLexicon()
                }
            } message: {
                Text("这不会影响内置的 39.6 万雾凇现代词库与 9.3 万五笔 86 码表，仅删除您平时积累的自造词和上下文联想记录。")
            }
        }
    }
}
