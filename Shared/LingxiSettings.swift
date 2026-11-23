import Foundation

/// Toolbar button stable identity for layout persistence.
/// 已移除低频『表情』与『光标移动』按钮，保持键盘顶栏极简专注。
enum ToolbarButtonID: String, Codable, CaseIterable, Identifiable {
    case ai
    case translate
    case clipboard
    case layout
    case editPad
    case settings
    case undo
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .ai: return "灵犀 AI"
        case .translate: return "边打边译"
        case .clipboard: return "剪贴板"
        case .layout: return "九键/26键切换"
        case .editPad: return "专业编辑台"
        case .settings: return "快捷设置"
        case .undo: return "撤销删除"
        }
    }
    var symbolName: String {
        switch self {
        case .ai: return "sparkles"
        case .translate: return "character.bubble"
        case .clipboard: return "doc.on.clipboard"
        case .layout: return "rectangle.grid.3x2"
        case .editPad: return "cursorarrow.and.square.on.square.dashed"
        case .settings: return "slider.horizontal.3"
        case .undo: return "arrow.uturn.backward"
        }
    }
    /// 是否属于左侧主功能胶囊区（AI / 译），其余归于右侧工具区
    var isPrimaryLeftAction: Bool {
        self == .ai || self == .translate
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

/// 兼容旧版 JSON 中已废弃按钮（如 emoji / edit）的宽松解码器
private struct LegacyToolbarItemReader: Decodable {
    let buttonID: String?
    let isVisible: Bool?
    let order: Int?
}

/// 极简默认布局：左侧 [灵犀 AI][译] + 右侧 [剪贴板][快捷设置][撤销事件位]，
/// 『九键/26键切换』默认隐藏，可在 App『键盘工具栏』设置页随时开启。
let defaultToolbarLayout: [ToolbarItemConfig] = ToolbarButtonID.allCases.enumerated().map { idx, bid in
    let collapsedByDefault: Set<ToolbarButtonID> = [.layout, .editPad]
    return ToolbarItemConfig(buttonID: bid, isVisible: !collapsedByDefault.contains(bid), order: idx)
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
        enabledCount > 0
    }

    var enabledCount: Int {
        [zhZ, chC, shS, nl, rl, fh, huangWang,
         anAng, enEng, inIng, ianIang, uanUang,
         unOng, anAi, unIong, engOng].filter { $0 }.count
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
    var autoReadClipboardPreview: Bool = true
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
    var selectionMagicEnabled: Bool = true
    var autoFuzzyPromptEnabled: Bool = true
    var geoLocationBoostEnabled: Bool = true
    var aiGeoContextEnabled: Bool = true
    var customSwipeUpMap: [String: String] = [:]
    var customSwipeDownMap: [String: String] = [:]

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
        case selectionMagicEnabled, autoFuzzyPromptEnabled, geoLocationBoostEnabled, aiGeoContextEnabled, customSwipeUpMap, customSwipeDownMap
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
        if let legacyReaders = try c.decodeIfPresent([LegacyToolbarItemReader].self, forKey: .toolbarLayout) {
            let parsed: [ToolbarItemConfig] = legacyReaders.enumerated().compactMap { idx, r in
                guard let idStr = r.buttonID, let bid = ToolbarButtonID(rawValue: idStr) else { return nil }
                return ToolbarItemConfig(buttonID: bid, isVisible: r.isVisible ?? true, order: r.order ?? idx)
            }
            toolbarLayout = LingxiSettings.normalizedToolbarLayout(parsed)
        } else {
            toolbarLayout = LingxiSettings.normalizedToolbarLayout(d.toolbarLayout)
        }
        showComposingStrip = try c.decodeIfPresent(Bool.self, forKey: .showComposingStrip) ?? d.showComposingStrip
        let rawBarH = try c.decodeIfPresent(Double.self, forKey: .candidateBarHeight) ?? d.candidateBarHeight
        candidateBarHeight = min(64, max(44, rawBarH))
        let rawFont = try c.decodeIfPresent(Double.self, forKey: .candidateFontSize) ?? d.candidateFontSize
        candidateFontSize = min(22, max(14, rawFont))
        selectionMagicEnabled = try c.decodeIfPresent(Bool.self, forKey: .selectionMagicEnabled) ?? d.selectionMagicEnabled
        autoFuzzyPromptEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoFuzzyPromptEnabled) ?? d.autoFuzzyPromptEnabled
        geoLocationBoostEnabled = try c.decodeIfPresent(Bool.self, forKey: .geoLocationBoostEnabled) ?? d.geoLocationBoostEnabled
        aiGeoContextEnabled = try c.decodeIfPresent(Bool.self, forKey: .aiGeoContextEnabled) ?? d.aiGeoContextEnabled
        customSwipeUpMap = try c.decodeIfPresent([String: String].self, forKey: .customSwipeUpMap) ?? d.customSwipeUpMap
        customSwipeDownMap = try c.decodeIfPresent([String: String].self, forKey: .customSwipeDownMap) ?? d.customSwipeDownMap
    }

    private struct CustomKeymapSyncPayload: Codable {
        let up: [String: String]
        let down: [String: String]
    }

    private static let fileName = "lingxi_settings.json"
    static let customKeymapSyncFileName = "lingxi_custom_keymap.json"
    private static var cachedValue: LingxiSettings?
    private static var cachedStamp: String?

    /// 读取最新设置；利用文件内容指纹（mtime+size+inode）避免同秒读写误用旧缓存。
    static func load(force: Bool = false) -> LingxiSettings {
        let stamp = AppGroup.fileStamp(of: fileName)
        if !force, let cached = cachedValue, let stamp, cachedStamp == stamp {
            return cached
        }
        let loaded = AppGroup.readJSON(LingxiSettings.self, from: fileName) ?? LingxiSettings()
        cachedValue = loaded
        cachedStamp = stamp
        return loaded
    }

    @discardableResult
    func save(notify: Bool = true) -> Bool {
        if !customSwipeUpMap.isEmpty || !customSwipeDownMap.isEmpty {
            _ = AppGroup.writeJSON(CustomKeymapSyncPayload(up: customSwipeUpMap, down: customSwipeDownMap), to: Self.customKeymapSyncFileName)
        }
        let ok = AppGroup.writeJSON(self, to: Self.fileName)
        Self.cachedValue = self
        Self.cachedStamp = AppGroup.fileStamp(of: Self.fileName)
        if ok && notify {
            AppGroupNotifications.post(AppGroupNotifications.settingsChanged)
        }
        return ok
    }
}
