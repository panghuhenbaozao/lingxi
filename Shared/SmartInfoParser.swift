import Foundation

/// 万能结构化信息类型（0ms 纯离线解析，用于剪贴板单字段速填）
public enum SmartInfoKind: String, Sendable, Equatable {
    case shippingAddress = "收件地址"
    case corporateInvoice = "开票信息"
    case meetingSchedule = "会议日程"

    public var badgeLabel: String {
        switch self {
        case .shippingAddress: return "📦 收件"
        case .corporateInvoice: return "🧾 开票"
        case .meetingSchedule: return "📅 会议"
        }
    }
}

/// 拆解后的单个可一键填写的字段
public struct SmartInfoField: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let value: String

    public init(id: String, label: String, value: String) {
        self.id = id
        self.label = label
        self.value = value
    }
}

/// 万能结构化信息拆解结果
public struct SmartInfoParseResult: Equatable, Sendable {
    public let kind: SmartInfoKind
    public let title: String
    public let fields: [SmartInfoField]

    public var formattedSummary: String {
        fields.map { "\($0.label)：\($0.value)" }.joined(separator: "\n")
    }

    public init(kind: SmartInfoKind, title: String, fields: [SmartInfoField]) {
        self.kind = kind
        self.title = title
        self.fields = fields
    }
}

/// 0ms 纯本地「万能收件地址 / 企业开票抬头 / 会议日程」结构化拆解引擎。
/// 解决手机填表痛点：从微信复制一整段「张三 13812345678 山东省临沂市...」或开票信息后，
/// 在键盘剪贴板里直接分字段一键点填（填姓名 / 填手机 / 填地址 / 填抬头 / 填税号 / 填开户行 / 填账号），
/// 彻底告别来回复制粘贴删改！
public enum SmartInfoParser {

    // MARK: - Compiled Regexes (ICU-safe, zero \u{...} in raw strings)

    private static let labeledTaxIdRegex = try? NSRegularExpression(
        pattern: #"(?:纳税人识别号|统一社会信用代码|信用代码|税号|税籍号)[:：\s]*([0-9A-Za-z]{15,20})"#
    )
    private static let standaloneCreditCodeRegex = try? NSRegularExpression(
        pattern: #"(?<![0-9A-Za-z])(9[123][0-9A-HJ-NPQRTUWXY]{16})(?![0-9A-Za-z])"#
    )
    private static let labeledCompanyRegex = try? NSRegularExpression(
        pattern: #"(?:公司名称|单位名称|企业名称|开票抬头|发票抬头|抬头|名称)[:：\s]*([^\n\r，,；;]{3,50})"#
    )
    private static let companySuffixRegex = try? NSRegularExpression(
        pattern: #"([\u4E00-\u9FA5A-Za-z0-9（）()]{2,40}(?:有限责任公司|股份有限公司|有限公司|工作室|事务所|研究院|医院|大学|中心))"#
    )
    private static let labeledBankNameRegex = try? NSRegularExpression(
        pattern: #"(?:开户银行|开户行|银行名称)[:：\s]*([^\n\r，,；;]{4,45})"#
    )
    private static let standaloneBankNameRegex = try? NSRegularExpression(
        pattern: #"([\u4E00-\u9FA5]{2,20}银行[\u4E00-\u9FA50-9（）()]{0,20}(?:支行|分行|营业部))"#
    )
    private static let labeledBankAccountRegex = try? NSRegularExpression(
        pattern: #"(?:银行账号|开户账号|对公账号|账号)[:：\s]*([0-9 \-]{12,26})"#
    )
    private static let standaloneBankAccountRegex = try? NSRegularExpression(
        pattern: #"(?<!\d)(\d{16,22})(?!\d)"#
    )

    private static let phoneRegex = try? NSRegularExpression(
        pattern: #"(?<!\d)(1[3-9]\d[\s\-]?\d{4}[\s\-]?\d{4})(?!\d)"#
    )
    private static let labeledNameRegex = try? NSRegularExpression(
        pattern: #"(?:收件人|收货人|联系人|姓名)[:：\s]*([\u4E00-\u9FA5A-Za-z·]{2,12})"#
    )
    private static let labeledAddressRegex = try? NSRegularExpression(
        pattern: #"(?:收货地址|收件地址|详细地址|寄送地址|地址)[:：\s]*([^\n\r]{6,120})"#
    )
    private static let addressIndicatorRegex = try? NSRegularExpression(
        pattern: #"(?:北京|上海|天津|重庆|河北|山西|辽宁|吉林|黑龙江|江苏|浙江|安徽|福建|江西|山东|河南|湖北|湖南|广东|海南|四川|贵州|云南|陕西|甘肃|青海|台湾|内蒙古|广西|西藏|宁夏|新疆|香港|澳门|省|市|自治区|区|县|镇|街道|大道|路|街|巷|小区|花园|大厦|广场|栋|幢|单元|室|号)"#
    )

