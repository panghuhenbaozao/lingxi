import Foundation

/// 单个动态提示词变量规格（对标 Raycast AI / PromptLayer 参数化指令语法）：
/// - `{{收件人|老板,客户,同事}}` → 枚举胶囊选择器（默认首项）
/// - `{{字数=120}}` → 带默认值的输入框
/// - `{{核心要点}}` → 自由输入字段
struct PromptVariableSpec: Identifiable, Equatable, Hashable {
    var id: String { name }
    let name: String
    let options: [String]
    let defaultValue: String
    let rawToken: String

    var isChoice: Bool { !options.isEmpty }
    var initialValue: String {
        if !defaultValue.isEmpty { return defaultValue }
        return options.first ?? ""
    }
}

/// 预置的高频参数化场景指令模板（带结构化 `{{变量}}` 表单与一键装入键盘能力）
struct ParameterizedProTemplate: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let category: String
    let icon: String
    let summary: String
    let systemPrompt: String
    let userPromptTemplate: String
    let preferDeep: Bool
}

/// 动态变量提示词解析与渲染引擎（纯 Foundation、零第三方依赖、App 与键盘共享）
enum PromptVariableEngine {
    /// 内置零输入动态上下文令牌：渲染时自动注入，无需用户手填表单
    static let magicContextTokens: Set<String> = [
        "当前日期", "当前时间", "当前城市", "当前场景", "剪贴板"
    ]

