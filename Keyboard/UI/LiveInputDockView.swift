import UIKit

/// 位于候选词栏正上方的常驻实时输入工作坞（永不被拼音候选词遮挡！）：
/// - `.translate`: 双行 86pt 实时 AI 翻译栏（上行：语种/语气/实时原文滚动预览/粘贴/语音/清空；下行：大字号 2 行流式实时译文卡片 + 上屏/原文按钮）
/// - `.aiDraft`: 单行 52pt 实时 AI 提问输入框（打中文拼音选字时始终可见，支持随时粘贴剪贴板、清空与一键发送问 AI）
final class LiveInputDockView: UIView {
    struct TranslateState: Equatable {
        var targetLanguage: String
        var formalTone: Bool
        var sourceText: String
        var liveComposing: String
        var translatedText: String
        var isTranslating: Bool
        var errorText: String?
    }

    enum Mode: Equatable {
        case hidden
        case translate(TranslateState)
        case aiDraft(draft: String, liveComposing: String)

        var preferredHeight: CGFloat {
            switch self {
            case .hidden: return 0
            case .translate: return 88
            case .aiDraft: return 50
            }
        }
    }

    enum Action {
        // 实时翻译动作
        case cycleTranslateTarget
        case toggleTranslateTone
        case pasteIntoTranslate
        case openVoiceTranslator
        case clearTranslateSource
        case closeTranslate
        case commitTranslatedText
        case commitTranslateSource
        case tapTranslateErrorFix

        // AI 打字框动作
        case pasteIntoAIDraft
        case clearAIDraft
        case sendAIDraft
        case returnToAIPanel
    }

    var onAction: ((Action) -> Void)?

    private var currentMode: Mode = .hidden
    private var theme: ResolvedTheme?

    private let bottomHairline = UIView()

    // MARK: - 实时翻译容器 (88pt)
    private let translateContainer = UIView()
    private let langButton = ActionClosureButton(type: .system)
    private let toneButton = ActionClosureButton(type: .system)
    private let sourceScroll = LingxiScrollView()
    private let sourceLabel = UILabel()
    private let translatePasteBtn = ActionClosureButton(type: .system)
    private let translateVoiceBtn = ActionClosureButton(type: .system)
    private let translateClearBtn = ActionClosureButton(type: .system)
    private let translateCloseBtn = ActionClosureButton(type: .system)

    private let resultCardBtn = ActionClosureButton(type: .custom)
    private let resultLabel = UILabel()
    private let commitSourceBtn = ActionClosureButton(type: .system)
    private let commitTranslatedBtn = ActionClosureButton(type: .system)

    // MARK: - AI 打字草稿容器 (50pt)
    private let aiDraftContainer = UIView()
    private let aiInputBox = UIView()
    private let aiDraftScroll = LingxiScrollView()
    private let aiDraftLabel = UILabel()
    private let aiPasteBtn = ActionClosureButton(type: .system)
    private let aiClearBtn = ActionClosureButton(type: .system)
    private let aiSendBtn = ActionClosureButton(type: .system)
    private let aiBackBtn = ActionClosureButton(type: .system)

    private var hasTranslateError = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        bottomHairline.isUserInteractionEnabled = false
        addSubview(bottomHairline)

        // --- 实时翻译区 ---
        translateContainer.isHidden = true
        addSubview(translateContainer)

        styleMiniPill(langButton, title: "中⇄英", fontSize: 11.5)
        langButton.actionHandler = { [weak self] in self?.onAction?(.cycleTranslateTarget) }
        translateContainer.addSubview(langButton)

        styleMiniPill(toneButton, title: "口语", fontSize: 11)
        toneButton.actionHandler = { [weak self] in self?.onAction?(.toggleTranslateTone) }
        translateContainer.addSubview(toneButton)

        sourceScroll.showsHorizontalScrollIndicator = false
        sourceScroll.showsVerticalScrollIndicator = false
        sourceScroll.alwaysBounceHorizontal = true
        sourceScroll.layer.cornerRadius = 8
        sourceScroll.layer.cornerCurve = .continuous
        translateContainer.addSubview(sourceScroll)

        sourceLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        sourceLabel.numberOfLines = 1
        sourceLabel.lineBreakMode = .byClipping
        sourceScroll.addSubview(sourceLabel)

