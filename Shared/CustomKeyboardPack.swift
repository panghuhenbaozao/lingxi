import Foundation

/// 声明式可分享「灵犀自定义键盘布局包」（对标 Hamster YAML / azooKey CustardKit）：
/// 打包上下划字符/动作命令映射、数字行、标点风格、盘古空格与场景快捷符号条，
/// 支持在键盘内 1 键秒切（标准 / 仓式效率 / 程序员 / 创作者 / 商务）与 JSON 文件导入导出分享。
struct CustomKeyboardLayoutPack: Codable, Identifiable, Equatable {
    var format: String = "LINGXI-KEYMAP-PACK-V1"
    var id: String = UUID().uuidString
    var name: String
    var subtitle: String = ""
    var icon: String = "keyboard"
    var swipeUpMap: [String: String] = [:]
    var swipeDownMap: [String: String] = [:]
    var showNumberRow: Bool = false
    var punctuationStyle: PunctuationStyle = .fullwidth
    var panguSpaceLetters: Bool = false
    var panguSpaceDigits: Bool = false
    var translateFormalTone: Bool = false
    var quickStripTokens: [String] = []

    init(
        format: String = "LINGXI-KEYMAP-PACK-V1",
        id: String = UUID().uuidString,
        name: String,
        subtitle: String = "",
        icon: String = "keyboard",
        swipeUpMap: [String: String] = [:],
        swipeDownMap: [String: String] = [:],
        showNumberRow: Bool = false,
        punctuationStyle: PunctuationStyle = .fullwidth,
        panguSpaceLetters: Bool = false,
        panguSpaceDigits: Bool = false,
        translateFormalTone: Bool = false,
        quickStripTokens: [String] = []
    ) {
        self.format = format
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.icon = icon
        self.swipeUpMap = swipeUpMap
        self.swipeDownMap = swipeDownMap
        self.showNumberRow = showNumberRow
        self.punctuationStyle = punctuationStyle
        self.panguSpaceLetters = panguSpaceLetters
        self.panguSpaceDigits = panguSpaceDigits
        self.translateFormalTone = translateFormalTone
        self.quickStripTokens = quickStripTokens
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? "LINGXI-KEYMAP-PACK-V1"
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "自定义布局包"
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "keyboard"
        swipeUpMap = try c.decodeIfPresent([String: String].self, forKey: .swipeUpMap) ?? [:]
        swipeDownMap = try c.decodeIfPresent([String: String].self, forKey: .swipeDownMap) ?? [:]
        showNumberRow = try c.decodeIfPresent(Bool.self, forKey: .showNumberRow) ?? false
        punctuationStyle = try c.decodeIfPresent(PunctuationStyle.self, forKey: .punctuationStyle) ?? .fullwidth
        panguSpaceLetters = try c.decodeIfPresent(Bool.self, forKey: .panguSpaceLetters) ?? false
        panguSpaceDigits = try c.decodeIfPresent(Bool.self, forKey: .panguSpaceDigits) ?? false
        translateFormalTone = try c.decodeIfPresent(Bool.self, forKey: .translateFormalTone) ?? false
        quickStripTokens = try c.decodeIfPresent([String].self, forKey: .quickStripTokens) ?? []
    }

    /// 将布局包一键应用到 `LingxiSettings`
    func apply(to settings: inout LingxiSettings) {
        settings.activeLayoutPackID = id
        settings.customSwipeUpMap = swipeUpMap
        settings.customSwipeDownMap = swipeDownMap
        settings.showNumberRow = showNumberRow
        settings.punctuationStyle = punctuationStyle
        settings.panguSpaceLetters = panguSpaceLetters
        settings.panguSpaceDigits = panguSpaceDigits
        settings.translateFormalTone = translateFormalTone
        if !swipeUpMap.isEmpty { settings.swipeUpForHint = true }
        if !swipeDownMap.isEmpty { settings.swipeDownForPunctuation = true }
    }

    /// 从当前用户设置导出为可分享布局包
    static func fromCurrentSettings(_ settings: LingxiSettings, name: String = "我的灵犀布局包") -> CustomKeyboardLayoutPack {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return CustomKeyboardLayoutPack(
            id: "custom_\(UUID().uuidString.prefix(8).lowercased())",
            name: cleanName.isEmpty ? "我的灵犀布局包" : cleanName,
            subtitle: "导出自当前灵犀键盘配置（\(settings.customSwipeUpMap.count + settings.customSwipeDownMap.count) 项自定义划动）",
            icon: "square.and.arrow.up",
            swipeUpMap: settings.customSwipeUpMap,
            swipeDownMap: settings.customSwipeDownMap,
            showNumberRow: settings.showNumberRow,
            punctuationStyle: settings.punctuationStyle,
            panguSpaceLetters: settings.panguSpaceLetters,
            panguSpaceDigits: settings.panguSpaceDigits,
            translateFormalTone: settings.translateFormalTone
        )
    }

