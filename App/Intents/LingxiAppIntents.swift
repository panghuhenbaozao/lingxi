import AppIntents
import Foundation

// MARK: - 原生 iOS 16+ AppIntents / Siri / 快捷指令 / 操作按钮 / 专注模式自动化集成
// 仅编入主 App Target（App/Intents/），零第三方依赖，全面复用 Shared 层的三协议、隐私脱敏护盾、容灾切换与离线质检仪。

enum LingxiAIActionAppEnum: String, AppEnum {
    case polish
    case eqReply
    case translateEn
    case translateZh
    case summarize
    case proofread
    case structureList

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "灵犀 AI 技能"

    static var caseDisplayRepresentations: [LingxiAIActionAppEnum: DisplayRepresentation] = [
        .polish: "润色优化",
        .eqReply: "高情商回复",
        .translateEn: "译为英文",
        .translateZh: "译为中文",
        .summarize: "精简提炼",
        .proofread: "纠错查病句",
        .structureList: "转待办清单",
    ]

    var presetAction: AIPresetAction {
        switch self {
        case .polish: return .polish
        case .eqReply: return .eqReply
        case .translateEn: return .translateEn
        case .translateZh: return .translateZh
        case .summarize: return .summarize
        case .proofread: return .proofread
        case .structureList: return .structureList
        }
    }
}

enum LingxiScenePersonaAppEnum: String, AppEnum {
    case auto
    case bossClient
    case colleague
    case friendPartner
    case socialMedia
    case academic

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "灵犀沟通场景"

    static var caseDisplayRepresentations: [LingxiScenePersonaAppEnum: DisplayRepresentation] = [
        .auto: "自动语境",
        .bossClient: "领导与客户",
        .colleague: "同事协作",
        .friendPartner: "密友与伴侣",
        .socialMedia: "社交种草",
        .academic: "学术严谨",
    ]

    var scenePersona: AIScenePersona {
        switch self {
        case .auto: return .auto
        case .bossClient: return .bossClient
        case .colleague: return .colleague
        case .friendPartner: return .friendPartner
        case .socialMedia: return .socialMedia
        case .academic: return .academic
        }
    }
}

/// 1. 灵犀 AI 处理文本（供快捷指令、Siri、背面轻点、iPhone 操作按钮无缝串接剪贴板与任意自动化流）
struct LingxiAIRunTextIntent: AppIntent {
    static var title: LocalizedStringResource = "用灵犀 AI 处理文本"
    static var description = IntentDescription("使用灵犀已配置的 AI 引擎（支持隐私护盾与自动容灾）对文本执行润色、高情商回复、翻译、提炼或自定义指令。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "待处理文本")
    var text: String

    @Parameter(title: "处理方式", default: .polish)
    var action: LingxiAIActionAppEnum

    @Parameter(title: "自定义指令（可选，填写后优先使用）")
    var customInstruction: String?

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            return .result(value: "", dialog: "输入文本为空，未能执行处理。")
        }
        let cfg = AIConfig.load()
        guard cfg.isConfigured else {
            return .result(value: source, dialog: "请先在灵犀输入法 App 的「AI 智脑」中填写 API Key。")
        }

        let custom = (customInstruction ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let sys = custom.isEmpty ? action.presetAction.systemPrompt : custom
        let label = custom.isEmpty ? action.presetAction.title : "捷径自定义指令"

        let client = AIClient(timeout: 35)
        var acc = ""
        for try await delta in client.streamText(
            prompt: source,
            systemInstruction: sys,
            config: cfg,
            featureTag: "app_intent_ai",
            preferFast: !action.presetAction.prefersDeepModel,
            preferDeep: action.presetAction.prefersDeepModel
        ) {
            acc += delta
        }
        let clean = AITextSanitizer.clean(acc, streaming: false)
        guard !clean.isEmpty else {
            return .result(value: source, dialog: "模型未返回有效结果，请稍后重试。")
        }
        AIRecentHistoryStore.record(title: "捷径 · \(label)", output: clean, prompt: source)
        return .result(value: clean, dialog: "已完成\(label)。")
    }
}

/// 2. 灵犀离线文案体检与一键盘古排版（100% 离线零联网、0 Token）
struct LingxiOfflineLintFixIntent: AppIntent {
    static var title: LocalizedStringResource = "灵犀离线文案体检与排版"
    static var description = IntentDescription("100% 纯本机离线修正手滑重复字、中英文盘古空格与混用标点，并检测 AI 腔与隐私泄露风险。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "待体检文本")
    var text: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let cfg = AIConfig.load()
        let report = OfflineTextLinter.analyze(
            text,
            bannedCliches: cfg.styleDNA.bannedAICliches,
            privacyCustomTerms: cfg.privacyCustomTerms
        )
        let msg = report.privacyHitCount > 0
            ? "排版完成（评分 \(report.score)），注意检测到 \(report.privacyHitCount) 处敏感隐私信息。"
            : "离线排版体检完成（评分 \(report.score) · 发现 \(report.findings.count) 项建议）。"
        return .result(value: report.autoFixedText, dialog: IntentDialog("\(msg)"))
    }
}