    private static let meetingIdRegex = try? NSRegularExpression(
        pattern: #"(?:会议号|房间号|腾讯会议|入会号|Meeting\s*ID|ID)[:：\s#]*([0-9][0-9\- ]{7,15}[0-9])"#,
        options: [.caseInsensitive]
    )
    private static let meetingPasscodeRegex = try? NSRegularExpression(
        pattern: #"(?:入会密码|会议密码|密码)[:：\s]*([A-Za-z0-9]{4,12})"#
    )
    private static let meetingTimeRegex = try? NSRegularExpression(
        pattern: #"((?:\d{4}[-/\.]\d{1,2}[-/\.]\d{1,2}|\d{1,2}月\d{1,2}[日号]|今天|明天|后天|下?周[一二三四五六日天]|星期[一二三四五六日天])(?:\s*(?:上午|下午|晚上|中午)?\s*\d{1,2}[:：点时]\d{0,2}(?:\s*[-~至到]\s*\d{1,2}[:：点时]\d{0,2})?)?)"#
    )
    private static let meetingLocationRegex = try? NSRegularExpression(
        pattern: #"(?:会议室|地点|位置)[:：\s]*([^\n\r，,。；;]{2,40})"#
    )

    private static let nameStopWords: Set<String> = [
        "收件人", "收货人", "联系人", "姓名", "电话", "手机", "手机号", "地址", "收货地址", "收件地址",
        "详细地址", "快递", "邮寄", "麻烦", "你好", "请寄", "发货", "公司", "开票", "抬头", "税号"
    ]

    /// 自动识别并拆解剪贴板文本中的结构化信息（收件地址 / 企业开票 / 会议日程）
    public static func parse(_ rawText: String) -> SmartInfoParseResult? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12, trimmed.count <= 2000 else { return nil }

