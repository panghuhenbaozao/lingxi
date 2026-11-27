import Foundation

/// 链接净身与防账号追踪清理结果（0ms 纯离线执行）
public struct LinkCleanResult: Equatable, Sendable {
    public let originalText: String
    public let cleanedText: String
    public let extractedCleanURL: String?
    public let removedParams: [String]
    public let removedIdentityLeakParams: [String]
    public let strippedShareNoise: Bool

    public var hasChanges: Bool {
        !removedParams.isEmpty || strippedShareNoise || cleanedText != originalText
    }

    public var hasIdentityLeakRisk: Bool {
        !removedIdentityLeakParams.isEmpty
    }

    public var summaryBadge: String {
        if hasIdentityLeakRisk {
            return "已清除 \(removedParams.count) 项追踪（含 \(removedIdentityLeakParams.count) 项账号暴露标识）"
        }
        if !removedParams.isEmpty && strippedShareNoise {
            return "已清 \(removedParams.count) 项追踪并剥离分享口令"
        }
        if !removedParams.isEmpty {
            return "已清除 \(removedParams.count) 项追踪参数"
        }
        if strippedShareNoise {
            return "已提取纯净链接"
        }
        return "链接已很干净"
    }

    public init(
        originalText: String,
        cleanedText: String,
        extractedCleanURL: String?,
        removedParams: [String],
        removedIdentityLeakParams: [String],
        strippedShareNoise: Bool
    ) {
        self.originalText = originalText
        self.cleanedText = cleanedText
        self.extractedCleanURL = extractedCleanURL
        self.removedParams = removedParams
        self.removedIdentityLeakParams = removedIdentityLeakParams
        self.strippedShareNoise = strippedShareNoise
    }
}

/// 0ms 纯本地「分享链接去追踪 · 防社死净链器」。
/// 针对 B 站 / 小红书 / 抖音 / 淘宝 / 京东 / 知乎 / 微博 / 微信 / YouTube / X 等平台分享链接：
/// 1. 剥离会暴露转发者个人账号的标识参数（如 `appuid`、`vd_source`、`sec_uid`、`u_code`、`share_from`、`buvid`）；
/// 2. 清理 55+ 广告归因与追踪参数（`utm_*`、`spm*`、`fbclid`、`gclid`、`si`、`igsh`、`share_medium` 等）；
/// 3. 保留页面正常打开所必需的功能参数（如 `v`、`p`、`id`、`q`、`xsec_token`、`xsec_source`）；
/// 4. 支持一键去除「复制这段话打开 App…」等冗长分享口令噪声，只贴纯净链接。
public enum LinkPrivacyCleaner {

    /// 直接可能暴露转发者个人身份/账号的追踪参数（小写）
    private static let identityLeakParams: Set<String> = [
        "appuid", "vd_source", "sec_uid", "u_code", "share_from", "share_from_user_hidden",
        "share_session_id", "buvid", "mid", "up_id", "sharer_id", "share_uid",
        "invite_code", "inviter_id", "from_user", "uid_share", "suid",
    ]

    /// 通用广告归因与平台分享追踪参数（小写精确匹配）
    private static let trackingParamsExact: Set<String> = [
        "spm", "spm_id_from", "from_spmid", "apptime", "xhsshare", "share_source",
        "share_medium", "share_plat", "share_tag", "share_copy_link", "share_times",
        "share_token", "timestamp", "unique_k", "bbid", "ts", "is_story_h5",
        "fbclid", "gclid", "dclid", "yclid", "msclkid", "ttclid", "twclid",
        "mc_cid", "mc_eid", "si", "igsh", "igshid", "feature", "pp",
        "ref", "ref_src", "ref_url", "referrer", "s", "t",
        "chksm", "poc_token", "from_wecom", "scene", "subscene", "clicktime", "enterid",
        "source", "source_type", "from_source", "from_s", "p_id", "track_id", "trackid",
        "ad_id", "campaign_id", "click_id", "union_lens", "bxsign", "ut_sk", "sm",
        "un", "share_crt_v", "sp_tk", "bc_fl_src", "cpp", "shareurl", "short_name",
        "app", "wxsign", "tk", "price", "suid", "un_site", "cu", "utm_source",
        "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id", "utm_name",
        "vd_source", "appuid", "sec_uid", "u_code", "share_from", "share_from_user_hidden",
        "share_session_id", "buvid", "mid", "up_id", "sharer_id", "share_uid",
    ]

    private static let trackingParamPrefixes: [String] = [
        "utm_", "spm_", "share_", "track_", "ga_", "fb_", "_hs", "oly_", "vero_", "mkt_",
    ]

    private static let urlRegex = try? NSRegularExpression(
        pattern: #"https?://[^\s<>\"'「」【】（）()，,。；;]+"#,
        options: [.caseInsensitive]
    )

    private static let shareNoiseHints: [String] = [
        "复制这段", "复制此消息", "复制本段", "打开淘宝", "打开抖音", "打开小红书", "打开哔哩哔哩",
        "打开京东", "长按复制", "快来抢购", "点击链接直接打开", "口令", "￥", "€", "fu致", "復制",
    ]