    /// 从任意模板文本中按出现顺序提取需要用户填写/选择的去重变量列表
    static func extractVariables(from template: String) -> [PromptVariableSpec] {
        guard template.contains("{{") else { return [] }
        let pattern = #"\{\{([^{}\n]{1,120})\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = template as NSString
        let matches = regex.matches(in: template, range: NSRange(location: 0, length: ns.length))

        var seen = Set<String>()
        var result: [PromptVariableSpec] = []
        for m in matches {
            guard m.numberOfRanges >= 2 else { continue }
            let rawToken = ns.substring(with: m.range(at: 0))
            let inner = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !inner.isEmpty else { continue }

            let name: String
            var options: [String] = []
            var defaultVal = ""

            if let pipeIdx = inner.firstIndex(of: "|") {
                name = String(inner[..<pipeIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                let rhs = String(inner[inner.index(after: pipeIdx)...])
                options = rhs
                    .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "/" })
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                defaultVal = options.first ?? ""
            } else if let eqIdx = inner.firstIndex(of: "=") {
                name = String(inner[..<eqIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                defaultVal = String(inner[inner.index(after: eqIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                name = inner
            }

            guard !name.isEmpty, !magicContextTokens.contains(name) else { continue }
            if seen.insert(name).inserted {
                result.append(PromptVariableSpec(name: name, options: options, defaultValue: defaultVal, rawToken: rawToken))
            }
        }
        return result
    }

    static func hasInteractiveVariables(in template: String) -> Bool {
        !extractVariables(from: template).isEmpty
    }

    /// 渲染动态变量与内置上下文令牌（`{{当前日期}}` / `{{当前时间}}` / `{{当前城市}}` / `{{当前场景}}` / `{{剪贴板}}`）
    static func render(
        template: String,
        values: [String: String],
        clipboardText: String = "",
        sceneTitle: String = "",
        cityName: String = "",
        now: Date = Date()
    ) -> String {
        guard template.contains("{{") else { return template }
        let pattern = #"\{\{([^{}\n]{1,120})\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return template }

        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "zh_CN")
        dateFmt.dateFormat = "yyyy年M月d日"
        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "zh_CN")
        timeFmt.dateFormat = "HH:mm"

        let magicMap: [String: String] = [
            "当前日期": dateFmt.string(from: now),
            "当前时间": timeFmt.string(from: now),
            "当前城市": cityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "当前所在城市" : cityName,
            "当前场景": sceneTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "自动语境" : sceneTitle,
            "剪贴板": clipboardText.trimmingCharacters(in: .whitespacesAndNewlines),
        ]

        let ns = template as NSString
        let matches = regex.matches(in: template, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return template }

        var output = ""
        var lastLoc = 0
        for m in matches {
            if m.range.location > lastLoc {
                output += ns.substring(with: NSRange(location: lastLoc, length: m.range.location - lastLoc))
            }
            let inner = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let name: String
            var fallback = ""
            if let pipeIdx = inner.firstIndex(of: "|") {
                name = String(inner[..<pipeIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                let rhs = String(inner[inner.index(after: pipeIdx)...])
                fallback = rhs.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "/" })
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first(where: { !$0.isEmpty }) ?? ""
            } else if let eqIdx = inner.firstIndex(of: "=") {
                name = String(inner[..<eqIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                fallback = String(inner[inner.index(after: eqIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                name = inner
            }

            if let magicVal = magicMap[name] {
                output += magicVal
            } else if let userVal = values[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !userVal.isEmpty {
                output += userVal
            } else {
                output += fallback
            }
            lastLoc = m.range.location + m.range.length
        }
        if lastLoc < ns.length {
            output += ns.substring(from: lastLoc)
        }
        return output
    }

    /// 将参数化模板的当前默认值静态化，便于一键安装为键盘快捷技能
    static func staticSystemPrompt(for template: ParameterizedProTemplate, values: [String: String]) -> String {
        let renderedContext = render(template: template.userPromptTemplate, values: values)
        return "\(template.systemPrompt)\n【用户预设参数参考】\n\(renderedContext)\n请针对用户后续输入的实际草稿直接输出最终可直接发送的正文。"
    }

    // MARK: - 8 套精选参数化专业场景模板

    static let featuredTemplates: [ParameterizedProTemplate] = [
        ParameterizedProTemplate(
            id: "var_polite_decline",
            title: "高情商拒绝与请假",
            category: "职场沟通",
            icon: "hand.raised.fill",
            summary: "按对象与语气一键生成不伤和气、留足余地的婉拒或请假消息",
            systemPrompt: "你是顶级中文职场沟通专家。请根据给定对象、语气和事由，写出自然真诚、不卑不亢、可直接微信/邮件发送的消息。严禁油腻官腔与多余说明，只直接输出正文。",
            userPromptTemplate: "沟通对象：{{对象|直属领导,重要客户,平级同事,朋友家人}}\n期望语气：{{语气|委婉诚恳,专业利落,轻松幽默}}\n字数控制：约 {{字数=80}} 字内\n具体事由与替代方案：{{事由与备选方案}}",
            preferDeep: false
        ),
        ParameterizedProTemplate(
            id: "var_weekly_report",
            title: "结构化周报 / 汇报",
            category: "职场沟通",
            icon: "list.bullet.clipboard",
            summary: "把零散工作记录按汇报对象提炼成结论先行的专业周报",
            systemPrompt: "你是资深管理咨询顾问。请把碎片化工作记录提炼为结构清晰、数据感强、结论先行的工作汇报，去掉废话与空洞形容词，使用干净纯文本分点，不要 Markdown 粗体星号。",
            userPromptTemplate: "汇报日期：{{当前日期}}\n汇报对象：{{汇报对象|直属主管,高管团队,项目干系人}}\n组织结构：{{结构|结论先行金字塔,已完成/进行中/下周计划,成果与风险双栏}}\n原始工作记录：{{原始工作要点}}",
            preferDeep: true
        ),
        ParameterizedProTemplate(
            id: "var_negotiate_price",
            title: "商务谈判与礼貌还价",
            category: "商务博弈",
            icon: "shield.lefthalf.filled",
            summary: "根据谈判筹码生成有理有据、兼顾长期合作的还价或争取条件话术",
            systemPrompt: "你是资深商务谈判专家。请基于给定立场和底线，起草一段专业克制、逻辑扎实、既表达合作诚意又能有效争取利益的沟通话术。只直接输出可直接发送的正文。",
            userPromptTemplate: "谈判策略：{{策略|预算封顶求让步,对比方案温和压价,以长期合作换折扣,争取增值服务或账期}}\n我的目标与底线：{{目标价格或条件}}\n对方当前报价或原话：{{对方原话}}",
            preferDeep: true
        ),
        ParameterizedProTemplate(
            id: "var_social_post",
            title: "多平台社媒爆款重构",
            category: "内容创作",
            icon: "sparkles",
            summary: "同一段随手素材一键改写成小红书、朋友圈、公众号或 X 风格",
            systemPrompt: "你是顶级新媒体内容主编。请将用户的原始素材改写为完全契合目标平台调性的高互动文案，拒绝 AI 味与套话，保留真实人感与节奏感。只输出成品文案。",
            userPromptTemplate: "发布平台：{{平台|小红书种草,微信朋友圈,公众号推文导语,X/推特短评}}\n预期篇幅：{{篇幅|120字以内短平快,260字干货分享}}\n吸睛侧重：{{侧重|真实体验共鸣,反常识金句开头,实用避坑清单}}\n原始素材：{{原始想法或草稿}}",
            preferDeep: false
        ),
        ParameterizedProTemplate(
            id: "var_pro_email",
            title: "商务邮件一键起草",
            category: "商务办公",
            icon: "envelope.fill",
            summary: "含清晰主题行、正文与行动项的中英双语商务邮件",
            systemPrompt: "你是资深跨国企业商务沟通专家。请生成一封含「主题：」和正文的专业邮件，段落简洁、行动项明确（含时间节点），符合对应语种商务礼仪。",
            userPromptTemplate: "邮件语种：{{语种|简体中文,地道商务英文,中英双语对照}}\n语气定位：{{语气|正式得体,友好协作,礼貌催进度}}\n核心诉求与截止时间：{{核心事项}}",
            preferDeep: false
        ),
        ParameterizedProTemplate(
            id: "var_code_review",
            title: "技术评审 / Code Review",
            category: "研发效率",
            icon: "chevron.left.forwardslash.chevron.right",
            summary: "输出专业、建设性且直指关键隐患的代码评审或技术方案意见",
            systemPrompt: "你是 Staff 级软件架构师。请按指定语气输出清晰、具体、可落地的技术评审意见：先肯定亮点，再按严重程度列出问题与改进建议，避免人身指责。",
            userPromptTemplate: "评审风格：{{风格|温和建设性,极简直指隐患,架构深度剖析}}\n关注重点：{{重点|边界条件与并发安全,性能与内存,可读性与架构解耦}}\n代码片段或方案说明：{{待评审内容}}",
            preferDeep: true
        ),
        ParameterizedProTemplate(
            id: "var_crisis_apology",
            title: "致歉安抚与公关澄清",
            category: "高情商应对",
            icon: "heart.text.square.fill",
            summary: "先承接情绪、再给明确方案，避免越描越黑的高分致歉/澄清回复",
            systemPrompt: "你是危机公关与高情商沟通专家。请严格遵循「共情承接→清晰说明→落地补偿/时间表→诚恳收尾」四步结构写出真诚克制的回复，绝不甩锅、不啰嗦。只输出正文。",
            userPromptTemplate: "场景定性：{{定性|我方疏漏诚恳致歉,客观不可抗力安抚,礼貌澄清误解守住边界}}\n事情经过与补救方案：{{经过与补救措施}}",
            preferDeep: false
        ),
        ParameterizedProTemplate(
            id: "var_academic_polish",
            title: "去 AI 腔与深度精修",
            category: "文字打磨",
            icon: "doc.text.magnifyingglass",
            summary: "精准去除「赋能/闭环/综上所述」等机械 AI 腔，保留原意提升质感",
            systemPrompt: "你是资深文字编辑。请精准消除机械翻译腔、AI 模板词（如「值得注意的是」「总而言之」「赋能」「抓手」）与冗长定语，在 100% 忠于原意的前提下提升表达准确度与可读性。只输出修改后正文。",
            userPromptTemplate: "精修方向：{{方向|去AI味更像真人,学术严谨表达,压缩30%更精炼,升级高级词汇}}\n保留术语（可选）：{{保留词=无}}\n原文段落：{{待精修文本}}",
            preferDeep: true
        ),
    ]
}
