import Foundation

/// 个人常用速填名片类型（日常高频表单项，非敏感密码）
public enum PersonalCardKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case homeAddress = "home_address"
    case workAddress = "work_address"
    case invoice = "invoice"
    case contact = "contact"
    case custom = "custom"

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .homeAddress: return "家庭收件"
        case .workAddress: return "公司收件"
        case .invoice: return "企业开票"
        case .contact: return "联系与车牌"
        case .custom: return "自定义名片"
        }
    }

    public var badgePrefix: String {
        switch self {
        case .homeAddress: return "🏠"
        case .workAddress: return "🏢"
        case .invoice: return "🧾"
        case .contact: return "🚗"
        case .custom: return "🪪"
        }
    }

    public var systemIcon: String {
        switch self {
        case .homeAddress: return "house.fill"
        case .workAddress: return "building.2.fill"
        case .invoice: return "doc.text.fill"
        case .contact: return "person.text.rectangle.fill"
        case .custom: return "rectangle.stack.person.crop"
        }
    }

    public var defaultFieldLabels: [String] {
        switch self {
        case .homeAddress, .workAddress:
            return ["姓名", "手机", "地址"]
        case .invoice:
            return ["抬头", "税号", "开户行", "账号"]
        case .contact:
            return ["姓名", "手机", "邮箱", "车牌"]
        case .custom:
            return ["项1", "项2", "项3"]
        }
    }
}

/// 名片内的单个结构化速填字段
public struct PersonalCardField: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var value: String

    public init(id: String = UUID().uuidString, label: String, value: String) {
        self.id = id
        self.label = label
        self.value = value
    }
}

/// 个人结构化速填名片（用于小程序/网购/医院/报销表单分字段 1 秒点填）
public struct PersonalFillCard: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var kind: PersonalCardKind
    public var fields: [PersonalCardField]
    public var updatedAt: Date

    public var nonEmptyFields: [PersonalCardField] {
        fields.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public var formattedFullText: String {
        nonEmptyFields.map { "\($0.label)：\($0.value)" }.joined(separator: "\n")
    }

    public var compactOneLine: String {
        nonEmptyFields.map(\.value).joined(separator: " ")
    }

    public init(
        id: UUID = UUID(),
        title: String,
        kind: PersonalCardKind,
        fields: [PersonalCardField],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.fields = fields
        self.updatedAt = updatedAt
    }
}

/// 个人速填名片夹持久化与 `v` 模式快捷召唤引擎（`vdz` 地址 / `vkp` 开票 / `vmp` 名片 / `vcp` 车牌）。
public enum PersonalFillCardStore {
    private static let fileName = "personal_fill_cards.json"
    private static let lock = NSLock()
    public static let vModeTriggers: Set<String> = [
        "dz", "dizhi", "kp", "kaipiao", "mp", "mingpian", "cp", "chepai", "shuihao",
        "yx", "youxiang", "dh", "dianhua", "shouji",
    ]

    public static func load() -> [PersonalFillCard] {
        lock.lock()
        defer { lock.unlock() }
        return AppGroup.readJSON([PersonalFillCard].self, from: fileName) ?? []
    }

    public static func save(_ cards: [PersonalFillCard]) {
        lock.lock()
        defer { lock.unlock() }
        _ = AppGroup.writeJSON(cards, to: fileName, protected: true)
    }

    public static func upsert(_ card: PersonalFillCard) {
        var list = load()
        var updated = card
        updated.updatedAt = Date()
        if let idx = list.firstIndex(where: { $0.id == card.id }) {
            list[idx] = updated
        } else {
            list.insert(updated, at: 0)
        }
        save(list)
    }

    public static func delete(id: UUID) {
        var list = load()
        list.removeAll { $0.id == id }
        save(list)
    }