/// 3. 切换灵犀 AI 沟通场景（极适合绑定 iOS「专注模式」自动化：上班自动切老板客户，下班自动切朋友日常）
struct LingxiSwitchScenePersonaIntent: AppIntent {
    static var title: LocalizedStringResource = "切换灵犀沟通场景"
    static var description = IntentDescription("切换灵犀输入法 AI 助手的当前沟通场景，并即时同步给键盘扩展，支持与 iOS 专注模式联动。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "目标场景", default: .bossClient)
    var scene: LingxiScenePersonaAppEnum

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        var cfg = AIConfig.load()
        cfg.activeScenePersona = scene.scenePersona
        _ = cfg.save()
        let name = scene.scenePersona.shortTitle
        return .result(value: name, dialog: "已将灵犀 AI 沟通场景切换为「\(name)」。")
    }
}

/// 4. 随手保存一条常用短语至灵犀键盘
struct LingxiAddQuickPhraseIntent: AppIntent {
    static var title: LocalizedStringResource = "添加到灵犀快捷短语"
    static var description = IntentDescription("将常用地址、话术或开票信息保存到灵犀快捷短语库，键盘立即可用。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "短语标题")
    var titleText: String

    @Parameter(title: "短语正文")
    var contentText: String

    @Parameter(title: "分类", default: "常用")
    var category: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let cleanContent = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanContent.isEmpty else {
            return .result(value: "", dialog: "短语正文为空，未保存。")
        }
        let cleanTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = cleanTitle.isEmpty ? String(cleanContent.prefix(10)) : cleanTitle
        let finalCat = category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "常用" : category
        QuickPhraseStore.add(title: finalTitle, content: cleanContent, category: finalCat)
        return .result(value: finalTitle, dialog: "已将「\(finalTitle)」添加到灵犀快捷短语。")
    }
}

enum LingxiLayoutPackAppEnum: String, AppEnum {
    case standard
    case hamsterPro = "hamster_pro"
    case developer
    case creator
    case business

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "灵犀键盘布局包"

    static var caseDisplayRepresentations: [LingxiLayoutPackAppEnum: DisplayRepresentation] = [
        .standard: "标准平衡",
        .hamsterPro: "仓式效率",
        .developer: "程序员极客",
        .creator: "写作创作者",
        .business: "商务办公",
    ]
}

/// 5. 切换灵犀键盘布局包（配合 iOS 专注模式自动化：办公切商务/极客包、创作切创作者包）
struct LingxiSwitchLayoutPackIntent: AppIntent {
    static var title: LocalizedStringResource = "切换灵犀键盘布局包"
    static var description = IntentDescription("一键切换灵犀键盘的划动映射、标点风格、数字行与专属符号条，适配不同专注模式。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "目标布局包", default: .developer)
    var pack: LingxiLayoutPackAppEnum

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let target = CustomKeyboardLayoutPack.find(id: pack.rawValue) else {
            return .result(value: "", dialog: "未找到对应布局包。")
        }
        var settings = LingxiSettings.load(force: true)
        target.apply(to: &settings)
        settings.save()
        return .result(value: target.name, dialog: "已将灵犀键盘切换为「\(target.name)」布局包。")
    }
}

/// 6. 一键开关灵犀隐身无痕模式（支持 Siri / 背面轻点 / 操作按钮快速进出无痕隐私输入）
struct LingxiToggleIncognitoIntent: AppIntent {
    static var title: LocalizedStringResource = "开关灵犀无痕模式"
    static var description = IntentDescription("开启或关闭灵犀输入法的隐身无痕模式：开启期间全面暂停词库学习、剪贴板记录、打字统计与 AI 历史留痕。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "开启无痕模式", default: true)
    var enabled: Bool

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        var settings = LingxiSettings.load(force: true)
        settings.incognitoModeEnabled = enabled
        settings.save()
        let msg = enabled ? "已开启灵犀隐身无痕模式，输入与剪贴板不再留痕。" : "已关闭灵犀无痕模式，恢复正常学习与记录。"
        return .result(value: enabled, dialog: IntentDialog("\(msg)"))
    }
}

/// 系统级 Siri 与快捷指令提供器（自动出现在 iOS 快捷指令 App 与聚焦搜索中）
struct LingxiAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .navy

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LingxiAIRunTextIntent(),
            phrases: [
                "用\(.applicationName)处理文本",
                "用\(.applicationName)润色文字",
            ],
            shortTitle: "灵犀 AI 处理",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: LingxiOfflineLintFixIntent(),
            phrases: [
                "用\(.applicationName)离线排版体检",
                "用\(.applicationName)检查文案",
            ],
            shortTitle: "离线文案体检",
            systemImageName: "text.badge.checkmark"
        )
        AppShortcut(
            intent: LingxiSwitchScenePersonaIntent(),
            phrases: [
                "切换\(.applicationName)沟通场景",
                "把\(.applicationName)切到工作场景",
            ],
            shortTitle: "切换沟通场景",
            systemImageName: "person.2.wave.2"
        )
        AppShortcut(
            intent: LingxiSwitchLayoutPackIntent(),
            phrases: [
                "切换\(.applicationName)键盘布局包",
                "把\(.applicationName)切成程序员键盘",
            ],
            shortTitle: "切换键盘布局包",
            systemImageName: "keyboard"
        )
        AppShortcut(
            intent: LingxiToggleIncognitoIntent(),
            phrases: [
                "开启\(.applicationName)无痕模式",
                "切换\(.applicationName)隐身模式",
            ],
            shortTitle: "开关无痕模式",
            systemImageName: "eye.slash.fill"
        )
        AppShortcut(
            intent: LingxiAddQuickPhraseIntent(),
            phrases: [
                "存到\(.applicationName)快捷短语",
            ],
            shortTitle: "存快捷短语",
            systemImageName: "text.badge.plus"
        )
    }
}
