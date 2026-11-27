import SwiftUI
import UIKit

/// 专业 8 语种对照翻译工作室（双向回译校验 + 地道表达精讲 + 原生双语语音朗读）
struct AITranslationStudioView: View {
    @EnvironmentObject private var appState: AppState

    struct LanguageOption: Identifiable, Hashable {
        let id: String
        let name: String
        let speechLocale: String
    }

    enum TranslationTone: String, CaseIterable, Identifiable {
        case natural = "自然地道"
        case business = "商务正式"
        case academic = "学术书面"
        case casual = "极简口语"

        var id: String { rawValue }

        var rule: String {
            switch self {
            case .natural: return "译文自然地道、符合母语者日常习惯，拒绝翻译腔。"
            case .business: return "使用礼貌、严谨、得体的专业商务书面表达。"
            case .academic: return "措辞精准规范、逻辑严密，符合学术论文或正式文书标准。"
            case .casual: return "短小精悍、轻松口语，适合微信/即时聊天直接发。"
            }
        }
    }

    private static let languages: [LanguageOption] = [
        LanguageOption(id: "zh", name: "简体中文", speechLocale: "zh-CN"),
        LanguageOption(id: "en", name: "英语", speechLocale: "en-US"),
        LanguageOption(id: "ja", name: "日语", speechLocale: "ja-JP"),
        LanguageOption(id: "ko", name: "韩语", speechLocale: "ko-KR"),
        LanguageOption(id: "fr", name: "法语", speechLocale: "fr-FR"),
        LanguageOption(id: "de", name: "德语", speechLocale: "de-DE"),
        LanguageOption(id: "es", name: "西班牙语", speechLocale: "es-ES"),
        LanguageOption(id: "ru", name: "俄语", speechLocale: "ru-RU"),
    ]

    @State private var sourceLangID = "zh"
    @State private var targetLangID = "en"
    @State private var tone: TranslationTone = .natural
    @State private var sourceText = "不好意思久等了，方案我刚复核完，核心细节都在附件里，麻烦您抽空过目。"
    @State private var translatedText = ""
    @State private var backTranslatedText = ""
    @State private var idiomNotes = ""
    @State private var ttftMs: Int?
    @State private var isTranslating = false
    @State private var isCheckingBack = false
    @State private var isExplaining = false
    @State private var errorMsg: String?
    @State private var activeTask: Task<Void, Never>?
    @State private var feedback: String?
    @StateObject private var speaker = AISpeechSpeaker()

    private let client = AIClient(timeout: 45)

    private var sourceLang: LanguageOption {
        Self.languages.first(where: { $0.id == sourceLangID }) ?? Self.languages[0]
    }