    /// 检测并净化文本中的链接（可保留正文中的其他内容，同时提取纯净主链接）
    public static func clean(_ rawText: String) -> LinkCleanResult {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let regex = urlRegex else {
            return LinkCleanResult(
                originalText: rawText,
                cleanedText: rawText,
                extractedCleanURL: nil,
                removedParams: [],
                removedIdentityLeakParams: [],
                strippedShareNoise: false
            )
        }

        let nsText = trimmed as NSString
        let matches = regex.matches(in: trimmed, options: [], range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else {
            return LinkCleanResult(
                originalText: rawText,
                cleanedText: rawText,
                extractedCleanURL: nil,
                removedParams: [],
                removedIdentityLeakParams: [],
                strippedShareNoise: false
            )
        }

        var allRemoved: [String] = []
        var allIdentityRemoved: [String] = []
        var firstCleanURL: String?
        let mutable = NSMutableString(string: trimmed)

        for match in matches.reversed() {
            let rawURLString = nsText.substring(with: match.range)
            let (cleanedURL, removed, idRemoved) = cleanSingleURL(rawURLString)
            if firstCleanURL == nil {
                firstCleanURL = cleanedURL
            } else {
                // reverse loop: update so first match wins at end
                firstCleanURL = cleanedURL
            }
            allRemoved.insert(contentsOf: removed, at: 0)
            allIdentityRemoved.insert(contentsOf: idRemoved, at: 0)
            mutable.replaceCharacters(in: match.range, with: cleanedURL)
        }

        let replacedText = mutable as String
        let looksLikeShareBoilerplate = matches.count == 1
            && firstCleanURL != nil
            && replacedText.count > (firstCleanURL?.count ?? 0) + 6
            && (shareNoiseHints.contains(where: { trimmed.contains($0) }) || trimmed.contains("【") && trimmed.contains("】"))

        let finalCleaned = looksLikeShareBoilerplate ? (firstCleanURL ?? replacedText) : replacedText

        return LinkCleanResult(
            originalText: rawText,
            cleanedText: finalCleaned,
            extractedCleanURL: firstCleanURL,
            removedParams: deduplicated(allRemoved),
            removedIdentityLeakParams: deduplicated(allIdentityRemoved),
            strippedShareNoise: looksLikeShareBoilerplate
        )
    }

    /// 便捷方法：仅提取并净化文本里的首个 URL（无 URL 返回 nil）
    public static func extractCleanURL(from text: String) -> String? {
        clean(text).extractedCleanURL
    }

    /// 净化单个 URL 的查询参数与多余末尾斜杠/问号
    private static func cleanSingleURL(_ rawURL: String) -> (cleaned: String, removed: [String], identityRemoved: [String]) {
        guard var comps = URLComponents(string: rawURL),
              let host = comps.host?.lowercased(), !host.isEmpty else {
            return (rawURL, [], [])
        }

        var removed: [String] = []
        var identityRemoved: [String] = []

        if let queryItems = comps.queryItems, !queryItems.isEmpty {
            var kept: [URLQueryItem] = []
            for item in queryItems {
                let lowerName = item.name.lowercased()
                if shouldStripParam(lowerName, host: host) {
                    removed.append(item.name)
                    if identityLeakParams.contains(lowerName) {
                        identityRemoved.append(item.name)
                    }
                } else {
                    kept.append(item)
                }
            }
            comps.queryItems = kept.isEmpty ? nil : kept
        }

        // B 站 / 知乎等纯空 fragment 清理
        if let frag = comps.fragment, frag.isEmpty {
            comps.fragment = nil
        }

        let out = comps.url?.absoluteString ?? rawURL
        return (out, removed, identityRemoved)
    }

    private static func shouldStripParam(_ lowerName: String, host: String) -> Bool {
        // 保护小红书正常打开所需的 xsec_token / xsec_source，不误删
        if host.contains("xiaohongshu.com") && (lowerName == "xsec_token" || lowerName == "xsec_source") {
            return false
        }
        // 保护 YouTube 播放时间戳 `t` 与视频 ID `v`
        if (host.contains("youtube.com") || host.contains("youtu.be")) && (lowerName == "v" || lowerName == "t" || lowerName == "list") {
            return false
        }
        // 保护 B 站分 P 参数 `p` 与跳转时间戳 `t`
        if host.contains("bilibili.com") && (lowerName == "p" || lowerName == "t") {
            return false
        }
        // 保护微信文章必需参数（__biz / mid / idx / sn），但清 chksm / scene / poc_token
        if host.contains("mp.weixin.qq.com") && ["__biz", "mid", "idx", "sn"].contains(lowerName) {
            return false
        }

        if identityLeakParams.contains(lowerName) { return true }
        if trackingParamsExact.contains(lowerName) { return true }
        return trackingParamPrefixes.contains { lowerName.hasPrefix($0) }
    }

    private static func deduplicated(_ list: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in list where seen.insert(item.lowercased()).inserted {
            out.append(item)
        }
        return out
    }
}
