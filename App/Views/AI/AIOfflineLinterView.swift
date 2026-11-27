import SwiftUI
import UIKit

/// 100% 纯端侧离线「发前冷静室 · 情绪 / 防诈 / 文案质检仪」（0ms 零联网 · 0 Token 消耗）
struct AIOfflineLinterView: View {
    @EnvironmentObject private var appState: AppState
    let onSendToWorkbench: (String) -> Void

    @State private var inputText = ""
    @State private var showAutoFixDiff = true
    @State private var toast: String?

    private static let demoSample = "各位老板好,本周我们围绕核心业务持续赋能,形成了完整的闭环抓手,在iPhone16上完成了的的新版联调!综上所述,预计下周三提交发版,有需要可联系13812345678或者发邮件到dev@lingxi.im,非常非常感谢大家的支持!"
    private static let impulseSample = "我都说了几遍了？！你到底听不懂人话吗？？？这么简单的需求都能搞砸，真服了你，爱干干不干拉倒吧！！"
    private static let scamSample = "【客服通知】您的微信百万保障今日到期将自动扣费每月800元，不关闭将影响征信！请立即下载会议软件开启屏幕共享，并把短信验证码发我办理关闭。"
    private static let postSample = "姐妹们！这款面霜真的是全网第一、顶级配方，100%有效而且零副作用，立竿见影还能根治敏感肌！想要全网最低价的直接加微信或者私聊转账，手慢无！"

