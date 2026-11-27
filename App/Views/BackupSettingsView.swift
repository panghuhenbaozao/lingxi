import SwiftUI
import UniformTypeIdentifiers

// MARK: - 备份与恢复（v6）
///
/// 本地加密备份的导出与导入：备份文件全程 AES-256-GCM 加密，
/// 密码仅用于本次加解密，灵犀不存储密码、没有云端副本；忘记密码将无法恢复备份。
struct BackupSettingsView: View {
    @EnvironmentObject private var appState: AppState

    // 导出状态
    @AppStorage("lastBackupExportAt") private var lastBackupExportAt: Double = 0
    @State private var exportPassword = ""
    @State private var exportConfirm = ""
    @State private var revealExportPassword = false
    @State private var backupDocument: BackupFile?
    @State private var isExporting = false
    @State private var isPreparingExport = false
    @State private var exportError: String?

    // 导入状态
    @State private var isImporting = false
    @State private var pendingData: Data?
    @State private var pendingPayload: LingxiBackup.Payload?
    @State private var pendingMeta: LingxiBackup.File?
    @State private var pendingFileName: String = ""
    @State private var importPassword = ""
    @State private var isValidating = false
    @State private var importError: String?
    @State private var showRestoreConfirm = false
    @State private var restoredCount = 0
    @State private var showRestoreSuccess = false
    @State private var toast: String?

    private static let minPasswordLength = 8