        styleMiniPill(translatePasteBtn, title: "粘贴", fontSize: 11)
        translatePasteBtn.actionHandler = { [weak self] in self?.onAction?(.pasteIntoTranslate) }
        translateContainer.addSubview(translatePasteBtn)

        let micCfg = UIImage.SymbolConfiguration(pointSize: 11.5, weight: .semibold)
        translateVoiceBtn.setImage(UIImage(systemName: "mic.fill", withConfiguration: micCfg), for: .normal)
        translateVoiceBtn.layer.cornerRadius = 11
        translateVoiceBtn.layer.cornerCurve = .continuous
        translateVoiceBtn.accessibilityLabel = "实时语音互译"
        translateVoiceBtn.actionHandler = { [weak self] in self?.onAction?(.openVoiceTranslator) }
        translateContainer.addSubview(translateVoiceBtn)

        let clrCfg = UIImage.SymbolConfiguration(pointSize: 10.5, weight: .semibold)
        translateClearBtn.setImage(UIImage(systemName: "trash", withConfiguration: clrCfg), for: .normal)
        translateClearBtn.layer.cornerRadius = 11
        translateClearBtn.layer.cornerCurve = .continuous
        translateClearBtn.accessibilityLabel = "清空翻译内容"
        translateClearBtn.actionHandler = { [weak self] in self?.onAction?(.clearTranslateSource) }
        translateContainer.addSubview(translateClearBtn)

        let xCfg = UIImage.SymbolConfiguration(pointSize: 10.5, weight: .bold)
        translateCloseBtn.setImage(UIImage(systemName: "xmark", withConfiguration: xCfg), for: .normal)
        translateCloseBtn.layer.cornerRadius = 11
        translateCloseBtn.layer.cornerCurve = .continuous
        translateCloseBtn.accessibilityLabel = "关闭实时翻译"
        translateCloseBtn.actionHandler = { [weak self] in self?.onAction?(.closeTranslate) }
        translateContainer.addSubview(translateCloseBtn)

        // 下行：实时译文大卡片（点卡片本身也可直接上屏或修复权限）
        resultCardBtn.layer.cornerRadius = 10
        resultCardBtn.layer.cornerCurve = .continuous
        resultCardBtn.layer.borderWidth = 0.6
        resultCardBtn.actionHandler = { [weak self] in
            guard let self else { return }
            if self.hasTranslateError {
                self.onAction?(.tapTranslateErrorFix)
            } else {
                self.onAction?(.commitTranslatedText)
            }
        }
        translateContainer.addSubview(resultCardBtn)

        resultLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        resultLabel.numberOfLines = 2
        resultLabel.lineBreakMode = .byTruncatingTail
        resultLabel.isUserInteractionEnabled = false
        resultCardBtn.addSubview(resultLabel)

        styleMiniPill(commitSourceBtn, title: "原文", fontSize: 11.5)
        commitSourceBtn.actionHandler = { [weak self] in self?.onAction?(.commitTranslateSource) }
        translateContainer.addSubview(commitSourceBtn)