    var body: some View {
        let report = OfflineTextLinter.analyze(
            inputText,
            bannedCliches: appState.aiConfig.styleDNA.bannedAICliches,
            privacyCustomTerms: appState.aiConfig.privacyCustomTerms
        )
        let emotion = CommunicationGuardEngine.analyzeEmotion(inputText)
        let scam = CommunicationGuardEngine.analyzeScam(inputText)
        let spoken = VoiceTranscriptCleaner.clean(inputText)
        let linkClean = LinkPrivacyCleaner.clean(inputText)

        return List {
            Section {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $inputText)
                        .font(.subheadline)
                        .frame(minHeight: 112)
                    if inputText.isEmpty {
                        Text("粘贴要发出的消息、收到的可疑短信或口述草稿——0ms 离线扫描情绪冲动、诈骗套路、重复错字、AI 味与隐私外泄…")
                            .font(.subheadline)
                            .foregroundStyle(Color(Design.Palette.muted))
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                LXFlowLayout(spacing: 8, lineSpacing: 8) {
                    Button {
                        if let p = ConcealedPasteboard.readNonConcealedStringForUserPaste() {
                            inputText = p
                        } else {
                            toast = ConcealedPasteboard.isConcealed()
                                ? "受保护的保险箱机密不会直接粘贴进来"
                                : "剪贴板为空"
                        }
                    } label: {
                        Label("粘贴", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                    Button {
                        inputText = Self.demoSample
                    } label: {
                        Label("文案体检", systemImage: "text.badge.checkmark")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                    Button {
                        inputText = Self.impulseSample
                    } label: {
                        Label("冲动示例", systemImage: "flame.fill")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                    Button {
                        inputText = Self.scamSample
                    } label: {
                        Label("防诈示例", systemImage: "exclamationmark.shield.fill")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                    Button {
                        inputText = Self.postSample
                    } label: {
                        Label("防限流示例", systemImage: "megaphone.fill")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                    if !inputText.isEmpty {
                        Button("清空") { inputText = "" }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.stone))
                            .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("待检文本（100% 本机离线运行，不上传不耗 Token）")
            }

            if scam.isRisky {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.shield.fill")
                                .font(.title3)
                                .foregroundStyle(scam.level == .highRisk ? Color(Design.Palette.error) : Color(Design.Palette.warning))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(scam.level.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(scam.level == .highRisk ? Color(Design.Palette.error) : Color(Design.Palette.warning))
                                Text(scam.summaryBanner)
                                    .font(.caption)
                                    .foregroundStyle(Color(Design.Palette.ink))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        ForEach(scam.hits) { hit in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    LXTag(
                                        text: hit.category,
                                        tint: hit.isHighRisk ? Color(Design.Palette.error) : Color(Design.Palette.warning),
                                        filled: true
                                    )
                                    Text("命中「\(hit.matchedKeyword)」")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color(Design.Palette.stone))
                                }
                                Text(hit.warning)
                                    .font(.caption)
                                    .foregroundStyle(Color(Design.Palette.charcoal))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("防诈与交易避坑雷达")
                }
            }

            if linkClean.hasChanges {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            LXTag(
                                text: linkClean.summaryBadge,
                                icon: linkClean.hasIdentityLeakRisk ? "exclamationmark.shield.fill" : "link",
                                tint: linkClean.hasIdentityLeakRisk ? Color(Design.Palette.warning) : Color(Design.Palette.accent),
                                filled: true
                            )
                        }
                        Text(linkClean.extractedCleanURL ?? linkClean.cleanedText)
                            .font(.caption.monospaced())
                            .foregroundStyle(Color(Design.Palette.ink))
                            .textSelection(.enabled)
                        LXFlowLayout(spacing: 8, lineSpacing: 8) {
                            Button {
                                let cleanTarget = linkClean.extractedCleanURL ?? linkClean.cleanedText
                                inputText = cleanTarget
                                UIPasteboard.general.string = cleanTarget
                                toast = "已净化追踪参数并复制纯净链接"
                            } label: {
                                Label("应用并复制净链", systemImage: "sparkles")
                            }
                            .buttonStyle(LXCapsuleButtonStyle(prominent: true))
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("链接去追踪 · 防账号暴露净身")
                }
            }

            if report.hasPlatformRisks {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        LXTag(
                            text: "命中 \(report.platformRiskCount) 处发帖限流 / 广告法极限词",
                            icon: "megaphone.fill",
                            tint: Color(Design.Palette.warning),
                            filled: true
                        )
                        let platDiff = AITextDiffEngine.diff(original: report.originalText, revised: report.platformSafeText)
                        LXDiffHighlightText(report: platDiff)
                            .padding(.vertical, 2)
                        LXFlowLayout(spacing: 8, lineSpacing: 8) {
                            Button {
                                inputText = report.platformSafeText
                                UIPasteboard.general.string = report.platformSafeText
                                toast = "已替换为小红书/抖音合规表达并复制"
                            } label: {
                                Label("一键合规平替并复制", systemImage: "checkmark.seal.fill")
                            }
                            .buttonStyle(LXCapsuleButtonStyle(prominent: true))
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("发帖防限流 / 广告法合规平替")
                }
            }

            if report.totalChars > 0 {
                if emotion.level >= .tense {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                LXTag(
                                    text: "\(emotion.level.title) · \(emotion.score)°",
                                    icon: emotion.level >= .heated ? "flame.fill" : "exclamationmark.triangle.fill",
                                    tint: emotionColor(emotion.level),
                                    filled: true
                                )
                                Spacer(minLength: 4)
                                Text("先深呼吸 3 秒")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(Design.Palette.stone))
                            }

                            Text(emotion.advice)
                                .font(.footnote)
                                .foregroundStyle(Color(Design.Palette.ink))
                                .fixedSize(horizontal: false, vertical: true)

                            if !emotion.matchedTriggers.isEmpty {
                                LXFlowLayout(spacing: 6, lineSpacing: 6) {
                                    ForEach(emotion.matchedTriggers, id: \.self) { trigger in
                                        LXTag(text: "触发：\(trigger)", tint: emotionColor(emotion.level))
                                    }
                                }
                            }

                            if !emotion.quickCalmSuggestions.isEmpty {
                                Text("0ms 离线冷静替代表达（点按直接替换或复制）：")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(Design.Palette.stone))
                                ForEach(emotion.quickCalmSuggestions, id: \.self) { calm in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(calm)
                                            .font(.footnote)
                                            .foregroundStyle(Color(Design.Palette.ink))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Button("选用") {
                                            inputText = calm
                                            UIPasteboard.general.string = calm
                                            toast = "已切换为冷静表达并复制"
                                        }
                                        .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                                    }
                                    .padding(10)
                                    .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }

                            Button {
                                onSendToWorkbench("【情绪降火改写】请在不卑微、保住我核心诉求和底线的前提下，把下面这段带气的话改成冷静、克制、能推进解决问题的表达：\n\(inputText)")
                            } label: {
                                Label("送工作台高情商保底线降火改写", systemImage: "snowflake")
                            }
                            .buttonStyle(LXCapsuleButtonStyle(prominent: true))
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("发前冷静室 · 情绪温度计")
                    }
                }

                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .stroke(Color(Design.Palette.hairline), lineWidth: 5)
                            Circle()
                                .trim(from: 0, to: CGFloat(report.score) / 100.0)
                                .stroke(scoreColor(report.score), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("\(report.score)")
                                .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(Color(Design.Palette.ink))
                        }
                        .frame(width: 54, height: 54)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(report.scoreLabel)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color(Design.Palette.ink))
                            Text("\(report.totalChars) 字 · \(report.hanChars) 汉字 · \(report.englishWords) 英文词 · 口播约 \(report.estimatedSpeakSeconds) 秒")
                                .font(.caption)
                                .foregroundStyle(Color(Design.Palette.stone))
                        }
                    }
                    .padding(.vertical, 4)

