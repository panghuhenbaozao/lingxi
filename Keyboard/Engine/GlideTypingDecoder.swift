import CoreGraphics
import Foundation

/// 26 键中英文滑行输入（Glide / Swipe Typing）几何轨迹与语言模型联合解码器（Shark2 / Gboard 算法架构）。
///
/// 工作流水线：
/// 1. 将手指触摸序列按弧长重采样为 `N = 24` 个等距点，并映射到标准键宽归一化坐标系；
/// 2. 提取起点与终点半径 `1.45` 键距内的最多 4 个候选首尾字母键，通过 `PinyinEngine.fetchGlidePool` 在 `< 0.5ms` 内取出高频词桶；
/// 3. 对每个候选词的折叠键位折线（`hello` -> `h-e-l-o`）做快速走廊过滤与 `N = 24` 等距模板对齐；
/// 4. 综合空间均方欧氏距离、首尾落点误差、弧长比惩罚与语言模型对数概率 `lp` 排序输出。
enum GlideTypingDecoder {
    private static let sampleCount = 24

    /// 标准 QWERTY 26 键归一化坐标（列间距 = 1.0，行间距 = 1.0）。
    static let standardKeyPositions: [Character: CGPoint] = {
        var map: [Character: CGPoint] = [:]
        for (i, ch) in "qwertyuiop".enumerated() {
            map[ch] = CGPoint(x: CGFloat(i), y: 0.0)
        }
        for (i, ch) in "asdfghjkl".enumerated() {
            map[ch] = CGPoint(x: 0.5 + CGFloat(i), y: 1.0)
        }
        for (i, ch) in "zxcvbnm".enumerated() {
            map[ch] = CGPoint(x: 1.5 + CGFloat(i), y: 2.0)
        }
        return map
    }()

    /// 将真实画布上的触摸轨迹与按键中心坐标一起解码为排序后的滑行候选词。
    static func decodeTouchPath(
        touchPoints: [CGPoint],
        keyCenters: [Character: CGPoint],
        keyPitch: CGFloat,
        engine: PinyinEngine,
        isEnglish: Bool,
        limit: Int = 12
    ) -> [PinyinCandidate] {
        guard touchPoints.count >= 2, keyPitch > 10 else { return [] }
        let qOrigin = keyCenters["q"] ?? .zero
        let normalizedTouch = touchPoints.map { pt in
            CGPoint(x: (pt.x - qOrigin.x) / keyPitch, y: (pt.y - qOrigin.y) / keyPitch)
        }
        var normalizedKeys: [Character: CGPoint] = [:]
        for (k, pt) in keyCenters {
            normalizedKeys[k] = CGPoint(x: (pt.x - qOrigin.x) / keyPitch, y: (pt.y - qOrigin.y) / keyPitch)
        }
        return decodeNormalized(
            points: normalizedTouch,
            keyMap: normalizedKeys.count >= 20 ? normalizedKeys : standardKeyPositions,
            engine: engine,
            isEnglish: isEnglish,
            limit: limit
        )
    }

