import Combine
import SwiftUI
import UIKit

@MainActor
final class AppState: ObservableObject {
    @Published var settings: LingxiSettings {
        didSet { settings.save() }
    }
    @Published var theme: ThemeCustomization {
        didSet { theme.save() }
    }
    @Published var aiConfig: AIConfig {
        didSet { aiConfig.save() }
    }
    @Published var clipboardItems: [ClipboardItem] = []
    @Published var quickPhrases: [QuickPhrase] = []
    @Published var customWords: [CustomWordEntry] = []
    @Published var userWords: [UserWordEntry] = []
    @Published var isKeyboardEnabled: Bool = false
    @Published var customBgPreview: UIImage?

    let lexicon = UserLexicon()

    init() {
        self.settings = LingxiSettings.load(force: true)
        self.theme = ThemeCustomization.load(force: true)
        self.aiConfig = AIConfig.load()
        refreshAll()
    }

    func refreshAll() {
        settings = LingxiSettings.load(force: true)
        theme = ThemeCustomization.load(force: true)
        aiConfig = AIConfig.load()
        clipboardItems = ClipboardStore.items()
        quickPhrases = QuickPhraseStore.load()
        customWords = CustomWordStore.load(force: true)
        userWords = lexicon.allEntries(limit: 250)
        isKeyboardEnabled = checkKeyboardEnabled()
        loadCustomBackgroundPreview()
    }

    private func checkKeyboardEnabled() -> Bool {
        let keyboards = UserDefaults.standard.object(forKey: "AppleKeyboards") as? [String] ?? []
        if let appBundleID = Bundle.main.bundleIdentifier {
            let expectedExtID = "\(appBundleID).keyboard"
            if keyboards.contains(expectedExtID) {
                return true
            }
        }
        return keyboards.contains { $0.lowercased().contains("lingxi") }
    }

    func saveCustomBackgroundImage(_ image: UIImage) {
        let maxDimension: CGFloat = 1080
        let size = image.size
        let scale = min(1.0, maxDimension / max(size.width, size.height))
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let jpegData = resized.jpegData(compressionQuality: 0.82) else { return }
        let fileName = ThemeCustomization.customBackgroundImageName
        let url = AppGroup.fileURL(fileName)
        do {
            try jpegData.write(to: url, options: [.atomic])
            theme.customBackgroundFileName = fileName
            customBgPreview = resized
        } catch {
            // 写入失败时保持原样
        }
    }

    func removeCustomBackgroundImage() {
        if let fileName = theme.customBackgroundFileName {
            try? FileManager.default.removeItem(at: AppGroup.fileURL(fileName))
        }
        theme.customBackgroundFileName = nil
        customBgPreview = nil
    }

    private func loadCustomBackgroundPreview() {
        if let url = theme.customBackgroundURL, let data = try? Data(contentsOf: url) {
            customBgPreview = UIImage(data: data)
        } else {
            customBgPreview = nil
        }
    }

    // MARK: - 剪贴板与短语操作

    func reloadClipboard() {
        clipboardItems = ClipboardStore.items()
    }

    func addClipboardEntry(_ text: String) {
        _ = ClipboardStore.record(text)
        reloadClipboard()
    }

    func togglePinClipboard(id: UUID) {
        ClipboardStore.togglePin(id: id)
        reloadClipboard()
    }

    func deleteClipboard(id: UUID) {
        ClipboardStore.delete(id: id)
        reloadClipboard()
    }

    func clearUnpinnedClipboard() {
        ClipboardStore.clearUnpinned()
        reloadClipboard()
    }

    func addQuickPhrase(title: String, content: String, category: String) {
        QuickPhraseStore.add(title: title, content: content, category: category)
        quickPhrases = QuickPhraseStore.load()
    }

    func deleteQuickPhrase(id: UUID) {
        QuickPhraseStore.delete(id: id)
        quickPhrases = QuickPhraseStore.load()
    }

    // MARK: - 用户词库管理

    func togglePinUserWord(_ entry: UserWordEntry) {
        lexicon.togglePin(word: entry.word, py: entry.py)
        userWords = lexicon.allEntries(limit: 250)
    }

    func forgetUserWord(_ entry: UserWordEntry) {
        lexicon.forget(word: entry.word, py: entry.py)
        userWords = lexicon.allEntries(limit: 250)
    }

    func clearUserLexicon() {
        lexicon.clearAll()
        userWords = []
    }

    func exportUserLexiconTSV() -> String {
        lexicon.exportTSV()
    }

    func importUserLexiconTSV(_ text: String) -> Int {
        let count = lexicon.importTSV(text)
        userWords = lexicon.allEntries(limit: 250)
        return count
    }

    // MARK: - 自定义短语 (custom.tsv)

    func addCustomWord(code: String, word: String) {
        CustomWordStore.add(code: code, word: word)
        customWords = CustomWordStore.load(force: true)
    }

    func deleteCustomWord(id: UUID) {
        CustomWordStore.delete(id: id)
        customWords = CustomWordStore.load(force: true)
    }

    func importCustomWordsTSV(_ text: String) -> Int {
        let count = CustomWordStore.importTSV(text)
        customWords = CustomWordStore.load(force: true)
        return count
    }

    func exportCustomWordsTSV() -> String {
        CustomWordStore.exportTSV()
    }
}
