import Foundation

/// 仓输入法 (Hamster) 风格「按键划动动作命令协议」：
/// 允许用户在任意 26 键的上滑/下划映射中，既可填写普通符号/短语（如 `@`、`()`），
/// 也可绑定 `#命令` 执行原生输入法与 AI 动作（以词定字、粘贴、撤销、光标微调、简繁/中英切换、一键润色等）。
enum KeyboardSwipeCommand: String, CaseIterable, Identifiable, Equatable {
    case firstChar = "#firstChar"
    case lastChar = "#lastChar"
    case paste = "#paste"
    case undo = "#undo"
    case clear = "#clear"
    case cursorLeft = "#cursorLeft"
    case cursorRight = "#cursorRight"
    case toggleLang = "#toggleLang"
    case toggleTrad = "#toggleTrad"
    case aiPanel = "#aiPanel"
    case aiPolish = "#aiPolish"
    case aiThreeVariants = "#ai3v"
    case lintFix = "#lintFix"
    case translate = "#translate"
    case insertDate = "#date"
    case insertTime = "#time"
    case newline = "#newline"
    case toggleIncognito = "#incognito"

    var id: String { rawValue }

    /// 键帽角落微型提示文字（严格控制在 1–2 个字符，绝不撑破 26 键键帽布局）
    var keycapBadge: String {
        switch self {
        case .firstChar: return "首"
        case .lastChar: return "尾"
        case .paste: return "贴"
        case .undo: return "撤"
        case .clear: return "清"
        case .cursorLeft: return "←"
        case .cursorRight: return "→"
        case .toggleLang: return "英"
        case .toggleTrad: return "繁"
        case .aiPanel: return "AI"
        case .aiPolish: return "润"
        case .aiThreeVariants: return "三"
        case .lintFix: return "检"
        case .translate: return "译"
        case .insertDate: return "日"
        case .insertTime: return "时"
        case .newline: return "↵"
        case .toggleIncognito: return "隐"
        }
    }

    var displayTitle: String {
        switch self {
        case .firstChar: return "以词定字·首字"
        case .lastChar: return "以词定字·尾字"
        case .paste: return "隐私粘贴"
        case .undo: return "撤销"
        case .clear: return "清空拼写/删词"
        case .cursorLeft: return "光标左移"
        case .cursorRight: return "光标右移"
        case .toggleLang: return "中英切换"
        case .toggleTrad: return "简繁切换"
        case .aiPanel: return "唤起 AI 面板"
        case .aiPolish: return "一键 AI 润色"
        case .aiThreeVariants: return "一键生成三版"
        case .lintFix: return "离线体检排版"
        case .translate: return "边打边译"
        case .insertDate: return "插入今日日期"
        case .insertTime: return "插入当前时间"
        case .newline: return "插入换行"
        case .toggleIncognito: return "隐身无痕模式"
        }
    }

    var shortDescription: String {
        switch self {
        case .firstChar: return "拼写时直接取首位候选词第一个字上屏（Rime 经典）"
        case .lastChar: return "拼写时直接取首位候选词最后一个字上屏（Rime 经典）"
        case .paste: return "经隐私护盾过滤后一键粘贴剪贴板"
        case .undo: return "恢复刚刚误删或误操作的内容"
        case .clear: return "拼写时清空全串，空闲时撤删前词"
        case .cursorLeft: return "光标向左移动 1 位"
        case .cursorRight: return "光标向右移动 1 位"
        case .toggleLang: return "即时切换中文与英文键盘"
        case .toggleTrad: return "即时切换简体中文与繁體中文"
        case .aiPanel: return "直接展开键盘内嵌灵犀 AI 面板"
        case .aiPolish: return "对光标前内容直接触发 AI 润色"
        case .aiThreeVariants: return "对光标前内容并发生成 3 种语气"
        case .lintFix: return "0 延迟离线修正重复字、混用标点与盘古空格（无需联网）"
        case .translate: return "开启或关闭键盘实时边打边译"
        case .insertDate: return "插入 YYYY-MM-DD 今日日期"
        case .insertTime: return "插入 HH:mm 当前时间"
        case .newline: return "向输入框插入换行符"
        case .toggleIncognito: return "暂停词库自学习、剪贴板历史、打字统计与 AI 留痕，零痕迹输入"
        }
    }

    /// 大小写不敏感解析 `#命令`；普通符号/文字返回 `nil`
    static func parse(_ raw: String) -> KeyboardSwipeCommand? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return nil }
        let lower = trimmed.lowercased()
        return Self.allCases.first { $0.rawValue.lowercased() == lower }
    }

    /// 将映射值转换为键帽上实际展示的紧凑文本（普通字符保持原样，命令显示简短角标）
    static func keycapBadge(for mappedValue: String) -> String {
        if let cmd = parse(mappedValue) {
            return cmd.keycapBadge
        }
        return mappedValue
    }

    /// 仓输入法效率命令预设（上划：j 取首字 / k 取尾字；下划：z 撤销 / x 清空 / c AI润色 / v 粘贴 / h/l 光标 / t 翻译 / f 简繁）
    static let hamsterEfficiencyUpPreset: [String: String] = [
        "j": KeyboardSwipeCommand.firstChar.rawValue,
        "k": KeyboardSwipeCommand.lastChar.rawValue,
    ]

    static let hamsterEfficiencyDownPreset: [String: String] = [
        "z": KeyboardSwipeCommand.undo.rawValue,
        "x": KeyboardSwipeCommand.clear.rawValue,
        "c": KeyboardSwipeCommand.aiPolish.rawValue,
        "v": KeyboardSwipeCommand.paste.rawValue,
        "b": KeyboardSwipeCommand.aiThreeVariants.rawValue,
        "h": KeyboardSwipeCommand.cursorLeft.rawValue,
        "l": KeyboardSwipeCommand.cursorRight.rawValue,
        "t": KeyboardSwipeCommand.translate.rawValue,
        "f": KeyboardSwipeCommand.toggleTrad.rawValue,
    ]
}
