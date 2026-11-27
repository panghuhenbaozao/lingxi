import Foundation

/// 端侧 0ms 口述文本清洗报告（对标豆包输入法 / Wispr Flow 的本地语音去口水与口误回撤引擎）
struct VoiceCleanReport: Equatable {
    let original: String
    let cleaned: String
    let removedFillersCount: Int
    let selfCorrectionsCount: Int
    let stuttersCollapsedCount: Int

    var hasChanges: Bool { cleaned != original }

    var summaryBadge: String {
        var parts: [String] = []
        if selfCorrectionsCount > 0 { parts.append("修正口误 \(selfCorrectionsCount) 处") }
        if removedFillersCount > 0 { parts.append("去口水词 \(removedFillersCount) 处") }
        if stuttersCollapsedCount > 0 { parts.append("合并叠词 \(stuttersCollapsedCount) 处") }
        if parts.isEmpty {
            return hasChanges ? "已完成标点与盘古排版" : "口述文本已很干净"
        }
        return parts.joined(separator: " · ")
    }
}

/// 100% 离线零延迟语音口述智能清洗引擎（0 网络 / 0 Token / App 与键盘扩展共用）：
/// 1. 口误回撤自动修正（「明天下午三点哦不对四点开会」→「明天下午四点开会」、「预算五万说错了八万」→「预算八万」）；
/// 2. 语境安全去口水词（剥离句首/停顿处的「嗯嗯」「呃」「啊那个」「就是说」「然后的话」「怎么说呢」，保护「那个项目」「就是这个」等实义短语）；
/// 3. 结巴叠词合并（「我我我觉得」→「我觉得」、「就是就是」→「就是」）；
/// 4. 串联 `OfflineTextLinter.autoFix` 完成中英文标点与盘古空格整理。
enum VoiceTranscriptCleaner {
    static func clean(_ raw: String) -> VoiceCleanReport {
        let original = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else {
            return VoiceCleanReport(
                original: raw,
                cleaned: "",
                removedFillersCount: 0,
                selfCorrectionsCount: 0,
                stuttersCollapsedCount: 0
            )
        }

        var text = original
        var selfCorrections = 0
        var removedFillers = 0
        var stutters = 0

        // 1. 口误回撤自动修正（Self-Correction Collapse）
        // 1a. 精准数值/时刻/数量口误回撤：如「下午三点哦不对四点开会」「预算5万说错了8万」「周三不对周四」
        let numericBacktrackPatterns: [String] = [
            #"(?:[零一二两三四五六七八九十百千万\d]+(?:\.\d+)?(?:点半?|点钟|分|秒|号|日|月|年|个|次|万|千|块|元|小时|分钟|天|周|%|折)?)\s*[，,、]?\s*(?:哦|啊|哎)?\s*(?:不对|说错了|讲错了|口误|不是不是|打错了)\s*[，,、]?\s*(?:应该是|是|改成|改为)?\s*(?=[零一二两三四五六七八九十百千万\d])"#,
            #"(?:周|星期|礼拜)[一二三四五六日天末]\s*[，,、]?\s*(?:哦|啊)?\s*(?:不对|说错了|不是)\s*[，,、]?\s*(?:是|改成)?\s*(?=(?:周|星期|礼拜)[一二三四五六日天末])"#,
        ]
        for pat in numericBacktrackPatterns {
            let (next, hits) = replacing(text, pattern: pat, with: "")
            text = next
            selfCorrections += hits
        }

        // 1b. 短语/称谓口误回撤：如「发给老王不对发给老李」「买苹果说错了买香蕉」
        let generalBacktrackPat = #"([A-Za-z0-9\u4E00-\u9FFF]{1,8})\s*[，,、]?\s*(?:哦|啊|哎)?\s*(?:不对|说错了|讲错了|口误)\s*[，,、]?\s*(?:应该是|改成|改为|是)?"#
        if let regex = try? NSRegularExpression(pattern: generalBacktrackPat) {
            var guardRounds = 0
            while guardRounds < 6 {
                guardRounds += 1
                let ns = text as NSString
                guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { break }
                // 仅当回撤标记后仍有后续修正内容时才执行折叠，避免误删句尾正常的「我觉得不对」
                let afterLoc = m.range.location + m.range.length
                let remaining = afterLoc < ns.length ? ns.substring(from: afterLoc).trimmingCharacters(in: .whitespacesAndNewlines) : ""
                guard !remaining.isEmpty,
                      let firstAfter = remaining.first,
                      !"。！？!?；;".contains(firstAfter) else {
                    break
                }
                let retracted = ns.substring(with: m.range(at: 1))
                // 若被回撤短语以常见完整主谓前缀开头且较长，仅截掉最后 2-4 字避免吞掉主语（如「明天发给老王不对老李」保留「明天发给」）
                let keptPrefix: String
                if retracted.count >= 5 {
                    let dropCount = min(3, max(2, remaining.prefix(3).count))
                    keptPrefix = String(retracted.dropLast(dropCount))
                } else {
                    keptPrefix = ""
                }
                text = ns.replacingCharacters(in: m.range, with: keptPrefix)
                selfCorrections += 1
            }
        }

        // 1c. 英文口误回撤：`at 3pm wait no 4pm` / `send to Bob, actually no, Alice`
        let enBacktrackPat = #"\b[A-Za-z0-9:$%.]{1,14}\s*,?\s*(?:wait no|actually no|sorry no|i mean)\s*,?\s*"#
        let (afterEnBack, enHits) = replacing(text, pattern: enBacktrackPat, with: "", options: [.caseInsensitive])
        text = afterEnBack
        selfCorrections += enHits

        // 2. 结巴与口语重复叠词合并（Stutter Collapse）
        // 2a. 单字 3 连及以上结巴（如「我我我觉得」→「我觉得」，跳过「哈哈哈」「呵呵呵」「666」「...」）
        let tripleStutterPat = #"([\u4E00-\u9FFF])\1{2,}"#
        if let regex = try? NSRegularExpression(pattern: tripleStutterPat) {
            let ns = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            if !matches.isEmpty {
                var rebuilt = ""
                var cursor = 0
                for m in matches {
                    let ch = ns.substring(with: m.range(at: 1))
                    rebuilt += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                    if "哈呵嘿嘻呜哇哦呀".contains(ch) {
                        rebuilt += ns.substring(with: m.range)
                    } else {
                        rebuilt += ch
                        stutters += 1
                    }
                    cursor = m.range.location + m.range.length
                }
                rebuilt += ns.substring(from: cursor)
                text = rebuilt
            }
        }

        // 2b. 高频口语双字卡顿重复（如「就是就是」「然后然后」「那个那个」「这个这个」「其实其实」「因为因为」「所以所以」「我们我们」）
        let doubleStutterPat = #"(就是|然后|那个|这个|其实|因为|所以|我们|你们|他们|我觉得|就是说|可以|应该|需要)\s*[，,、]?\s*\1"#
        let (afterDouble, doubleHits) = replacing(text, pattern: doubleStutterPat, with: "$1")
        text = afterDouble
        stutters += doubleHits

        // 3. 语境安全去口水词（Filler Removal）
        // 3a. 句首与标点后的独立语气垫词（绝不误伤句子中间的实义词）
        let boundaryFillers: [String] = [
            #"(?:^|(?<=[，。！？；、,;!?\n]))\s*(?:嗯+|呃+|额+|啊+|诶+|唉+|哦+)\s*[，,、]?"#,
            #"(?:^|(?<=[，。！？；、,;!?\n]))\s*(?:就是说|然后的话|怎么说呢|那个什么|那个啥|啊那个|嗯那个|呃那个|其实的话|反正就是)\s*[，,、]?"#,
            #"(?:^|(?<=[，。！？；、,;!?\n]))\s*(?:那个|这个)\s*[，,、]\s*(?=(?:我们|我|你|他|她|它|大家|明天|今天|现在|帮|请|麻烦|先|把))"#,
            #"\b(?:uh+|um+|erm+|you know|like),?\s+"#,
        ]
        for pat in boundaryFillers {
            let (next, hits) = replacing(text, pattern: pat, with: "", options: [.caseInsensitive])
            text = next
            removedFillers += hits
        }

        // 3b. 句中明显拖沓口头禅短语
        let midFillers = #"[，,、]?\s*(?:就是说呢|怎么说呢|那个啥|呃就是|嗯就是|然后呢的话)\s*[，,、]?"#
        let (afterMid, midHits) = replacing(text, pattern: midFillers, with: "，")
        text = afterMid
        removedFillers += midHits

        // 4. 清理残余首尾多余标点与连续重复标点，并串联离线盘古排版
        let (noLeadPunct, _) = replacing(text, pattern: #"^[\s，,、；;：:]+"#, with: "")
        let (collapsedPunct, _) = replacing(noLeadPunct, pattern: #"([，,、。；;])\s*[，,、；;]+"#, with: "$1")
        let finalText = OfflineTextLinter.autoFix(collapsedPunct).trimmingCharacters(in: .whitespacesAndNewlines)

        return VoiceCleanReport(
            original: original,
            cleaned: finalText.isEmpty ? original : finalText,
            removedFillersCount: removedFillers,
            selfCorrectionsCount: selfCorrections,
            stuttersCollapsedCount: stutters
        )
    }

    private static func replacing(
        _ input: String,
        pattern: String,
        with template: String,
        options: NSRegularExpression.Options = []
    ) -> (String, Int) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return (input, 0)
        }
        let range = NSRange(location: 0, length: (input as NSString).length)
        let count = regex.numberOfMatches(in: input, range: range)
        guard count > 0 else { return (input, 0) }
        let out = regex.stringByReplacingMatches(in: input, range: range, withTemplate: template)
        return (out, count)
    }
}
