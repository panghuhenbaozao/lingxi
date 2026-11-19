import Foundation

/// 快捷短语条目。
struct QuickPhrase: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var content: String
    var category: String

    init(id: UUID = UUID(), title: String, content: String, category: String = "常用") {
        self.id = id
        self.title = title
        self.content = content
        self.category = category
    }
}

/// 快捷短语持久化管理，内置常用高频/有趣短语模板。
enum QuickPhraseStore {
    private static let fileName = "lingxi_phrases.json"

    static let defaults: [QuickPhrase] = [
        QuickPhrase(title: "收到马上看", content: "收到，我马上看一下，稍后回复您～", category: "职场"),
        QuickPhrase(title: "开会晚回", content: "不好意思正在开会，散会后第一时间联系您。", category: "职场"),
        QuickPhrase(title: "辛苦啦", content: "辛苦了，感谢配合与支持！", category: "职场"),
        QuickPhrase(title: "放门口", content: "快递/外卖请直接放在门口就好，谢谢师傅辛苦了！", category: "生活"),
        QuickPhrase(title: "在路上", content: "已经在路上了，大概还有十几分钟到。", category: "生活"),
        QuickPhrase(title: "哈哈笑死", content: "哈哈哈哈哈哈笑不活了", category: "趣味"),
        QuickPhrase(title: "贴贴抱抱", content: "(つ´ω`)つ 贴贴抱抱~", category: "趣味"),
        QuickPhrase(title: "赞爆了", content: "这也太强了吧！！直接封神 🔥", category: "趣味"),
    ]

    static func load() -> [QuickPhrase] {
        AppGroup.readJSON([QuickPhrase].self, from: fileName) ?? defaults
    }

    @discardableResult
    static func save(_ phrases: [QuickPhrase]) -> Bool {
        AppGroup.writeJSON(phrases, to: fileName)
    }

    static func add(title: String, content: String, category: String) {
        var list = load()
        list.insert(QuickPhrase(title: title, content: content, category: category), at: 0)
        save(list)
    }

    static func delete(id: UUID) {
        var list = load()
        list.removeAll { $0.id == id }
        save(list)
    }
}
