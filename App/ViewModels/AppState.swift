import Combine
import SwiftUI
import UIKit

@MainActor
final class AppState: ObservableObject {
    @Published var settings: LingxiSettings {
        didSet {
            settings.save()
            scheduleAutoSyncIfNeeded()
        }
    }
    @Published var theme: ThemeCustomization {
        didSet {
            theme.save()
            scheduleAutoSyncIfNeeded()
        }
    }
    @Published var aiConfig: AIConfig {
        didSet {
            aiConfig.save()
            scheduleAutoSyncIfNeeded()
        }
    }
    @Published var cloudConfig: CloudBackendConfig {
        didSet { cloudConfig.save() }
    }
    @Published var habitProfile: UserTypingHabitProfile = TypingHabitTracker.shared.currentProfile()
    @Published var aiInsightReport: AIAutoInsightReport? = AIAutoInsightService.loadCachedReport()
    @Published var isRunningAIInsight: Bool = false
    @Published var isCloudAuthenticated: Bool = false
    @Published var activeCustomerAPIKey: String = ""
    @Published var clipboardItems: [ClipboardItem] = []
    @Published var quickPhrases: [QuickPhrase] = []
    @Published var customWords: [CustomWordEntry] = []
    @Published var userWords: [UserWordEntry] = []
    @Published var isKeyboardEnabled: Bool = false
    @Published var customBgPreview: UIImage?
    @Published var userAvatarImage: UIImage?

    static let userAvatarFileName = "lingxi_user_avatar.jpg"

    let lexicon = UserLexicon()
    private var autoSyncTask: Task<Void, Never>?
    private var isRefreshingState = false

    init() {
        self.settings = LingxiSettings.load(force: true)
        self.theme = ThemeCustomization.load(force: true)
        self.aiConfig = AIConfig.load()
        self.cloudConfig = CloudBackendConfig.load()
        refreshAll()
    }

    func refreshAll() {
        isRefreshingState = true
        defer { isRefreshingState = false }
        settings = LingxiSettings.load(force: true)
        theme = ThemeCustomization.load(force: true)
        aiConfig = AIConfig.load()
        cloudConfig = CloudBackendConfig.load()
        habitProfile = TypingHabitTracker.shared.currentProfile()
        aiInsightReport = AIAutoInsightService.loadCachedReport()
        isCloudAuthenticated = CloudBackendClient.shared.isAuthenticatedOrHasAPIKey
        activeCustomerAPIKey = CloudCredentialStore.loadAPIKey() ?? ""
        clipboardItems = ClipboardStore.items()
        quickPhrases = QuickPhraseStore.load()
        customWords = CustomWordStore.load(force: true)
        userWords = lexicon.allEntries(limit: 250)
        isKeyboardEnabled = checkKeyboardEnabled()
        loadCustomBackgroundPreview()
        loadUserAvatar()
    }

    /// 当已登录或已接入客户 API Key 且开启自动同步时，按当前激活的同步层实现（LocalNoop / LAN / E2EE Cloud）防抖触发后台无感同步
    func scheduleAutoSyncIfNeeded() {
        let relayCfg = ClipboardRelayConfig.load()
        guard !isRefreshingState,
              cloudConfig.autoSyncEnabled,
              relayCfg.syncTransportMode != .localNoop else {
            return
        }
        if relayCfg.syncTransportMode == .e2eeCloud && !CloudBackendClient.shared.isAuthenticatedOrHasAPIKey {
            return
        }
        autoSyncTask?.cancel()
        autoSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled, let self else { return }
            if relayCfg.syncTransportMode == .lan {
                _ = try? await LANSyncService.shared.performPeerSync(
                    peerHost: relayCfg.lanPeerHost,
                    peerPort: UInt16(relayCfg.lanPort),
                    pairCode: relayCfg.pairCode
                )
            } else {
                _ = try? await CloudBackendClient.shared.syncAllImportantDataAndHabits()
            }
            self.habitProfile = TypingHabitTracker.shared.currentProfile()
            self.cloudConfig = CloudBackendConfig.load()
        }
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

    // MARK: - Apple 风格用户头像持久化

