import Foundation

/// Toolbar button stable identity for layout persistence.
enum ToolbarButtonID: String, Codable, CaseIterable, Identifiable {
    case ai
    case translate
    case clipboard
    case emoji
    case edit
    case layout
    case settings
    case undo
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .ai: return "AI"
        case .translate: return "Translate"
        case .clipboard: return "Clipboard"
        case .emoji: return "Emoji"
        case .edit: return "Edit"
        case .layout: return "Layout"
        case .settings: return "Settings"
        case .undo: return "Undo"
        }
    }
    var symbolName: String {
        switch self {
        case .ai: return "sparkles"
        case .translate: return "character.bubble"
        case .clipboard: return "doc.on.clipboard"
        case .emoji: return "face.smiling"
        case .edit: return "textformat"
        case .layout: return "rectangle.grid.3x2"
        case .settings: return "gearshape"
        case .undo: return "arrow.uturn.left"
        }
    }
}

/// Layout config for a single toolbar button (visibility + order).
struct ToolbarItemConfig: Codable, Equatable, Identifiable {
    var buttonID: ToolbarButtonID
    var isVisible: Bool
    var order: Int
    var id: String { buttonID.rawValue }
    init(buttonID: ToolbarButtonID, isVisible: Bool = true, order: Int) {
        self.buttonID = buttonID
        self.isVisible = isVisible
        self.order = order
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let bid = try c.decodeIfPresent(ToolbarButtonID.self, forKey: .buttonID) ?? .settings
        buttonID = bid
        isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? (ToolbarButtonID.allCases.firstIndex(of: bid) ?? 0)
    }
}

/// Default toolbar layout matching the original fixed button order.
let defaultToolbarLayout: [ToolbarItemConfig] = ToolbarButtonID.allCases.enumerated().map { idx, bid in
    ToolbarItemConfig(buttonID: bid, isVisible: true, order: idx)
}

/// 键盘排布模式。
enum KeyboardLayoutMode: String, Codable, CaseIterable, Identifiable {
    case qwerty26
    case t9Nine

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .qwerty26: return "26键"
        case .t9Nine: return "九宫格"
        }
    }
}

/// 输入方案（完整覆盖全拼 + 7 种主流双拼 + 五笔 86，对齐 WowType）。
enum InputScheme: String, Codable, CaseIterable, Identifiable {
    case quanpin
    case xiaohe
    case ziranma
    case microsoft
    case sogou
    case abc
    case ziguang
    case pinyinjiajia
    case wubi86

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .quanpin: return "全拼"
        case .xiaohe: return "小鹤双拼"
        case .ziranma: return "自然码双拼"
        case .microsoft: return "微软双拼"
        case .sogou: return "搜狗双拼"
        case .abc: return "智能ABC双拼"
        case .ziguang: return "紫光双拼"
        case .pinyinjiajia: return "拼音加加双拼"
        case .wubi86: return "五笔86"
        }
    }

    var shortBadge: String {
        switch self {
        case .quanpin: return "全拼"
        case .xiaohe: return "小鹤"
        case .ziranma: return "自然"
        case .microsoft: return "微软"
        case .sogou: return "搜狗"
        case .abc: return "ABC"
        case .ziguang: return "紫光"
        case .pinyinjiajia: return "加加"
        case .wubi86: return "五笔"
        }
    }

    var isDoublePinyin: Bool {
        switch self {
        case .xiaohe, .ziranma, .microsoft, .sogou, .abc, .ziguang, .pinyinjiajia:
            return true
        case .quanpin, .wubi86:
            return false
        }
    }

    var isWubi: Bool { self == .wubi86 }

    /// 微软/搜狗/紫光双拼用分号键 `;` 表示韵母 `ing`。
    var usesSemicolonFinal: Bool {
        self == .microsoft || self == .sogou || self == .ziguang
    }
}

/// 标点样式：中文全角（含数字后自动半角与弯引号配对）或英文半角。
enum PunctuationStyle: String, Codable, CaseIterable, Identifiable {
    case fullwidth
    case halfwidth

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fullwidth: return "中文全角"
        case .halfwidth: return "英文半角"
        }
    }

    var shortBadge: String {
        switch self {
        case .fullwidth: return "全角"
        case .halfwidth: return "半角"
        }
    }
}

/// 键盘高度预设。
enum KeyboardHeightPreset: String, Codable, CaseIterable, Identifiable {
    case compact
    case standard
    case comfortable

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compact: return "紧凑"
        case .standard: return "标准"
        case .comfortable: return "舒适"
        }
    }

    /// 键盘按键区基准高度（不含顶部候选/工具栏）。
    var bodyHeight: Double {
        switch self {
        case .compact: return 198
        case .standard: return 218
        case .comfortable: return 240
        }
    }
}