    func exportJSON() -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(self)
    }

    static func decodeJSON(_ data: Data) -> CustomKeyboardLayoutPack? {
        guard let pack = try? JSONDecoder().decode(CustomKeyboardLayoutPack.self, from: data),
              pack.format.hasPrefix("LINGXI-KEYMAP-PACK"),
              !pack.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return pack
    }

    /// 5 套开箱即用的专业场景布局包
    static let builtInPacks: [CustomKeyboardLayoutPack] = [
        CustomKeyboardLayoutPack(
            id: "standard",
            name: "标准平衡",
            subtitle: "默认纯净键面，零学习成本",
            icon: "keyboard",
            swipeUpMap: [:],
            swipeDownMap: [:],
            showNumberRow: false,
            punctuationStyle: .fullwidth,
            panguSpaceLetters: false,
            panguSpaceDigits: false,
            translateFormalTone: false,
            quickStripTokens: ["，", "。", "？", "！", "、", "～"]
        ),
        CustomKeyboardLayoutPack(
            id: "hamster_pro",
            name: "仓式效率",
            subtitle: "J/K 以词定字 + 下划撤/贴/润/三版/光标/简繁",
            icon: "bolt.circle.fill",
            swipeUpMap: KeyboardSwipeCommand.hamsterEfficiencyUpPreset,
            swipeDownMap: KeyboardSwipeCommand.hamsterEfficiencyDownPreset,
            showNumberRow: false,
            punctuationStyle: .fullwidth,
            panguSpaceLetters: true,
            panguSpaceDigits: false,
            translateFormalTone: false,
            quickStripTokens: ["#firstChar", "#lastChar", "#paste", "#undo", "#lintFix"]
        ),
        CustomKeyboardLayoutPack(
            id: "developer",
            name: "程序员极客",
            subtitle: "独立数字行 + 半角标点 + 盘古空格 + 编程符号下划",
            icon: "chevron.left.forwardslash.chevron.right",
            swipeUpMap: [
                "j": KeyboardSwipeCommand.firstChar.rawValue,
                "k": KeyboardSwipeCommand.lastChar.rawValue,
            ],
            swipeDownMap: [
                "a": "@", "s": "/", "d": "$", "f": "()", "g": "{}", "h": "[]", "k": "->",
                "z": KeyboardSwipeCommand.undo.rawValue,
                "v": KeyboardSwipeCommand.paste.rawValue,
                "c": KeyboardSwipeCommand.lintFix.rawValue,
            ],
            showNumberRow: true,
            punctuationStyle: .halfwidth,
            panguSpaceLetters: true,
            panguSpaceDigits: true,
            translateFormalTone: false,
            quickStripTokens: ["()", "{}", "[]", "<>", "=>", "->", "//", "!=", "&&", "||"]
        ),
        CustomKeyboardLayoutPack(
            id: "creator",
            name: "写作创作者",
            subtitle: "全角标点 + 盘古空格 + 下划润色/三版/离线排版体检",
            icon: "pencil.and.outline",
            swipeUpMap: [
                "j": KeyboardSwipeCommand.firstChar.rawValue,
                "k": KeyboardSwipeCommand.lastChar.rawValue,
            ],
            swipeDownMap: [
                "q": "「」", "w": "『』", "e": "《》", "r": "——", "t": "……",
                "z": KeyboardSwipeCommand.undo.rawValue,
                "c": KeyboardSwipeCommand.aiPolish.rawValue,
                "v": KeyboardSwipeCommand.paste.rawValue,
                "b": KeyboardSwipeCommand.aiThreeVariants.rawValue,
                "n": KeyboardSwipeCommand.lintFix.rawValue,
                "d": KeyboardSwipeCommand.insertDate.rawValue,
            ],
            showNumberRow: false,
            punctuationStyle: .fullwidth,
            panguSpaceLetters: true,
            panguSpaceDigits: true,
            translateFormalTone: false,
            quickStripTokens: ["「」", "『』", "《》", "——", "……", "·", "✨", "🔥"]
        ),
        CustomKeyboardLayoutPack(
            id: "business",
            name: "商务办公",
            subtitle: "正式翻译口吻 + 盘古空格 + 日期/时间/润色/离线排版",
            icon: "briefcase.fill",
            swipeUpMap: [:],
            swipeDownMap: [
                "a": "【】", "s": "¥", "d": KeyboardSwipeCommand.insertDate.rawValue,
                "f": KeyboardSwipeCommand.insertTime.rawValue,
                "z": KeyboardSwipeCommand.undo.rawValue,
                "c": KeyboardSwipeCommand.aiPolish.rawValue,
                "v": KeyboardSwipeCommand.paste.rawValue,
                "b": KeyboardSwipeCommand.lintFix.rawValue,
                "t": KeyboardSwipeCommand.translate.rawValue,
            ],
            showNumberRow: true,
            punctuationStyle: .fullwidth,
            panguSpaceLetters: true,
            panguSpaceDigits: true,
            translateFormalTone: true,
            quickStripTokens: ["¥", "$", "%", "【】", "—", "·"]
        ),
    ]

    static func find(id: String) -> CustomKeyboardLayoutPack? {
        builtInPacks.first { $0.id == id }
    }
}
