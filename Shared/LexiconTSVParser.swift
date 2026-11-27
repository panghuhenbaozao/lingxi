import Foundation

/// 导入 TSV 的纯逻辑（预览计数与导入用同一套规则，保证「预览 N 条」与实际导入一致）
enum LexiconTSVParser {
    /// 手机上很难输入 Tab：把「编码,内容」「编码，内容」「编码=内容」也转换成 Tab 分隔
    static func normalize(_ text: String) -> String {
        text.components(separatedBy: .newlines).map { raw -> String in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.contains("\t") else { return raw }
            for sep in [",", "，", "="] {
                if let r = line.range(of: sep) {
                    let head = line[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
                    let tail = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
                    let headOK = !head.isEmpty && head.allSatisfy { ($0.isASCII && $0.isLetter) || $0 == " " || $0 == "'" || $0 == "ü" }
                    if headOK && !tail.isEmpty {
                        return "\(head)\t\(tail)"
                    }
                }
            }
            return raw
        }
        .joined(separator: "\n")
    }

    private static func dataLines(_ text: String) -> [[String]] {
        normalize(text)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    }

    /// 与 `CustomWordStore.importTSV` 规则一致：编码只能是英文字母（可含空格），内容非空
    static func validCustomCount(_ text: String) -> Int {
        dataLines(text).filter { cols in
            guard cols.count >= 2 else { return false }
            let compact = cols[0].lowercased().replacingOccurrences(of: " ", with: "")
            return !compact.isEmpty && compact.allSatisfy { $0.isASCII && $0.isLetter } && !cols[1].isEmpty
        }.count
    }

    /// 与 `UserLexicon.importTSV` 规则一致：拼音 1~8 个音节，词条非空
    static func validUserCount(_ text: String) -> Int {
        dataLines(text).filter { cols in
            let trimmed = cols.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard trimmed.count >= 2 else { return false }
            let syllables = trimmed[0].lowercased().split(whereSeparator: { $0 == " " || $0 == "'" })
            return !syllables.isEmpty && syllables.count <= 8
        }.count
    }

    /// 自定义短语编码：只能是英文字母（允许空格、撇号分隔音节）
    static func isValidCode(_ code: String) -> Bool {
        let compact = code.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "'", with: "")
        return !compact.isEmpty && compact.allSatisfy { $0.isASCII && $0.isLetter }
    }
}
