import Foundation

/// 提示文案工具：去掉上游消息自带的 ✓ / ⚠️ 前缀，并按文案判断语气（成功 / 提示 / 失败）
enum LXToastText {
    enum Tone { case success, info, error }

    static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["✓", "✔︎", "✅", "⚠️", "⚠", "❌", "⚡"] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return s
    }

    static func tone(of raw: String) -> Tone {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 注意：Swift 按字形簇比较，"⚠️"（带 emoji 变体选择符）与 "⚠" 是两个不同字符，必须分别判断
        if ["⚠️", "⚠", "❌"].contains(where: { s.hasPrefix($0) }) { return .error }
        let errorWords = ["失败", "错误", "出错", "无法", "超时"]
        if errorWords.contains(where: { s.contains($0) }) { return .error }
        let infoWords = ["是空的", "已存在", "已在列表", "都已", "已全部开启", "没有", "无需"]
        if infoWords.contains(where: { s.contains($0) }) { return .info }
        return .success
    }
}