        if let invoice = parseInvoice(trimmed) {
            return invoice
        }
        if let address = parseShippingAddress(trimmed) {
            return address
        }
        if let meeting = parseMeeting(trimmed) {
            return meeting
        }
        return nil
    }

    // MARK: - 1. 企业开票信息拆解

    private static func parseInvoice(_ text: String) -> SmartInfoParseResult? {
        let taxId = firstCapture(in: text, regex: labeledTaxIdRegex)?.uppercased()
            ?? firstCapture(in: text, regex: standaloneCreditCodeRegex)?.uppercased()

        let hasInvoiceKeyword = text.contains("税号") || text.contains("抬头") || text.contains("开票") || text.contains("开户行") || text.contains("信用代码")
        guard taxId != nil || hasInvoiceKeyword else { return nil }

        let company = cleanFieldValue(
            firstCapture(in: text, regex: labeledCompanyRegex)
                ?? firstCapture(in: text, regex: companySuffixRegex)
        )
        let bankName = cleanFieldValue(
            firstCapture(in: text, regex: labeledBankNameRegex)
                ?? firstCapture(in: text, regex: standaloneBankNameRegex)
        )
        let rawBankAccount = firstCapture(in: text, regex: labeledBankAccountRegex)
            ?? firstCapture(in: text, regex: standaloneBankAccountRegex)
        let bankAccount = rawBankAccount.map { digitsOnly($0) }.flatMap { $0.count >= 12 ? $0 : nil }

        var fields: [SmartInfoField] = []
        if let company, !company.isEmpty {
            fields.append(SmartInfoField(id: "company", label: "抬头", value: company))
        }
        if let taxId, !taxId.isEmpty {
            fields.append(SmartInfoField(id: "taxId", label: "税号", value: taxId))
        }
        if let bankName, !bankName.isEmpty {
            fields.append(SmartInfoField(id: "bankName", label: "开户行", value: bankName))
        }
        if let bankAccount, !bankAccount.isEmpty {
            fields.append(SmartInfoField(id: "bankAccount", label: "账号", value: bankAccount))
        }
        if let address = cleanFieldValue(firstCapture(in: text, regex: labeledAddressRegex)), address.count >= 6 {
            fields.append(SmartInfoField(id: "address", label: "地址", value: address))
        }

        // 必须有税号且至少 2 个有效字段，防止误判普通文本
        guard taxId != nil, fields.count >= 2 else { return nil }
        return SmartInfoParseResult(
            kind: .corporateInvoice,
            title: "识别到企业开票信息（\(fields.count) 项）",
            fields: fields
        )
    }

    // MARK: - 2. 快递收件地址拆解

    private static func parseShippingAddress(_ text: String) -> SmartInfoParseResult? {
        guard let rawPhoneMatch = firstMatchRangeAndCapture(in: text, regex: phoneRegex) else {
            return nil
        }
        let normalizedPhone = digitsOnly(rawPhoneMatch.value)
        guard normalizedPhone.count == 11 else { return nil }

        // 1. 先提取明确标注的姓名与地址
        var name = cleanFieldValue(firstCapture(in: text, regex: labeledNameRegex))
        var address = cleanFieldValue(firstCapture(in: text, regex: labeledAddressRegex))

        // 2. 若未标注，按分隔符拆段智能识别地址与姓名
        let residualText = stripPhoneAndLabels(from: text, rawPhone: rawPhoneMatch.value)
        let segments = residualText
            .components(separatedBy: CharacterSet(charactersIn: "\n\r,，;；|｜\t "))
            .map { cleanFieldValue($0) ?? "" }
            .filter { !$0.isEmpty }

        if address == nil {
            // 优先寻找包含省市区路号特征的较长段落；如果被空格切开，尝试拼接相邻地址段
            var addrCandidates: [String] = []
            for seg in segments where seg.count >= 4 {
                if hasAddressIndicator(seg) {
                    addrCandidates.append(seg)
                }
            }
            if !addrCandidates.isEmpty {
                let merged = addrCandidates.joined(separator: " ")
                if merged.count >= 6 {
                    address = merged
                }
            }
        }

        if name == nil {
            for seg in segments {
                if seg.count >= 2, seg.count <= 4,
                   isPureChineseName(seg),
                   !nameStopWords.contains(seg),
                   !hasAddressIndicator(seg) {
                    if let addr = address, addr.contains(seg) { continue }
                    name = seg
                    break
                }
            }
        }

        guard let finalAddress = address, finalAddress.count >= 6 else { return nil }

        var fields: [SmartInfoField] = []
        if let finalName = name, !finalName.isEmpty {
            fields.append(SmartInfoField(id: "name", label: "姓名", value: finalName))
        }
        fields.append(SmartInfoField(id: "phone", label: "手机", value: normalizedPhone))
        fields.append(SmartInfoField(id: "address", label: "地址", value: finalAddress))

        return SmartInfoParseResult(
            kind: .shippingAddress,
            title: "识别到收件地址（\(fields.count) 项）",
            fields: fields
        )
    }

    // MARK: - 3. 会议与日程信息拆解

    private static func parseMeeting(_ text: String) -> SmartInfoParseResult? {
        let meetingIdRaw = firstCapture(in: text, regex: meetingIdRegex)
        let meetingId = meetingIdRaw.map { $0.replacingOccurrences(of: " ", with: "") }
        let passcode = cleanFieldValue(firstCapture(in: text, regex: meetingPasscodeRegex))
        let time = cleanFieldValue(firstCapture(in: text, regex: meetingTimeRegex))
        let location = cleanFieldValue(firstCapture(in: text, regex: meetingLocationRegex))

        var fields: [SmartInfoField] = []
        if let time, !time.isEmpty {
            fields.append(SmartInfoField(id: "time", label: "时间", value: time))
        }
        if let meetingId, !meetingId.isEmpty {
            fields.append(SmartInfoField(id: "meetingId", label: "会议号", value: meetingId))
        }
        if let passcode, !passcode.isEmpty {
            fields.append(SmartInfoField(id: "passcode", label: "密码", value: passcode))
        }
        if let location, !location.isEmpty {
            fields.append(SmartInfoField(id: "location", label: "地点", value: location))
        }

        let isValid = (meetingId != nil && fields.count >= 2) || (time != nil && location != nil)
        guard isValid else { return nil }

        return SmartInfoParseResult(
            kind: .meetingSchedule,
            title: "识别到会议日程（\(fields.count) 项）",
            fields: fields
        )
    }

    // MARK: - Private Helpers

    private static func firstCapture(in text: String, regex: NSRegularExpression?) -> String? {
        firstMatchRangeAndCapture(in: text, regex: regex)?.value
    }

    private static func firstMatchRangeAndCapture(
        in text: String,
        regex: NSRegularExpression?
    ) -> (range: NSRange, value: String)? {
        guard let regex else { return nil }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: fullRange) else { return nil }
        let groupIndex = match.numberOfRanges > 1 ? 1 : 0
        let captureRange = match.range(at: groupIndex)
        guard captureRange.location != NSNotFound else { return nil }
        return (match.range, nsText.substring(with: captureRange))
    }

    private static func cleanFieldValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "：:,，;；。\"'「」【】")))
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func digitsOnly(_ raw: String) -> String {
        String(raw.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) })
    }

    private static func hasAddressIndicator(_ segment: String) -> Bool {
        guard let regex = addressIndicatorRegex else { return false }
        let range = NSRange(segment.startIndex..<segment.endIndex, in: segment)
        return regex.firstMatch(in: segment, options: [], range: range) != nil
    }

    private static func isPureChineseName(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return text.unicodeScalars.allSatisfy { scalar in
            (0x4E00...0x9FA5).contains(scalar.value)
        }
    }

    private static func stripPhoneAndLabels(from text: String, rawPhone: String) -> String {
        var result = text.replacingOccurrences(of: rawPhone, with: " ")
        let labelPrefixes = [
            "收货地址：", "收货地址:", "收件地址：", "收件地址:", "详细地址：", "详细地址:", "地址：", "地址:",
            "收件人：", "收件人:", "收货人：", "收货人:", "联系人：", "联系人:", "姓名：", "姓名:",
            "手机号：", "手机号:", "手机：", "手机:", "电话：", "电话:", "联系电话：", "联系电话:"
        ]
        for prefix in labelPrefixes {
            result = result.replacingOccurrences(of: prefix, with: " ")
        }
        return result
    }
}