        styleMiniPill(commitTranslatedBtn, title: "上屏", fontSize: 12.5)
        commitTranslatedBtn.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .bold)
        commitTranslatedBtn.actionHandler = { [weak self] in self?.onAction?(.commitTranslatedText) }
        translateContainer.addSubview(commitTranslatedBtn)

        // --- AI 打字草稿区 ---
        aiDraftContainer.isHidden = true
        addSubview(aiDraftContainer)

        aiInputBox.layer.cornerRadius = 12
        aiInputBox.layer.cornerCurve = .continuous
        aiInputBox.layer.borderWidth = 0.8
        aiDraftContainer.addSubview(aiInputBox)

        aiDraftScroll.showsHorizontalScrollIndicator = false
        aiDraftScroll.showsVerticalScrollIndicator = false
        aiDraftScroll.alwaysBounceHorizontal = true
        aiInputBox.addSubview(aiDraftScroll)

        aiDraftLabel.font = .systemFont(ofSize: 13.5, weight: .medium)
        aiDraftLabel.numberOfLines = 1
        aiDraftLabel.lineBreakMode = .byClipping
        aiDraftScroll.addSubview(aiDraftLabel)

        styleMiniPill(aiPasteBtn, title: "粘贴", fontSize: 11.5)
        aiPasteBtn.actionHandler = { [weak self] in self?.onAction?(.pasteIntoAIDraft) }
        aiDraftContainer.addSubview(aiPasteBtn)

        aiClearBtn.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: clrCfg), for: .normal)
        aiClearBtn.layer.cornerRadius = 11
        aiClearBtn.accessibilityLabel = "清空 AI 输入"
        aiClearBtn.actionHandler = { [weak self] in self?.onAction?(.clearAIDraft) }
        aiDraftContainer.addSubview(aiClearBtn)

        styleMiniPill(aiSendBtn, title: "问 AI", fontSize: 12.5)
        aiSendBtn.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .bold)
        aiSendBtn.actionHandler = { [weak self] in self?.onAction?(.sendAIDraft) }
        aiDraftContainer.addSubview(aiSendBtn)

        aiBackBtn.setImage(UIImage(systemName: "chevron.down", withConfiguration: xCfg), for: .normal)
        aiBackBtn.layer.cornerRadius = 11
        aiBackBtn.accessibilityLabel = "返回 AI 面板"
        aiBackBtn.actionHandler = { [weak self] in self?.onAction?(.returnToAIPanel) }
        aiDraftContainer.addSubview(aiBackBtn)
    }

    private func styleMiniPill(_ btn: ActionClosureButton, title: String, fontSize: CGFloat) {
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: fontSize, weight: .semibold)
        btn.titleLabel?.adjustsFontSizeToFitWidth = true
        btn.titleLabel?.minimumScaleFactor = 0.8
        btn.layer.cornerRadius = 11
        btn.layer.cornerCurve = .continuous
    }

    func apply(theme: ResolvedTheme) {
        self.theme = theme
        backgroundColor = theme.toolbarBg
        bottomHairline.backgroundColor = theme.keyBorder.withAlphaComponent(0.75)

        langButton.backgroundColor = theme.accentFill.withAlphaComponent(0.16)
        langButton.setTitleColor(theme.candidateHighlight, for: .normal)

        toneButton.backgroundColor = theme.specialKeyFill
        toneButton.setTitleColor(theme.keyText, for: .normal)

        sourceScroll.backgroundColor = theme.keyFill.withAlphaComponent(0.85)
        sourceLabel.textColor = theme.keyText

        for btn in [translatePasteBtn, translateVoiceBtn, translateClearBtn, translateCloseBtn, commitSourceBtn, aiPasteBtn, aiBackBtn] {
            btn.backgroundColor = theme.specialKeyFill
            btn.setTitleColor(theme.keyText, for: .normal)
            btn.tintColor = theme.keyText
        }
        aiClearBtn.backgroundColor = .clear
        aiClearBtn.tintColor = theme.keyHintText

        resultCardBtn.backgroundColor = theme.keyFill.withAlphaComponent(0.96)
        resultCardBtn.layer.borderColor = theme.accentFill.withAlphaComponent(0.32).cgColor
        resultLabel.textColor = theme.candidateHighlight

        commitTranslatedBtn.backgroundColor = theme.accentFill
        commitTranslatedBtn.setTitleColor(theme.accentText, for: .normal)

        aiInputBox.backgroundColor = theme.keyFill
        aiInputBox.layer.borderColor = theme.accentFill.withAlphaComponent(0.45).cgColor
        aiDraftLabel.textColor = theme.keyText

        aiSendBtn.backgroundColor = theme.accentFill
        aiSendBtn.setTitleColor(theme.accentText, for: .normal)
    }

    func update(mode: Mode) {
        currentMode = mode
        switch mode {
        case .hidden:
            isHidden = true
            translateContainer.isHidden = true
            aiDraftContainer.isHidden = true
            hasTranslateError = false

        case .translate(let tr):
            isHidden = false
            translateContainer.isHidden = false
            aiDraftContainer.isHidden = true

            let combinedSource = tr.sourceText + (tr.liveComposing.isEmpty ? "" : "[\(tr.liveComposing)]")
            let hasForeign = tr.sourceText.range(of: "[A-Za-z]", options: .regularExpression) != nil
            let hasChinese = tr.sourceText.range(of: "[\\u4e00-\\u9fff]", options: .regularExpression) != nil
            let dirTitle: String
            if hasForeign && !hasChinese {
                dirTitle = "外→中"
            } else if tr.targetLanguage == "英文" {
                dirTitle = "中⇄英"
            } else {
                dirTitle = "中→\(tr.targetLanguage)"
            }
            langButton.setTitle(dirTitle, for: .normal)
            toneButton.setTitle(tr.formalTone ? "正式" : "口语", for: .normal)
            if let theme {
                toneButton.backgroundColor = tr.formalTone ? theme.accentFill.withAlphaComponent(0.20) : theme.specialKeyFill
                toneButton.setTitleColor(tr.formalTone ? theme.candidateHighlight : theme.keyText, for: .normal)
            }

            if combinedSource.isEmpty {
                sourceLabel.text = "输入或粘贴原文，下方实时出译文…"
                sourceLabel.textColor = theme?.keyHintText ?? .secondaryLabel
            } else {
                sourceLabel.text = "\(combinedSource) ▍"
                sourceLabel.textColor = theme?.keyText ?? .label
            }
            translateClearBtn.isHidden = tr.sourceText.isEmpty && tr.liveComposing.isEmpty

            if let err = tr.errorText, !err.isEmpty {
                hasTranslateError = true
                resultLabel.text = "⚠️ \(err)（点此一键修复）"
                resultLabel.textColor = .systemOrange
            } else {
                hasTranslateError = false
                if tr.isTranslating && tr.translatedText.isEmpty {
                    resultLabel.text = "✨ 正在实时流式翻译…"
                    resultLabel.textColor = theme?.keyHintText ?? .secondaryLabel
                } else if tr.translatedText.isEmpty {
                    resultLabel.text = tr.sourceText.isEmpty
                        ? "实时译文会一直显示在这里（不被候选词挡住）"
                        : "停顿片刻自动出译文，也可按回车立刻翻译…"
                    resultLabel.textColor = theme?.keyHintText ?? .secondaryLabel
                } else {
                    resultLabel.text = tr.isTranslating ? "\(tr.translatedText) ▍" : tr.translatedText
                    resultLabel.textColor = theme?.candidateHighlight ?? .systemBlue
                }
            }

            let canCommitTr = !tr.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            commitTranslatedBtn.isEnabled = canCommitTr
            commitTranslatedBtn.alpha = canCommitTr ? 1.0 : 0.45

            let canCommitSrc = !tr.sourceText.isEmpty
            commitSourceBtn.isEnabled = canCommitSrc
            commitSourceBtn.alpha = canCommitSrc ? 1.0 : 0.45

        case .aiDraft(let draft, let composing):
            isHidden = false
            translateContainer.isHidden = true
            aiDraftContainer.isHidden = false
            hasTranslateError = false

            let full = draft + (composing.isEmpty ? "" : "[\(composing)]")
            if full.isEmpty {
                aiDraftLabel.text = "✨ 直接打字问 AI，或点右侧「粘贴」…"
                aiDraftLabel.textColor = theme?.keyHintText ?? .secondaryLabel
            } else {
                aiDraftLabel.text = "✨ \(full) ▍"
                aiDraftLabel.textColor = theme?.keyText ?? .label
            }
            let hasContent = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !composing.isEmpty
            aiClearBtn.isHidden = !hasContent
            aiSendBtn.isEnabled = hasContent
            aiSendBtn.alpha = hasContent ? 1.0 : 0.45
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 10, bounds.height > 10 else { return }
        bottomHairline.frame = CGRect(x: 0, y: bounds.height - 0.5, width: bounds.width, height: 0.5)

        let pad: CGFloat = 8

        if !translateContainer.isHidden {
            translateContainer.frame = bounds
            // Row 1: y = 5, h = 28
            let r1Y: CGFloat = 5
            let r1H: CGFloat = 28
            let langW: CGFloat = 46
            let toneW: CGFloat = 34
            let pasteW: CGFloat = 36
            let voiceW: CGFloat = 28
            let clearW: CGFloat = translateClearBtn.isHidden ? 0 : 26
            let closeW: CGFloat = 26

            langButton.frame = CGRect(x: pad, y: r1Y, width: langW, height: r1H)
            toneButton.frame = CGRect(x: langButton.frame.maxX + 4, y: r1Y, width: toneW, height: r1H)

            var rightEdge = bounds.width - pad
            translateCloseBtn.frame = CGRect(x: rightEdge - closeW, y: r1Y, width: closeW, height: r1H)
            rightEdge = translateCloseBtn.frame.minX - 4

            if !translateClearBtn.isHidden {
                translateClearBtn.frame = CGRect(x: rightEdge - clearW, y: r1Y, width: clearW, height: r1H)
                rightEdge = translateClearBtn.frame.minX - 4
            }
            translateVoiceBtn.frame = CGRect(x: rightEdge - voiceW, y: r1Y, width: voiceW, height: r1H)
            rightEdge = translateVoiceBtn.frame.minX - 4

            translatePasteBtn.frame = CGRect(x: rightEdge - pasteW, y: r1Y, width: pasteW, height: r1H)
            rightEdge = translatePasteBtn.frame.minX - 5

            let srcX = toneButton.frame.maxX + 5
            let srcW = max(60, rightEdge - srcX)
            sourceScroll.frame = CGRect(x: srcX, y: r1Y, width: srcW, height: r1H)
            let fitSrc = sourceLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: r1H))
            let innerSrcW = max(srcW - 12, ceil(fitSrc.width) + 4)
            sourceLabel.frame = CGRect(x: 6, y: 0, width: innerSrcW, height: r1H)
            sourceScroll.contentSize = CGSize(width: innerSrcW + 12, height: r1H)
            if sourceScroll.contentSize.width > srcW + 1 {
                sourceScroll.contentOffset = CGPoint(x: sourceScroll.contentSize.width - srcW, y: 0)
            } else {
                sourceScroll.contentOffset = .zero
            }

            // Row 2: y = 38, h = 44 (宽敞两行实时译文卡片 + 右侧上屏按钮)
            let r2Y: CGFloat = 38
            let r2H: CGFloat = max(38, bounds.height - r2Y - 6)
            let commitW: CGFloat = 52
            let srcBtnW: CGFloat = 38

            commitTranslatedBtn.frame = CGRect(x: bounds.width - pad - commitW, y: r2Y, width: commitW, height: r2H)
            commitSourceBtn.frame = CGRect(x: commitTranslatedBtn.frame.minX - 4 - srcBtnW, y: r2Y, width: srcBtnW, height: r2H)

            let cardW = max(80, commitSourceBtn.frame.minX - 6 - pad)
            resultCardBtn.frame = CGRect(x: pad, y: r2Y, width: cardW, height: r2H)
            resultLabel.frame = resultCardBtn.bounds.insetBy(dx: 9, dy: 4)
        }

        if !aiDraftContainer.isHidden {
            aiDraftContainer.frame = bounds
            let h: CGFloat = 34
            let y: CGFloat = (bounds.height - h) / 2
            let backW: CGFloat = 28
            let sendW: CGFloat = 54
            let pasteW: CGFloat = 40
            let clearW: CGFloat = aiClearBtn.isHidden ? 0 : 24

            aiBackBtn.frame = CGRect(x: bounds.width - pad - backW, y: y, width: backW, height: h)
            aiSendBtn.frame = CGRect(x: aiBackBtn.frame.minX - 4 - sendW, y: y, width: sendW, height: h)
            aiPasteBtn.frame = CGRect(x: aiSendBtn.frame.minX - 4 - pasteW, y: y, width: pasteW, height: h)

            let boxW = max(80, aiPasteBtn.frame.minX - 6 - pad)
            aiInputBox.frame = CGRect(x: pad, y: y, width: boxW, height: h)

            if !aiClearBtn.isHidden {
                aiClearBtn.frame = CGRect(x: aiInputBox.frame.maxX - clearW - 4, y: y + (h - 24) / 2, width: 24, height: 24)
            }
            let scrollW = max(40, boxW - 14 - (aiClearBtn.isHidden ? 0 : clearW))
            aiDraftScroll.frame = CGRect(x: 9, y: 0, width: scrollW, height: h)
            let fitDraft = aiDraftLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: h))
            let innerW = max(scrollW, ceil(fitDraft.width) + 6)
            aiDraftLabel.frame = CGRect(x: 0, y: 0, width: innerW, height: h)
            aiDraftScroll.contentSize = CGSize(width: innerW, height: h)
            if innerW > scrollW + 1 {
                aiDraftScroll.contentOffset = CGPoint(x: innerW - scrollW, y: 0)
            } else {
                aiDraftScroll.contentOffset = .zero
            }
        }
    }
}