/// 单手模式。
enum HandednessMode: String, Codable, CaseIterable, Identifiable {
    case full
    case left
    case right

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .full: return "全宽"
        case .left: return "左手"
        case .right: return "右手"
        }
    }
}

/// 震动反馈强度。
enum HapticStrength: String, Codable, CaseIterable, Identifiable {
    case off
    case light
    case medium
    case strong

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "关闭"
        case .light: return "轻微"
        case .medium: return "适中"
        case .strong: return "清脆"
        }
    }
}

/// 模糊音设置（16 组全覆盖，对齐主流双拼/全拼/WowType）。
struct FuzzyPinyinOptions: Codable, Equatable {
    // 声母模糊（平翘舌 / 鼻边音 / 唇齿音 / h-w）
    var zhZ: Bool = false
    var chC: Bool = false
    var shS: Bool = false
    var nl: Bool = false
    var rl: Bool = false
    var fh: Bool = false
    var huangWang: Bool = false

    // 韵母模糊（前后鼻音 / 复韵母）
    var anAng: Bool = false
    var enEng: Bool = false
    var inIng: Bool = false
    var ianIang: Bool = false
    var uanUang: Bool = false
    var unOng: Bool = false
    var anAi: Bool = false
    var unIong: Bool = false
    var engOng: Bool = false

    var isAnyEnabled: Bool {
        zhZ || chC || shS || nl || rl || fh || huangWang ||
        anAng || enEng || inIng || ianIang || uanUang ||
        unOng || anAi || unIong || engOng
    }
}

/// 全局设置模型，持久化在 App Group 共享目录中（所有新增字段向后兼容旧版 JSON）。
struct LingxiSettings: Codable, Equatable {
    var layoutMode: KeyboardLayoutMode = .qwerty26
    var inputScheme: InputScheme = .quanpin
    var fuzzy: FuzzyPinyinOptions = FuzzyPinyinOptions()
    var heightPreset: KeyboardHeightPreset = .standard
    var handedness: HandednessMode = .full
    var hapticStrength: HapticStrength = .light
    var keySoundEnabled: Bool = true
    var keyPopupEnabled: Bool = true
    var showSecondaryHints: Bool = true
    var showDownwardHints: Bool = true
    var swipeUpForHint: Bool = true
    var swipeDownForPunctuation: Bool = true
    var inlineComposingEnabled: Bool = false
    var spacebarTrackpadEnabled: Bool = true
    var autoPairPunctuation: Bool = true
    var punctuationStyle: PunctuationStyle = .fullwidth
    var smartQuotePairing: Bool = true
    var panguSpaceLetters: Bool = false
    var panguSpaceDigits: Bool = false
    var traditionalChineseEnabled: Bool = false
    var typoCorrectionEnabled: Bool = true
    var fuzzyFallbackEnabled: Bool = true
    var glideTypingEnabled: Bool = true
    var showNumberRow: Bool = false
    var dynamicKeyHitBoxEnabled: Bool = true
    var emojiSuggestionEnabled: Bool = true
    var smartEnglishCandidate: Bool = true
    var userLearningEnabled: Bool = true
    var autoLearnThreshold: Int = 1
    var bigramPredictionEnabled: Bool = true
    var wubiAutoCommitUnique4: Bool = true
    var wubiShowCodeHints: Bool = true
    var clipboardBannerEnabled: Bool = true
    var autoReadClipboardPreview: Bool = false
    var smartOTPExtraction: Bool = true
    var autoCapitalizeEnglish: Bool = true
    var doubleSpacePeriod: Bool = true
    var typingStatsEnabled: Bool = false
    var translateTargetLang: String = "英文"
    var translateFormalTone: Bool = false
    var stylishFontID: String = StylishFontStyle.normal.rawValue
    var toolbarLayout: [ToolbarItemConfig] = defaultToolbarLayout
    var showComposingStrip: Bool = true
    var candidateBarHeight: Double = 50
    var candidateFontSize: Double = 16.5

    /// Ensure every known toolbar button appears exactly once, preserving saved order.
    static func normalizedToolbarLayout(_ layout: [ToolbarItemConfig]) -> [ToolbarItemConfig] {
        var seen = Set<ToolbarButtonID>()
        var result: [ToolbarItemConfig] = []
        for item in layout.sorted(by: { $0.order < $1.order }) where !seen.contains(item.buttonID) {
            seen.insert(item.buttonID)
            result.append(item)
        }
        for bid in ToolbarButtonID.allCases where !seen.contains(bid) {
            result.append(ToolbarItemConfig(buttonID: bid, isVisible: true, order: result.count))
        }
        return result.enumerated().map { idx, item in
            var copy = item
            copy.order = idx
            return copy
        }
    }