    private static let backupDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt
    }()

    // MARK: 密码校验

    private var passwordTooShort: Bool {
        !exportPassword.isEmpty && exportPassword.count < Self.minPasswordLength
    }

    private var passwordMismatch: Bool {
        !exportConfirm.isEmpty && exportConfirm != exportPassword
    }

    private var canExport: Bool {
        exportPassword.count >= Self.minPasswordLength && exportPassword == exportConfirm && !isPreparingExport
    }

    /// 简单强度估计：长度 + 字符种类
    private var passwordStrength: (level: Int, label: String) {
        let p = exportPassword
        guard !p.isEmpty else { return (0, "") }
        var kinds = 0
        if p.rangeOfCharacter(from: .lowercaseLetters) != nil { kinds += 1 }
        if p.rangeOfCharacter(from: .uppercaseLetters) != nil { kinds += 1 }
        if p.rangeOfCharacter(from: .decimalDigits) != nil { kinds += 1 }
        if p.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil { kinds += 1 }
        if p.count < Self.minPasswordLength { return (1, "太短") }
        if p.count >= 12 && kinds >= 3 { return (3, "强") }
        if kinds >= 2 { return (2, "中") }
        return (1, "弱")
    }

    private var lastBackupText: String {
        guard lastBackupExportAt > 0 else { return "从未备份" }
        let date = Date(timeIntervalSince1970: lastBackupExportAt)
        return "上次备份 " + date.formatted(.relative(presentation: .named))
    }

    var body: some View {
        Form {
            statusSection
            exportSection
            importSection
            contentSection
        }
        .navigationTitle("备份与恢复")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($toast)
        .fileExporter(
            isPresented: $isExporting,
            document: backupDocument,
            contentType: .lingxiBackup,
            defaultFilename: defaultExportName()
        ) { result in
            // 导出流程结束后立即清空密码与备份数据，避免残留在内存
            exportPassword = ""
            exportConfirm = ""
            backupDocument = nil
            switch result {
            case .success:
                lastBackupExportAt = Date().timeIntervalSince1970
                exportError = nil
                toast = "备份已保存"
            case .failure(let error):
                if Self.isUserCancelled(error) {
                    toast = "已取消保存"
                } else {
                    exportError = error.localizedDescription
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.lingxiBackup, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    loadImportFile(at: url)
                }
            case .failure(let error):
                if !Self.isUserCancelled(error) {
                    importError = error.localizedDescription
                }
            }
        }
        .alert("用这份备份覆盖当前数据？", isPresented: $showRestoreConfirm) {
            Button("取消", role: .cancel) {}
            Button("恢复并覆盖", role: .destructive) { performRestore() }
        } message: {
            if let meta = pendingMeta {
                Text("将用 \(Self.backupDateFormatter.string(from: meta.createdAt)) 的备份覆盖当前全部设置、词库、剪贴板和统计数据，无法撤销。建议先导出一份当前数据。")
            } else {
                Text("当前全部设置、词库、剪贴板和统计数据会被覆盖，无法撤销。")
            }
        }
        .alert("恢复完成", isPresented: $showRestoreSuccess) {
            Button("好", role: .cancel) {}
        } message: {
            Text("已恢复 \(restoredCount) 份数据。下次切到灵犀键盘时会自动加载。")
        }
    }

    // MARK: - 状态

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                LXIconTile(
                    icon: lastBackupExportAt > 0 ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                    tint: lastBackupExportAt > 0 ? Color(Design.Palette.success) : Color(Design.Palette.warning),
                    size: 42
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(lastBackupText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                    Text(lastBackupExportAt > 0
                         ? "换手机或重装前，建议再导出一份最新的备份。"
                         : "免费侧载的 App 过期或被删除时数据会丢失，建议定期备份。")
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 导出

    private var exportSection: some View {
        Section {
            passwordField("设置备份密码（至少 8 位）", text: $exportPassword, reveal: revealExportPassword)
            passwordField("再输入一次", text: $exportConfirm, reveal: revealExportPassword)

            if !exportPassword.isEmpty {
                strengthRow
            }

            Toggle("显示密码", isOn: $revealExportPassword)
                .tint(Color(Design.Palette.accent))

            Button {
                createBackup()
            } label: {
                HStack(spacing: 6) {
                    if isPreparingExport {
                        ProgressView().controlSize(.small).tint(Color.white)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                    Text(isPreparingExport ? "正在加密…" : "生成并保存备份文件")
                }
            }
            .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
            .disabled(!canExport)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

            if let exportError {
                errorText(exportError)
            }
        } header: {
            Text("导出备份")
        } footer: {
            if passwordMismatch {
                Text("两次输入的密码不一致。")
                    .foregroundStyle(Color(Design.Palette.error))
            } else if passwordTooShort {
                Text("密码至少 \(Self.minPasswordLength) 位。")
                    .foregroundStyle(Color(Design.Palette.error))
            } else {
                Text("请牢记这个密码：灵犀不保存密码，也没有找回方式，忘记后备份将无法打开。")
            }
        }
    }

    private var strengthRow: some View {
        let s = passwordStrength
        let color: Color = s.level >= 3 ? Color(Design.Palette.success) : (s.level == 2 ? Color(Design.Palette.accent) : Color(Design.Palette.warning))
        return HStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(1...3, id: \.self) { i in
                    Capsule()
                        .fill(i <= s.level ? color : Color(Design.Palette.hairline))
                        .frame(height: 5)
                }
            }
            Text("强度：\(s.label)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 64, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("密码强度：\(s.label)")
    }

    private func passwordField(_ placeholder: String, text: Binding<String>, reveal: Bool) -> some View {
        Group {
            if reveal {
                TextField(placeholder, text: text)
            } else {
                SecureField(placeholder, text: text)
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }

    private func errorText(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Color(Design.Palette.error))
                .padding(.top, 1)
            Text(message)
                .font(.caption)
                .foregroundStyle(Color(Design.Palette.error))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func createBackup() {
        guard exportPassword.count >= Self.minPasswordLength else {
            exportError = LingxiBackup.BackupError.weakPassword.localizedDescription
            return
        }
        guard exportPassword == exportConfirm else {
            exportError = "两次输入的密码不一致"
            return
        }
        exportError = nil
        isPreparingExport = true
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        // 词库打包需要与 AppState 共用同一个 UserLexicon 实例，保持在主线程执行；
        // 先让出一帧把「正在加密…」画出来，再做 PBKDF2 与打包
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            do {
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
            isPreparingExport = false
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
            Button {
                importError = nil
                isImporting = true
            } label: {
                Label(pendingMeta == nil ? "选择备份文件" : "换一个文件", systemImage: "doc.badge.arrow.up")
                    .frame(minHeight: 36)
            }

            if let meta = pendingMeta {
                if !pendingFileName.isEmpty {
                    LabeledContent("文件", value: pendingFileName)
                }
                LabeledContent("备份时间", value: Self.backupDateFormatter.string(from: meta.createdAt))
                LabeledContent("来自版本", value: "灵犀 \(meta.appVersion)")
                SecureField("输入这份备份的密码", text: $importPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { validatePassword() }
                Button {
                    validatePassword()
                } label: {
                    HStack(spacing: 6) {
                        if isValidating {
                            ProgressView().controlSize(.small).tint(Color.white)
                        } else {
                            Image(systemName: "lock.open")
                        }
                        Text(isValidating ? "正在验证…" : "验证密码并恢复")
                    }
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                .disabled(importPassword.isEmpty || isValidating)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }

            if let importError {
                errorText(importError)
            }
        } header: {
            Text("从备份恢复")
        } footer: {
            Text("会先验证密码，确认无误后再询问是否覆盖，不会误删数据。")
        }
    }

    private var contentSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                contentRow(icon: "checkmark.circle.fill", tint: Color(Design.Palette.success), text: "设置、皮肤配色、AI 智脑配置（含 API 密钥、文风 DNA、多话题对话与用量历史）")
                contentRow(icon: "checkmark.circle.fill", tint: Color(Design.Palette.success), text: "个人词库、自定义短语、快捷短语、常用表情")
                contentRow(icon: "checkmark.circle.fill", tint: Color(Design.Palette.success), text: "剪贴板记录、打字统计与习惯、触控校准、跨屏接力设置")
                contentRow(icon: "minus.circle.fill", tint: Color(Design.Palette.stone), text: "不包含：本地保险箱、键盘壁纸图片")
            }
            .padding(.vertical, 4)
        } header: {
            Text("备份里有什么")
        } footer: {
            Text("文件用 PBKDF2 派生密钥、AES-256-GCM 加密，可以在任意设备上的灵犀输入法里恢复。")
        }
    }

    private func contentRow(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
                .padding(.top, 2)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Color(Design.Palette.charcoal))
                .fixedSize(horizontal: false, vertical: true)
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
            pendingFileName = url.lastPathComponent
        } catch {
            resetImportState()
            importError = error.localizedDescription
        }
    }

    /// 恢复前先完整解密校验密码，通过后才弹覆盖确认，避免确认后才发现密码错误。
    private func validatePassword() {
        guard let data = pendingData, !importPassword.isEmpty, !isValidating else { return }
        isValidating = true
        importError = nil
        // 先让出一帧把「正在验证…」画出来，再做 PBKDF2 解密校验
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            do {
                let payload = try LingxiBackup.decrypt(data: data, password: importPassword)
                pendingPayload = payload
                showRestoreConfirm = true
            } catch {
                importError = error.localizedDescription
            }
            isValidating = false
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
        pendingFileName = ""
        importPassword = ""
    }

    /// 用户在文件面板点了「取消」时不当作错误显示
    private static func isUserCancelled(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError
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