    func saveUserAvatarImage(_ image: UIImage) {
        let targetSide: CGFloat = 256
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetSide, height: targetSide))
        let square = renderer.image { _ in
            let minSide = min(image.size.width, image.size.height)
            let scale = targetSide / max(1, minSide)
            let drawW = image.size.width * scale
            let drawH = image.size.height * scale
            let drawRect = CGRect(x: (targetSide - drawW) / 2, y: (targetSide - drawH) / 2, width: drawW, height: drawH)
            image.draw(in: drawRect)
        }
        guard let jpeg = square.jpegData(compressionQuality: 0.85) else { return }
        let url = AppGroup.fileURL(Self.userAvatarFileName)
        if (try? jpeg.write(to: url, options: [.atomic])) != nil {
            userAvatarImage = square
        }
    }

    func removeUserAvatarImage() {
        try? FileManager.default.removeItem(at: AppGroup.fileURL(Self.userAvatarFileName))
        userAvatarImage = nil
    }

    private func loadUserAvatar() {
        let url = AppGroup.fileURL(Self.userAvatarFileName)
        if let data = try? Data(contentsOf: url) {
            userAvatarImage = UIImage(data: data)
        } else {
            userAvatarImage = nil
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

    // MARK: - 云端账号、重要数据同步与 API 打字习惯分析

    func registerCloudAccount(email: String, username: String, password: String) async throws {
        _ = try await CloudBackendClient.shared.register(email: email, username: username, password: password)
        refreshAll()
        _ = try? await syncCloudNow()
    }

    func loginCloudAccount(account: String, password: String) async throws {
        _ = try await CloudBackendClient.shared.login(account: account, password: password)
        refreshAll()
        _ = try? await syncCloudNow()
    }

    func signInWithAppleAccount(identityToken: Data, user: String) async throws {
        _ = try await CloudBackendClient.shared.signInWithApple(identityToken: identityToken, user: user)
        refreshAll()
        _ = try? await syncCloudNow()
    }

    func createQuickLocalAccount(username: String = "灵犀用户") {
        _ = CloudBackendClient.shared.createQuickLocalAccount(username: username)
        refreshAll()
    }

    func connectCustomerAPIKey(_ rawKey: String) async throws {
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CloudBackendError.badRequest("请输入有效的 API Key (如 lx_live_...)")
        }
        CloudCredentialStore.saveAPIKey(trimmed)
        cloudConfig.apiKeyPrefix = String(trimmed.prefix(16)) + "..."
        cloudConfig.save()
        let profile = try await CloudBackendClient.shared.syncTypingHabitsWithServer()
        habitProfile = profile
        refreshAll()
    }

    func rotateCloudAPIKey() async throws -> String {
        let newKey = try await CloudBackendClient.shared.rotateAPIKey()
        refreshAll()
        return newKey
    }

    func signOutCloudAccount() async {
        await CloudBackendClient.shared.signOut()
        refreshAll()
    }

    @discardableResult
    func syncCloudNow() async throws -> SyncRunReport {
        let relayCfg = ClipboardRelayConfig.load()
        let report: SyncRunReport
        switch relayCfg.syncTransportMode {
        case .localNoop:
            let engine = SyncEngine(sync: LocalNoopSyncService(), source: SyncEngine.makeFullSyncSource())
            report = try await engine.syncNow()
        case .lan:
            report = try await LANSyncService.shared.performPeerSync(
                peerHost: relayCfg.lanPeerHost,
                peerPort: UInt16(relayCfg.lanPort),
                pairCode: relayCfg.pairCode
            )
        case .e2eeCloud:
            if cloudConfig.isLocalOnlyAccount && cloudConfig.normalizedBaseURL.contains("127.0.0.1") {
                let engine = SyncEngine(sync: LocalNoopSyncService(), source: SyncEngine.makeFullSyncSource())
                report = try await engine.syncNow()
            } else {
                report = try await CloudBackendClient.shared.syncAllImportantDataAndHabits()
            }
        }
        refreshAll()
        return report
    }

    func refreshHabitProfile() async {
        if CloudBackendClient.shared.isAuthenticatedOrHasAPIKey {
            if let remote = try? await CloudBackendClient.shared.syncTypingHabitsWithServer() {
                habitProfile = remote
                return
            }
        }
        habitProfile = TypingHabitTracker.shared.currentProfile()
        aiInsightReport = AIAutoInsightService.loadCachedReport()
    }

    func clearAllHabitAnalytics() async {
        if let cleared = try? await CloudBackendClient.shared.deleteServerHabits() {
            habitProfile = cleared
        } else {
            TypingHabitTracker.shared.clearAllLocalHabits()
            habitProfile = TypingHabitTracker.shared.currentProfile()
            aiInsightReport = AIAutoInsightService.loadCachedReport()
        }
    }

    /// 一键应用智能习惯分析引擎给出的参数调优建议（含专属模糊音配对）
    func applyTuningRecommendation(_ rec: TypingTuningRecommendation) {
        switch rec.settingKey {
        case "dynamicKeyHitBoxEnabled":
            settings.dynamicKeyHitBoxEnabled = true
            settings.typoCorrectionEnabled = true
            settings.fuzzyFallbackEnabled = true
        case "autoLearnThreshold":
            settings.autoLearnThreshold = max(2, settings.autoLearnThreshold)
        case "bigramPredictionEnabled":
            settings.bigramPredictionEnabled = true
        case "glideTypingEnabled":
            settings.glideTypingEnabled = true
        case "userLearningEnabled":
            settings.userLearningEnabled = true
        case "fuzzy.zhZ":
            settings.fuzzy.zhZ = true
        case "fuzzy.chC":
            settings.fuzzy.chC = true
        case "fuzzy.shS":
            settings.fuzzy.shS = true
        case "fuzzy.nl":
            settings.fuzzy.nl = true
        case "fuzzy.anAng":
            settings.fuzzy.anAng = true
        case "fuzzy.enEng":
            settings.fuzzy.enEng = true
        case "fuzzy.inIng":
            settings.fuzzy.inIng = true
        case "fuzzy.fh":
            settings.fuzzy.fh = true
        case "fuzzy.huangWang":
            settings.fuzzy.huangWang = true
        default:
            break
        }
    }

    // MARK: - AI 自动分析诊断与专属提示词工坊

    @discardableResult
    func runAIAutoAnalysis() async -> AIAutoInsightReport {
        isRunningAIInsight = true
        defer { isRunningAIInsight = false }
        let currentHabit = TypingHabitTracker.shared.currentProfile()
        habitProfile = currentHabit
        let report = await AIAutoInsightService.runAutoAnalysis(
            config: aiConfig,
            profile: currentHabit,
            stats: TypingStatsStore.shared.summary(),
            settings: settings
        )
        aiInsightReport = report
        return report
    }

    func addOrUpdateCustomPrompt(_ template: CustomAIPromptTemplate) {
        if let idx = aiConfig.customPrompts.firstIndex(where: { $0.id == template.id }) {
            aiConfig.customPrompts[idx] = template
        } else {
            aiConfig.customPrompts.insert(template, at: 0)
        }
    }

    func deleteCustomPrompt(id: String) {
        aiConfig.customPrompts.removeAll { $0.id == id }
    }

    func togglePinCustomPrompt(id: String) {
        if let idx = aiConfig.customPrompts.firstIndex(where: { $0.id == id }) {
            aiConfig.customPrompts[idx].isPinned.toggle()
        }
    }

    @discardableResult
    func importSuggestedPrompts(_ prompts: [CustomAIPromptTemplate]) -> Int {
        var added = 0
        var existingTitles = Set(aiConfig.customPrompts.map(\.title))
        for item in prompts {
            if existingTitles.insert(item.title).inserted {
                aiConfig.customPrompts.insert(item, at: 0)
                added += 1
            }
        }
        return added
    }

    @discardableResult
    func importSuggestedPhrases(_ phrases: [AISuggestedPhrase]) -> Int {
        var added = 0
        var existingContents = Set(QuickPhraseStore.load().map(\.content))
        for phrase in phrases where !phrase.content.isEmpty {
            if existingContents.insert(phrase.content).inserted {
                QuickPhraseStore.add(title: phrase.title, content: phrase.content, category: phrase.category)
                added += 1
            }
        }
        quickPhrases = QuickPhraseStore.load()
        return added
    }

    @discardableResult
    func applySuggestedFuzzyKeys(_ keys: [String]) -> Int {
        var copy = settings
        let count = AIAutoInsightService.applyFuzzyKeys(keys, to: &copy)
        if count > 0 {
            settings = copy
        }
        return count
    }
}