    private enum CodingKeys: String, CodingKey {
        case layoutMode, inputScheme, fuzzy, heightPreset, handedness, hapticStrength
        case keySoundEnabled, keyPopupEnabled, showSecondaryHints, showDownwardHints
        case swipeUpForHint, swipeDownForPunctuation, inlineComposingEnabled
        case spacebarTrackpadEnabled, autoPairPunctuation, punctuationStyle, smartQuotePairing
        case panguSpaceLetters, panguSpaceDigits, traditionalChineseEnabled
        case typoCorrectionEnabled, fuzzyFallbackEnabled, glideTypingEnabled
        case showNumberRow, dynamicKeyHitBoxEnabled
        case emojiSuggestionEnabled, smartEnglishCandidate
        case userLearningEnabled, autoLearnThreshold, bigramPredictionEnabled
        case wubiAutoCommitUnique4, wubiShowCodeHints
        case clipboardBannerEnabled, autoReadClipboardPreview, smartOTPExtraction
        case autoCapitalizeEnglish, doubleSpacePeriod, typingStatsEnabled
        case translateTargetLang, translateFormalTone, stylishFontID
        case toolbarLayout, showComposingStrip, candidateBarHeight, candidateFontSize
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LingxiSettings()
        layoutMode = try c.decodeIfPresent(KeyboardLayoutMode.self, forKey: .layoutMode) ?? d.layoutMode
        inputScheme = try c.decodeIfPresent(InputScheme.self, forKey: .inputScheme) ?? d.inputScheme
        fuzzy = try c.decodeIfPresent(FuzzyPinyinOptions.self, forKey: .fuzzy) ?? d.fuzzy
        heightPreset = try c.decodeIfPresent(KeyboardHeightPreset.self, forKey: .heightPreset) ?? d.heightPreset
        handedness = try c.decodeIfPresent(HandednessMode.self, forKey: .handedness) ?? d.handedness
        hapticStrength = try c.decodeIfPresent(HapticStrength.self, forKey: .hapticStrength) ?? d.hapticStrength
        keySoundEnabled = try c.decodeIfPresent(Bool.self, forKey: .keySoundEnabled) ?? d.keySoundEnabled
        keyPopupEnabled = try c.decodeIfPresent(Bool.self, forKey: .keyPopupEnabled) ?? d.keyPopupEnabled
        showSecondaryHints = try c.decodeIfPresent(Bool.self, forKey: .showSecondaryHints) ?? d.showSecondaryHints
        showDownwardHints = try c.decodeIfPresent(Bool.self, forKey: .showDownwardHints) ?? d.showDownwardHints
        swipeUpForHint = try c.decodeIfPresent(Bool.self, forKey: .swipeUpForHint) ?? d.swipeUpForHint
        swipeDownForPunctuation = try c.decodeIfPresent(Bool.self, forKey: .swipeDownForPunctuation) ?? d.swipeDownForPunctuation
        inlineComposingEnabled = try c.decodeIfPresent(Bool.self, forKey: .inlineComposingEnabled) ?? d.inlineComposingEnabled
        spacebarTrackpadEnabled = try c.decodeIfPresent(Bool.self, forKey: .spacebarTrackpadEnabled) ?? d.spacebarTrackpadEnabled
        autoPairPunctuation = try c.decodeIfPresent(Bool.self, forKey: .autoPairPunctuation) ?? d.autoPairPunctuation
        punctuationStyle = try c.decodeIfPresent(PunctuationStyle.self, forKey: .punctuationStyle) ?? d.punctuationStyle
        smartQuotePairing = try c.decodeIfPresent(Bool.self, forKey: .smartQuotePairing) ?? d.smartQuotePairing
        panguSpaceLetters = try c.decodeIfPresent(Bool.self, forKey: .panguSpaceLetters) ?? d.panguSpaceLetters
        panguSpaceDigits = try c.decodeIfPresent(Bool.self, forKey: .panguSpaceDigits) ?? d.panguSpaceDigits
        traditionalChineseEnabled = try c.decodeIfPresent(Bool.self, forKey: .traditionalChineseEnabled) ?? d.traditionalChineseEnabled
        typoCorrectionEnabled = try c.decodeIfPresent(Bool.self, forKey: .typoCorrectionEnabled) ?? d.typoCorrectionEnabled
        fuzzyFallbackEnabled = try c.decodeIfPresent(Bool.self, forKey: .fuzzyFallbackEnabled) ?? d.fuzzyFallbackEnabled
        glideTypingEnabled = try c.decodeIfPresent(Bool.self, forKey: .glideTypingEnabled) ?? d.glideTypingEnabled
        showNumberRow = try c.decodeIfPresent(Bool.self, forKey: .showNumberRow) ?? d.showNumberRow
        dynamicKeyHitBoxEnabled = try c.decodeIfPresent(Bool.self, forKey: .dynamicKeyHitBoxEnabled) ?? d.dynamicKeyHitBoxEnabled
        emojiSuggestionEnabled = try c.decodeIfPresent(Bool.self, forKey: .emojiSuggestionEnabled) ?? d.emojiSuggestionEnabled
        smartEnglishCandidate = try c.decodeIfPresent(Bool.self, forKey: .smartEnglishCandidate) ?? d.smartEnglishCandidate
        userLearningEnabled = try c.decodeIfPresent(Bool.self, forKey: .userLearningEnabled) ?? d.userLearningEnabled
        let rawThreshold = try c.decodeIfPresent(Int.self, forKey: .autoLearnThreshold) ?? d.autoLearnThreshold
        autoLearnThreshold = min(5, max(1, rawThreshold))
        bigramPredictionEnabled = try c.decodeIfPresent(Bool.self, forKey: .bigramPredictionEnabled) ?? d.bigramPredictionEnabled
        wubiAutoCommitUnique4 = try c.decodeIfPresent(Bool.self, forKey: .wubiAutoCommitUnique4) ?? d.wubiAutoCommitUnique4
        wubiShowCodeHints = try c.decodeIfPresent(Bool.self, forKey: .wubiShowCodeHints) ?? d.wubiShowCodeHints
        clipboardBannerEnabled = try c.decodeIfPresent(Bool.self, forKey: .clipboardBannerEnabled) ?? d.clipboardBannerEnabled
        autoReadClipboardPreview = try c.decodeIfPresent(Bool.self, forKey: .autoReadClipboardPreview) ?? d.autoReadClipboardPreview
        smartOTPExtraction = try c.decodeIfPresent(Bool.self, forKey: .smartOTPExtraction) ?? d.smartOTPExtraction
        autoCapitalizeEnglish = try c.decodeIfPresent(Bool.self, forKey: .autoCapitalizeEnglish) ?? d.autoCapitalizeEnglish
        doubleSpacePeriod = try c.decodeIfPresent(Bool.self, forKey: .doubleSpacePeriod) ?? d.doubleSpacePeriod
        typingStatsEnabled = try c.decodeIfPresent(Bool.self, forKey: .typingStatsEnabled) ?? d.typingStatsEnabled
        translateTargetLang = try c.decodeIfPresent(String.self, forKey: .translateTargetLang) ?? d.translateTargetLang
        translateFormalTone = try c.decodeIfPresent(Bool.self, forKey: .translateFormalTone) ?? d.translateFormalTone
        stylishFontID = try c.decodeIfPresent(String.self, forKey: .stylishFontID) ?? d.stylishFontID
        let rawToolbarLayout = try c.decodeIfPresent([ToolbarItemConfig].self, forKey: .toolbarLayout) ?? d.toolbarLayout
        toolbarLayout = LingxiSettings.normalizedToolbarLayout(rawToolbarLayout)
        showComposingStrip = try c.decodeIfPresent(Bool.self, forKey: .showComposingStrip) ?? d.showComposingStrip
        let rawBarH = try c.decodeIfPresent(Double.self, forKey: .candidateBarHeight) ?? d.candidateBarHeight
        candidateBarHeight = min(64, max(44, rawBarH))
        let rawFont = try c.decodeIfPresent(Double.self, forKey: .candidateFontSize) ?? d.candidateFontSize
        candidateFontSize = min(22, max(14, rawFont))
    }

    private static let fileName = "lingxi_settings.json"
    private static var cachedValue: LingxiSettings?
    private static var cachedMTime: Date?

    /// 读取最新设置；利用文件修改时间避免频繁重复反序列化。
    static func load(force: Bool = false) -> LingxiSettings {
        let mtime = AppGroup.modificationDate(of: fileName)
        if !force, let cached = cachedValue, cachedMTime == mtime {
            return cached
        }
        let loaded = AppGroup.readJSON(LingxiSettings.self, from: fileName) ?? LingxiSettings()
        cachedValue = loaded
        cachedMTime = mtime
        return loaded
    }

    @discardableResult
    func save() -> Bool {
        let ok = AppGroup.writeJSON(self, to: Self.fileName)
        Self.cachedValue = self
        Self.cachedMTime = AppGroup.modificationDate(of: Self.fileName)
        return ok
    }
}