                    LXFlowLayout(spacing: 6, lineSpacing: 6) {
                        LXTag(text: "\(report.sentenceCount) 句")
                        LXTag(
                            text: emotion.level == .calm ? "情绪平和" : "\(emotion.level.title) \(emotion.score)°",
                            icon: emotion.level == .calm ? "face.smiling" : "flame.fill",
                            tint: emotionColor(emotion.level),
                            filled: emotion.level >= .heated
                        )
                        if report.privacyHitCount > 0 {
                            LXTag(text: "隐私警报 \(report.privacyHitCount)", icon: "exclamationmark.shield.fill", tint: Color(Design.Palette.error), filled: true)
                        } else {
                            LXTag(text: "无隐私外泄", icon: "checkmark.shield", tint: Color(Design.Palette.success), filled: true)
                        }
                        let clicheCount = report.findings.filter { $0.category == .aiCliche }.count
                        if clicheCount > 0 {
                            LXTag(text: "AI 腔 \(clicheCount) 处", tint: Color(Design.Palette.warning), filled: true)
                        }
                    }
                } header: {
                    Text("综合体检总评")
                }

                if report.hasAutoFixChanges {
                    Section {
                        if showAutoFixDiff {
                            let diff = AITextDiffEngine.diff(original: report.originalText, revised: report.autoFixedText)
                            LXDiffHighlightText(report: diff)
                                .padding(.vertical, 4)
                        } else {
                            Text(report.autoFixedText)
                                .font(.subheadline)
                                .foregroundStyle(Color(Design.Palette.ink))
                                .textSelection(.enabled)
                                .padding(.vertical, 2)
                        }

                        LXFlowLayout(spacing: 8, lineSpacing: 8) {
                            Button {
                                inputText = report.autoFixedText
                                toast = "已应用一键离线排版修复"
                            } label: {
                                Label("应用自动修复", systemImage: "wand.and.stars")
                            }
                            .buttonStyle(LXCapsuleButtonStyle(prominent: true))

                            Button {
                                UIPasteboard.general.string = report.autoFixedText
                                toast = "已复制修复版"
                            } label: {
                                Label("复制修复版", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                            Button {
                                showAutoFixDiff.toggle()
                            } label: {
                                Label(showAutoFixDiff ? "看纯文本" : "红绿 Diff", systemImage: "arrow.left.arrow.right")
                            }
                            .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                        }
                    } header: {
                        Text("一键离线排版与错漏自动修复")
                    }
                }

                Section {
                    if report.findings.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Color(Design.Palette.success))
                            Text("未发现重复字、AI 味套话、排版问题或隐私外泄，表达清爽自然。")
                                .font(.footnote)
                                .foregroundStyle(Color(Design.Palette.charcoal))
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(report.findings) { item in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    LXTag(
                                        text: item.category.rawValue,
                                        tint: severityColor(item.severity),
                                        filled: item.severity >= .warning
                                    )
                                    Text(item.matchedText)
                                        .font(.caption.weight(.semibold).monospaced())
                                        .foregroundStyle(Color(Design.Palette.ink))
                                    Spacer(minLength: 4)
                                    if item.autoFixable {
                                        LXTag(text: "可自动修", tint: Color(Design.Palette.success), filled: true)
                                    }
                                }
                                Text(item.message)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(Color(Design.Palette.ink))
                                Text("建议：\(item.suggestion)")
                                    .font(.caption)
                                    .foregroundStyle(Color(Design.Palette.stone))
                            }
                            .padding(.vertical, 3)
                        }
                    }
                } header: {
                    Text("逐项诊断清单（\(report.findings.count)）")
                }

                Section("进阶操作") {
                    LXFlowLayout(spacing: 8, lineSpacing: 8) {
                        if spoken.hasChanges {
                            Button {
                                inputText = spoken.cleaned
                                UIPasteboard.general.string = spoken.cleaned
                                toast = "已去口水：\(spoken.summaryBadge)"
                            } label: {
                                Label("离线去口水", systemImage: "waveform")
                            }
                            .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                        }
                        if report.privacyHitCount > 0 {
                            Button {
                                UIPasteboard.general.string = report.privacyRedactedText
                                toast = "已复制隐私脱敏安全版"
                            } label: {
                                Label("复制脱敏版", systemImage: "checkmark.shield.fill")
                            }
                            .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                        }
                        Button {
                            let target = report.hasAutoFixChanges ? report.autoFixedText : report.originalText
                            onSendToWorkbench("请帮我去掉上面这段话里的 AI 味和冗长套话，保留原意改成自然说人话的版本：\n\(target)")
                        } label: {
                            Label("送工作台深度去 AI 味", systemImage: "sparkles")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: true))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("发前冷静室与质检")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($toast)
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 85 { return Color(Design.Palette.success) }
        if score >= 60 { return Color(Design.Palette.warning) }
        return Color(Design.Palette.error)
    }

    private func emotionColor(_ level: EmotionHeatLevel) -> Color {
        switch level {
        case .calm: return Color(Design.Palette.success)
        case .tense: return Color(Design.Palette.warning)
        case .heated, .explosive: return Color(Design.Palette.error)
        }
    }

    private func severityColor(_ severity: OfflineTextLinter.Severity) -> Color {
        switch severity {
        case .critical: return Color(Design.Palette.error)
        case .warning: return Color(Design.Palette.warning)
        case .info: return Color(Design.Palette.slate)
        }
    }
}