    /// 联动 `SmartInfoParser`：从任意一段复制的收件地址或开票文本 1 键识别并生成结构化速填名片
    public static func buildCardFromRawText(_ rawText: String, titleOverride: String? = nil) -> PersonalFillCard? {
        guard let parsed = SmartInfoParser.parse(rawText), !parsed.fields.isEmpty else {
            return nil
        }
        let kind: PersonalCardKind
        let defaultTitle: String
        switch parsed.kind {
        case .shippingAddress:
            kind = .homeAddress
            let namePart = parsed.fields.first(where: { $0.id == "name" })?.value
            defaultTitle = namePart.map { "\($0)的收件地址" } ?? "常用收件地址"
        case .corporateInvoice:
            kind = .invoice
            let company = parsed.fields.first(where: { $0.id == "company" })?.value
            defaultTitle = company.map { String($0.prefix(12)) } ?? "企业开票信息"
        case .meetingSchedule:
            kind = .custom
            defaultTitle = "常用会议信息"
        }
        let fields = parsed.fields.map { PersonalCardField(id: $0.id, label: $0.label, value: $0.value) }
        return PersonalFillCard(
            title: titleOverride?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? titleOverride!.trimmingCharacters(in: .whitespacesAndNewlines)
                : defaultTitle,
            kind: kind,
            fields: fields
        )
    }

    /// 键盘 `v` 模式秒调已存名片候选（`vdz` 地址 / `vkp` 开票 / `vmp` 名片 / `vcp` 车牌）
    public static func vModeCandidates(forBody rawBody: String, cards: [PersonalFillCard]? = nil) -> [String] {
        let lower = rawBody.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard vModeTriggers.contains(lower) else { return [] }
        let allCards = cards ?? load()
        guard !allCards.isEmpty else { return [] }

        let filtered: [PersonalFillCard]
        switch lower {
        case "dz", "dizhi":
            filtered = allCards.filter { $0.kind == .homeAddress || $0.kind == .workAddress }
        case "kp", "kaipiao", "shuihao":
            filtered = allCards.filter { $0.kind == .invoice }
        case "cp", "chepai":
            filtered = allCards.filter { card in
                card.kind == .contact || card.nonEmptyFields.contains { $0.label.contains("车牌") }
            }
        case "yx", "youxiang":
            filtered = allCards.filter { card in
                card.nonEmptyFields.contains { $0.label.contains("邮箱") || $0.value.contains("@") }
            }
        case "dh", "dianhua", "shouji":
            filtered = allCards.filter { card in
                card.nonEmptyFields.contains { $0.label.contains("手机") || $0.label.contains("电话") }
            }
        default:
            filtered = allCards
        }

        let targetCards = filtered.isEmpty ? allCards : filtered
        var out: [String] = []
        var seen = Set<String>()

        func push(_ value: String) {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, seen.insert(clean).inserted else { return }
            out.append(clean)
        }

        if lower == "shuihao" {
            for card in targetCards {
                for f in card.nonEmptyFields where f.label.contains("税号") {
                    push(f.value)
                }
            }
        } else if lower == "cp" || lower == "chepai" {
            for card in targetCards {
                for f in card.nonEmptyFields where f.label.contains("车牌") {
                    push(f.value)
                }
            }
        } else if lower == "yx" || lower == "youxiang" {
            for card in targetCards {
                for f in card.nonEmptyFields where f.label.contains("邮箱") || f.value.contains("@") {
                    push(f.value)
                }
            }
        } else if lower == "dh" || lower == "dianhua" || lower == "shouji" {
            for card in targetCards {
                for f in card.nonEmptyFields where f.label.contains("手机") || f.label.contains("电话") {
                    push(f.value)
                }
            }
        }

        for card in targetCards.prefix(4) {
            if lower == "dz" || lower == "dizhi" {
                push(card.compactOneLine)
                for f in card.nonEmptyFields where f.label.contains("地址") || f.label.contains("手机") || f.label.contains("姓名") {
                    push(f.value)
                }
            } else {
                for f in card.nonEmptyFields {
                    push(f.value)
                }
                push(card.formattedFullText)
            }
        }
        return Array(out.prefix(8))
    }

    /// 常规全拼直出速填名片：打 `dizhi / youxiang / shouji / dianhua / kaipiao / shuihao / chepai / mingpian` 时
    /// 无需记 `vdz` 前缀，直接把对应名片字段排在常规中文词之后供一键点选（不拦截 2 字母简拼）。
    public static func naturalPinyinCandidates(forNormalizedPinyin rawPinyin: String, cards: [PersonalFillCard]? = nil) -> [String] {
        let lower = rawPinyin.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fullTriggers: Set<String> = ["dizhi", "youxiang", "shouji", "dianhua", "kaipiao", "shuihao", "chepai", "mingpian"]
        guard fullTriggers.contains(lower) else { return [] }
        return Array(vModeCandidates(forBody: lower, cards: cards).prefix(3))
    }
}