    private var targetLang: LanguageOption {
        Self.languages.first(where: { $0.id == targetLangID }) ?? Self.languages[1]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 语种双向栏
                LXCard {
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Menu {
                                ForEach(Self.languages) { lang in
                                    Button(lang.name) { sourceLangID = lang.id }
                                }
                            } label: {
                                Text(sourceLang.name)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 38)
                                    .foregroundStyle(Color(Design.Palette.ink))
                                    .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }

                            Button {
                                let tmp = sourceLangID
                                sourceLangID = targetLangID
                                targetLangID = tmp
                                if !translatedText.isEmpty {
                                    sourceText = translatedText
                                    translatedText = ""
                                    backTranslatedText = ""
                                    idiomNotes = ""
                                }
                            } label: {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color(Design.Palette.accent))
                                    .frame(width: 38, height: 38)
                                    .background(Color(Design.Palette.accentSoft), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("互换源语言和目标语言")

                            Menu {
                                ForEach(Self.languages) { lang in
                                    Button(lang.name) { targetLangID = lang.id }
                                }
                            } label: {
                                Text(targetLang.name)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 38)
                                    .foregroundStyle(Color(Design.Palette.accent))
                                    .background(Color(Design.Palette.accentSoft), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }

                        Picker("译文腔调", selection: $tone) {
                            ForEach(TranslationTone.allCases) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                // 原文区
                LXCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("原文（\(sourceLang.name)）")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.stone))
                            Spacer()
                            Button {
                                speaker.toggleSpeak(sourceText, localeID: sourceLang.speechLocale, id: "src")
                            } label: {
                                Image(systemName: speaker.isSpeaking && speaker.activeID == "src" ? "stop.circle.fill" : "speaker.wave.2")
                                    .font(.subheadline)
                                    .foregroundStyle(Color(Design.Palette.slate))
                            }
                            .buttonStyle(.plain)
                            .disabled(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button("粘贴") {
                                if let s = ConcealedPasteboard.readNonConcealedStringForUserPaste() {
                                    sourceText = s
                                    feedback = "已粘贴原文"
                                } else if ConcealedPasteboard.isConcealed() {
                                    feedback = "受保护的保险箱机密不可直接粘贴给 AI"
                                }
                            }
                            .font(.caption.bold())
                            .foregroundStyle(Color(Design.Palette.accent))
                            .buttonStyle(.plain)
                        }

                        TextEditor(text: $sourceText)
                            .font(.subheadline)
                            .frame(minHeight: 88)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .disabled(isTranslating)
                    }
                }

                if isTranslating {
                    Button {
                        activeTask?.cancel()
                    } label: {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small).tint(Color(Design.Palette.error))
                            Text("正在翻译… 点击停止")
                        }
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true, tint: Color(Design.Palette.error)))
                } else {
                    Button {
                        runTranslate()
                    } label: {
                        Label("翻译为\(targetLang.name)（\(tone.rawValue)）", systemImage: "globe")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                    .disabled(!appState.aiConfig.isConfigured || sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let err = errorMsg {
                    Text(err).font(.caption).foregroundStyle(Color(Design.Palette.error))
                }

                // 译文结果卡
                if !translatedText.isEmpty {
                    LXCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                LXTag(text: "\(targetLang.name) · \(tone.rawValue)", tint: Color(Design.Palette.accent), filled: true)
                                Spacer()
                                if let ms = ttftMs {
                                    Text("首字 \(ms)ms")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(Color(Design.Palette.stone))
                                }
                            }

                            Text(translatedText)
                                .font(.body)
                                .foregroundStyle(Color(Design.Palette.ink))
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)

                            if !isTranslating {
                                LXFlowLayout(spacing: 8, lineSpacing: 8) {
                                    Button {
                                        UIPasteboard.general.string = translatedText
                                        feedback = "已复制译文"
                                    } label: {
                                        Label("复制译文", systemImage: "doc.on.doc")
                                    }
                                    .buttonStyle(LXCapsuleButtonStyle(prominent: true))

                                    Button {
                                        speaker.toggleSpeak(translatedText, localeID: targetLang.speechLocale, id: "dst")
                                    } label: {
                                        Label(speaker.isSpeaking && speaker.activeID == "dst" ? "停止朗读" : "朗读发音", systemImage: "speaker.wave.2")
                                    }
                                    .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                                    Button {
                                        runBackTranslation()
                                    } label: {
                                        HStack(spacing: 4) {
                                            if isCheckingBack { ProgressView().controlSize(.mini) }
                                            Label("回译核验", systemImage: "arrow.uturn.backward")
                                        }
                                    }
                                    .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                                    .disabled(isCheckingBack)

                                    Button {
                                        runIdiomBreakdown()
                                    } label: {
                                        HStack(spacing: 4) {
                                            if isExplaining { ProgressView().controlSize(.mini) }
                                            Label("地道解析", systemImage: "book")
                                        }
                                    }
                                    .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                                    .disabled(isExplaining)
                                }
                            }
                        }
                    }
                }

                // 双向回译核验卡
                if !backTranslatedText.isEmpty {
                    LXCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("双向回译核验（译文 → \(sourceLang.name)）", systemImage: "checkmark.seal")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.success))
                            Text(backTranslatedText)
                                .font(.subheadline)
                                .foregroundStyle(Color(Design.Palette.ink))
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }

                // 地道表达解析卡
                if !idiomNotes.isEmpty {
                    LXCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("地道表达与核心词汇精讲", systemImage: "lightbulb.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.accent))
                            Text(idiomNotes)
                                .font(.footnote)
                                .foregroundStyle(Color(Design.Palette.charcoal))
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .lxReadableWidth()
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("专业多语翻译台")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($feedback)
        .onDisappear {
            activeTask?.cancel()
            speaker.stop()
        }
    }

    private func runTranslate() {
        let src = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty else { return }
        let sys = "你是精通\(sourceLang.name)与\(targetLang.name)的母语级专业译者。请将用户输入精准翻译为\(targetLang.name)。\(tone.rule) 只输出最终译文，不要加任何解释、引号或前缀。"
        let cfg = appState.aiConfig
        errorMsg = nil
        translatedText = ""
        backTranslatedText = ""
        idiomNotes = ""
        ttftMs = nil
        isTranslating = true

        activeTask = Task {
            let start = Date()
            var acc = ""
            defer {
                Task { @MainActor in
                    isTranslating = false
                    appState.refreshAll()
                }
            }
            do {
                for try await d in client.streamText(prompt: src, systemInstruction: sys, config: cfg, featureTag: "studio_translate", preferFast: true) {
                    if Task.isCancelled { break }
                    if ttftMs == nil {
                        let ms = Int(Date().timeIntervalSince(start) * 1000)
                        await MainActor.run { ttftMs = ms }
                    }
                    acc += d
                    let snap = AITextSanitizer.clean(acc, streaming: true)
                    await MainActor.run { translatedText = snap }
                }
                let finalOut = AITextSanitizer.clean(acc, streaming: false)
                await MainActor.run {
                    translatedText = finalOut
                    if !finalOut.isEmpty {
                        AIRecentHistoryStore.record(title: "翻译 · \(targetLang.name)", output: finalOut, prompt: src)
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { errorMsg = error.localizedDescription }
                }
            }
        }
    }

    private func runBackTranslation() {
        let txt = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !txt.isEmpty else { return }
        isCheckingBack = true
        backTranslatedText = ""
        let sys = "请把这段\(targetLang.name)如实直译回\(sourceLang.name)，用于核对语义与语气是否走样。只输出回译结果。"
        let cfg = appState.aiConfig
        Task {
            var acc = ""
            defer { Task { @MainActor in isCheckingBack = false } }
            do {
                for try await d in client.streamText(prompt: txt, systemInstruction: sys, config: cfg, featureTag: "back_translate", preferFast: true) {
                    acc += d
                    let snap = AITextSanitizer.clean(acc, streaming: true)
                    await MainActor.run { backTranslatedText = snap }
                }
                let finalOut = AITextSanitizer.clean(acc, streaming: false)
                await MainActor.run { backTranslatedText = finalOut }
            } catch {
                await MainActor.run { feedback = "回译失败：\(error.localizedDescription)" }
            }
        }
    }

    private func runIdiomBreakdown() {
        let txt = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !txt.isEmpty else { return }
        isExplaining = true
        idiomNotes = ""
        let sys = "请用简明简体中文点评下面这段\(targetLang.name)译文：挑出 3 个最地道的关键短语/词汇做释义，并补充 1 个更口语或更正式的替代表达（不要用 Markdown 星号）。"
        let cfg = appState.aiConfig
        Task {
            var acc = ""
            defer { Task { @MainActor in isExplaining = false } }
            do {
                for try await d in client.streamText(prompt: txt, systemInstruction: sys, config: cfg, featureTag: "idiom_notes", preferFast: true) {
                    acc += d
                    let snap = AITextSanitizer.clean(acc, streaming: true)
                    await MainActor.run { idiomNotes = snap }
                }
                let finalOut = AITextSanitizer.clean(acc, streaming: false)
                await MainActor.run { idiomNotes = finalOut }
            } catch {
                await MainActor.run { feedback = "解析失败：\(error.localizedDescription)" }
            }
        }
    }
}