    /// 在归一化键位坐标系下解码滑行轨迹（亦可直接用于单元测试）。
    static func decodeNormalized(
        points: [CGPoint],
        keyMap: [Character: CGPoint] = standardKeyPositions,
        engine: PinyinEngine,
        isEnglish: Bool,
        limit: Int = 12
    ) -> [PinyinCandidate] {
        guard points.count >= 2 else { return [] }
        let (userPts, userLen) = resamplePolyline(points, count: sampleCount)
        guard userLen >= 0.75 else { return [] }

        let pStart = points.first!
        let pEnd = points.last!

        let startKeys = keyMap
            .map { ($0.key, hypot($0.value.x - pStart.x, $0.value.y - pStart.y)) }
            .filter { $0.1 <= 1.45 }
            .sorted { $0.1 < $1.1 }
            .prefix(4)
            .map(\.0)

        let endKeys = keyMap
            .map { ($0.key, hypot($0.value.x - pEnd.x, $0.value.y - pEnd.y)) }
            .filter { $0.1 <= 1.45 }
            .sorted { $0.1 < $1.1 }
            .prefix(4)
            .map(\.0)

        guard !startKeys.isEmpty, !endKeys.isEmpty else { return [] }

        let rawPool = engine.fetchGlidePool(startKeys: startKeys, endKeys: endKeys, isEnglish: isEnglish)
        guard !rawPool.isEmpty else { return [] }

        var scored: [(score: Double, word: String, py: String)] = []
        var seenWords = Set<String>()

        for item in rawPool {
            guard seenWords.insert(item.word).inserted else { continue }
            let keyPoly = wordKeyPolyline(for: item.pyFlat, keyMap: keyMap)
            guard keyPoly.count >= 2 else { continue }

            // 快速几何走廊过滤：每个理想转折键离滑行轨迹最近距离不超过 1.45 个键宽
            var corridorOK = true
            for kp in keyPoly {
                var minD = CGFloat.infinity
                for up in userPts {
                    let d = hypot(kp.x - up.x, kp.y - up.y)
                    if d < minD { minD = d }
                }
                if minD > 1.45 {
                    corridorOK = false
                    break
                }
            }
            if !corridorOK { continue }

            let (tmplPts, tmplLen) = resamplePolyline(keyPoly, count: sampleCount)
            var spatialSum: CGFloat = 0
            for idx in 0..<sampleCount {
                spatialSum += hypot(userPts[idx].x - tmplPts[idx].x, userPts[idx].y - tmplPts[idx].y)
            }
            let spatial = Double(spatialSum) / Double(sampleCount)
            let sDist = Double(hypot(pStart.x - keyPoly.first!.x, pStart.y - keyPoly.first!.y))
            let eDist = Double(hypot(pEnd.x - keyPoly.last!.x, pEnd.y - keyPoly.last!.y))
            let lenPen = Double(abs(userLen - tmplLen) / max(1.5, tmplLen)) * 0.45
            let geoCost = spatial * 4.2 + (sDist + eDist) * 1.5 + lenPen
            let totalScore = item.lp * 0.50 - geoCost
            scored.append((totalScore, item.word, item.py))
        }

        scored.sort { $0.score > $1.score }
        return scored.prefix(limit).map { entry in
            PinyinCandidate(
                word: entry.word,
                py: entry.py,
                lp: entry.score,
                consumed: 0,
                isExact: true,
                source: isEnglish ? .englishDirect : .dictionary
            )
        }
    }

    static func wordKeyPolyline(
        for letters: String,
        keyMap: [Character: CGPoint] = standardKeyPositions
    ) -> [CGPoint] {
        var dedup: [Character] = []
        for ch in letters.lowercased() where keyMap[ch] != nil {
            if dedup.last != ch {
                dedup.append(ch)
            }
        }
        return dedup.compactMap { keyMap[$0] }
    }

    static func resamplePolyline(_ pts: [CGPoint], count: Int = 24) -> (points: [CGPoint], length: CGFloat) {
        guard let first = pts.first else {
            return (Array(repeating: .zero, count: count), 0)
        }
        var clean: [CGPoint] = [first]
        for p in pts.dropFirst() {
            if hypot(p.x - clean.last!.x, p.y - clean.last!.y) > 1e-4 {
                clean.append(p)
            }
        }
        guard clean.count >= 2 else {
            return (Array(repeating: first, count: count), 0)
        }
        var cum: [CGFloat] = [0]
        for i in 1..<clean.count {
            let d = hypot(clean[i].x - clean[i - 1].x, clean[i].y - clean[i - 1].y)
            cum.append(cum.last! + d)
        }
        let total = cum.last!
        guard total > 1e-4 else {
            return (Array(repeating: first, count: count), 0)
        }

        var out: [CGPoint] = []
        out.reserveCapacity(count)
        var segIdx = 0
        for k in 0..<count {
            let target = (total * CGFloat(k)) / CGFloat(max(1, count - 1))
            while segIdx + 1 < cum.count - 1 && cum[segIdx + 1] < target {
                segIdx += 1
            }
            let segLen = max(1e-6, cum[segIdx + 1] - cum[segIdx])
            let t = (target - cum[segIdx]) / segLen
            let x = clean[segIdx].x + t * (clean[segIdx + 1].x - clean[segIdx].x)
            let y = clean[segIdx].y + t * (clean[segIdx + 1].y - clean[segIdx].y)
            out.append(CGPoint(x: x, y: y))
        }
        return (out, total)
    }
}
