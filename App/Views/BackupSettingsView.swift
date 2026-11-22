import SwiftUI
import UniformTypeIdentifiers

// MARK: - 备份与恢复（M1.5）
///
/// 本地加密备份的导出与导入：备份文件全程 AES-256-GCM 加密，
/// 密码仅用于本次加解密，灵犀不存储密码、没有云端副本；忘记密码将无法恢复备份。
struct BackupSettingsView: View {
    @EnvironmentObject private var appState: AppState

    // 导出状态
    @AppStorage("lastBackupExportAt") private var lastBackupExportAt: Double = 0
    @State private var exportPassword = ""
    @State private var exportConfirm = ""
    @State private var backupDocument: BackupFile?
    @State private var isExporting = false
    @State private var exportError: String?

    // 导入状态
    @State private var isImporting = false
    @State private var pendingData: Data?
    @State private var pendingPayload: LingxiBackup.Payload?
    @State private var pendingMeta: LingxiBackup.File?
    @State private var importPassword = ""
    @State private var importError: String?
    @State private var showRestoreConfirm = false
    @State private var restoredCount = 0
    @State private var showRestoreSuccess = false

    private static let backupDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt
    }()

    var body: some View {
        Form {
            exportSection
            importSection
        }
        .navigationTitle("备份与恢复")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $isExporting,
            document: backupDocument,
            contentType: .lingxiBackup,
            defaultFilename: defaultExportName()
        ) { result in
            // 导出流程结束后立即清空密码状态，避免残留在内存
            exportPassword = ""
            exportConfirm = ""
            switch result {
            case .success:
                lastBackupExportAt = Date().timeIntervalSince1970
                exportError = nil
            case .failure(let error):
                exportError = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.lingxiBackup],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    loadImportFile(at: url)
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert("恢复备份", isPresented: $showRestoreConfirm) {
            Button("取消", role: .cancel) {}
            Button("恢复并覆盖", role: .destructive) { performRestore() }
        } message: {
            Text("恢复将覆盖当前全部设置、词库、剪贴板与统计数据，且无法撤销。建议先导出一份当前数据的备份。")
        }
        .alert("恢复完成", isPresented: $showRestoreSuccess) {
            Button("好", role: .cancel) {}
        } message: {
            Text("已恢复 \(restoredCount) 份数据文件。键盘扩展将在下次唤起时加载新数据。")
        }
    }

    // MARK: - 导出

    private var exportSection: some View {
        Section {
            SecureField("设置备份密码（至少 8 位）", text: $exportPassword)
            SecureField("再次输入密码确认", text: $exportConfirm)
            Button("生成加密备份文件") { createBackup() }
                .disabled(exportPassword.isEmpty || exportConfirm.isEmpty)
            if let exportError = exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("导出备份")
        } footer: {
            Text("备份内容：设置、主题、AI 配置、剪贴板、自定义短语、快捷短语、常用表情、打字统计与个人词库。文件全程加密（PBKDF2 派生密钥 + AES-256-GCM），可在任意设备的灵犀输入法中导入恢复。")
        }
    }

    private func createBackup() {
        guard exportPassword.count >= 8 else {
            exportError = LingxiBackup.BackupError.weakPassword.localizedDescription
            return
        }
        guard exportPassword == exportConfirm else {
            exportError = "两次输入的密码不一致"
            return
        }
        exportError = nil
        do {
            let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
            let data = try LingxiBackup.createBackupData(
                password: exportPassword,
                lexicon: appState.lexicon,
                appVersion: appVersion
            )
            backupDocument = BackupFile(data: data)
            isExporting = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func defaultExportName() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmm"
        return "灵犀备份-" + fmt.string(from: Date())
    }

    // MARK: - 导入

    private var importSection: some View {
        Section {
            Button("选择备份文件（.lingxibak）") { isImporting = true }
            if let meta = pendingMeta {
                LabeledContent("备份时间", value: Self.backupDateFormatter.string(from: meta.createdAt))
                LabeledContent("备份版本", value: "灵犀 \(meta.appVersion)")
                SecureField("输入该备份的密码", text: $importPassword)
                Button("校验密码并继续") { validatePassword() }
                    .disabled(importPassword.isEmpty)
            }
            if let importError = importError {
                Text(importError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("导入恢复")
        } footer: {
            Text("恢复会覆盖当前全部数据且无法撤销。密码只用于本机解密，灵犀不存储、也无法找回。")
        }
    }

    private func loadImportFile(at url: URL) {
        let gotAccess = url.startAccessingSecurityScopedResource()
        defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard let meta = LingxiBackup.peekMetadata(from: data) else {
                resetImportState()
                importError = LingxiBackup.BackupError.invalidFormat.localizedDescription
                return
            }
            importError = nil
            importPassword = ""
            pendingData = data
            pendingPayload = nil
            pendingMeta = meta
        } catch {
            resetImportState()
            importError = error.localizedDescription
        }
    }

    /// 恢复前先完整解密校验密码，通过后才弹覆盖确认，避免确认后才发现密码错误。
    private func validatePassword() {
        guard let data = pendingData else { return }
        do {
            let payload = try LingxiBackup.decrypt(data: data, password: importPassword)
            importError = nil
            pendingPayload = payload
            showRestoreConfirm = true
        } catch {
            importError = error.localizedDescription
        }
    }

    private func performRestore() {
        guard let payload = pendingPayload else { return }
        do {
            // 必须传入 AppState 共享的同一个 UserLexicon 实例（恢复后重连数据库）
            let count = try LingxiBackup.restoreFiles(payload, lexicon: appState.lexicon)
            // 从磁盘重载全部内存状态，避免 didSet 用旧值回写覆盖恢复的数据
            appState.refreshAll()
            restoredCount = count
            resetImportState()
            showRestoreSuccess = true
        } catch {
            importError = error.localizedDescription
        }
    }

    private func resetImportState() {
        pendingData = nil
        pendingPayload = nil
        pendingMeta = nil
        importPassword = ""
    }
}

// MARK: - 备份文件类型与文档包装

extension UTType {
    /// 灵犀加密备份文件类型（.lingxibak）；exportedAs 为 failable init，异常时兜底通用 data 类型
    static let lingxiBackup = UTType(exportedAs: "com.lingxi.backup", conformingTo: .data) ?? .data
}

/// 供 fileExporter / fileImporter 读写的备份文件包装（内容为已加密字节）。
struct BackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.lingxiBackup] }
    static var writableContentTypes: [UTType] { [.lingxiBackup] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
