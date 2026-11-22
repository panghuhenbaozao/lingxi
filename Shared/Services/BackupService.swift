import CryptoKit
import CommonCrypto
import Foundation

// MARK: - 灵犀本地加密备份（M1.5）
///
/// 设计要点：
/// - 端到端加密：密码经 PBKDF2-HMAC-SHA256（10 万轮 + 32 字节随机盐）派生 AES-256-GCM 密钥；
/// - 备份文件不含任何明文业务数据——仅头部元数据（格式/版本/创建时间）可见，payload 全密文；
/// - GCM 认证标签天然防篡改：密码错误或文件被改动都会在解密时失败；
/// - 备份范围：全部用户数据（设置/主题/AI 配置/剪贴板/自定义短语/快捷短语/常用表情/打字统计 + 个人词库 SQLite）；
/// - 纯本地文件导出导入，不经任何服务器，与「键盘永不联网」铁律一致；
/// - 仅使用 Foundation/CryptoKit/CommonCrypto，可安全编入 App/Keyboard/Tests 三目标。
enum LingxiBackup {

    // MARK: - 错误

    enum BackupError: LocalizedError, Equatable {
        /// 不是有效的灵犀备份文件
        case invalidFormat
        /// 备份文件版本较新
        case unsupportedVersion
        /// 密码错误或文件已损坏（GCM 认证失败统一归为此类，不区分细节）
        case wrongPasswordOrCorrupted
        /// 密码强度不足
        case weakPassword
        /// 没有可备份的数据
        case emptyBackup

        var errorDescription: String? {
            switch self {
            case .invalidFormat: return "不是有效的灵犀备份文件"
            case .unsupportedVersion: return "备份文件版本较新，请先升级灵犀输入法"
            case .wrongPasswordOrCorrupted: return "密码错误，或备份文件已损坏"
            case .weakPassword: return "密码至少 8 位"
            case .emptyBackup: return "没有可备份的数据"
            }
        }
    }

    // MARK: - 常量

    /// 参与备份的 App Group JSON 数据文件
    static let jsonFileNames = [
        "lingxi_settings.json",
        "lingxi_theme.json",
        "lingxi_ai_config.json",
        "lingxi_clipboard.json",
        "lingxi_custom_words.json",
        "lingxi_phrases.json",
        "lingxi_recent_emojis.json",
        "typing_stats.json"
    ]

    /// 个人词库（SQLite，WAL 模式，备份前需 checkpoint 合并日志）
    static let sqliteFileName = "user_dict.sqlite"

    /// 备份文件扩展名
    static let fileExtension = "lingxibak"

    static let currentSchemaVersion = 1

    /// PBKDF2 迭代轮数（OWASP 2023 对 PBKDF2-SHA256 的推荐量级）
    static let kdfRounds = 100_000

    /// 文件格式标识（明文头部校验用）
    private static let magic = "LINGXI-BACKUP"

    // MARK: - 数据模型

    /// 备份文件外层（明文可读）：仅元数据，无业务内容
    struct File: Codable {
        var format: String
        var schemaVersion: Int
        var kdf: String
        var kdfRounds: Int
        var salt: Data
        var createdAt: Date
        var appVersion: String
        /// AES-256-GCM sealed box（combined：nonce + 密文 + 认证标签）
        var payload: Data
    }

    /// 备份内层（密文内容）：文件名 → 文件字节
    struct Payload: Codable, Equatable {
        var schemaVersion: Int
        var createdAt: Date
        var files: [String: Data]
    }

    // MARK: - 加密层（核心语义，供单元测试直接覆盖）

    /// 将 payload 加密为完整备份文件字节。
    /// 密码不落盘不存储，盐与 nonce 每次随机生成。
    static func encrypt(password: String, payload: Payload,
                        appVersion: String = "test", now: Date = Date()) throws -> Data {
        guard password.count >= 8 else { throw BackupError.weakPassword }

        // 32 字节随机盐（SymmetricKey 生成走系统安全随机源）
        let salt = Data(SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
        let key = deriveKey(password: password, salt: salt)
        // 内层与外层统一 iso8601 日期策略，保证 encrypt/decrypt 严格对称
        let payloadEncoder = JSONEncoder()
        payloadEncoder.dateEncodingStrategy = .iso8601
        let plain = try payloadEncoder.encode(payload)
        let box = try AES.GCM.seal(plain, using: key)
        guard let combined = box.combined else { throw BackupError.invalidFormat }

        let file = File(
            format: magic,
            schemaVersion: currentSchemaVersion,
            kdf: "PBKDF2-HMAC-SHA256",
            kdfRounds: kdfRounds,
            salt: salt,
            createdAt: now,
            appVersion: appVersion,
            payload: combined
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(file)
    }

    /// 解密备份文件字节为 payload。
    /// 格式错误/密码错误/文件损坏分别归类，不泄漏内部细节。
    static func decrypt(data: Data, password: String) throws -> Payload {
        guard let file = peekMetadata(from: data) else { throw BackupError.invalidFormat }
        guard file.schemaVersion <= currentSchemaVersion else { throw BackupError.unsupportedVersion }

        let key = deriveKey(password: password, salt: file.salt, rounds: file.kdfRounds)
        guard let box = try? AES.GCM.SealedBox(combined: file.payload),
              let plain = try? AES.GCM.open(box, using: key) else {
            throw BackupError.wrongPasswordOrCorrupted
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: plain) else {
            throw BackupError.wrongPasswordOrCorrupted
        }
        return payload
    }

    /// 读取明文头部元数据（不解密 payload），用于恢复前展示创建时间与版本。
    static func peekMetadata(from data: Data) -> File? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(File.self, from: data), file.format == magic else {
            return nil
        }
        return file
    }

    /// PBKDF2-HMAC-SHA256 派生 256 位密钥
    private static func deriveKey(password: String, salt: Data, rounds: Int = kdfRounds) -> SymmetricKey {
        var derived = [UInt8](repeating: 0, count: Int(kCCKeySizeAES256))
        let saltBytes = Array(salt)
        password.withCString { pwd in
            saltBytes.withUnsafeBufferPointer { saltBuf in
                _ = CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pwd,
                    Int(strlen(pwd)),
                    saltBuf.baseAddress,
                    saltBytes.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(rounds),
                    &derived,
                    derived.count
                )
            }
        }
        return SymmetricKey(data: derived)
    }

    // MARK: - 文件编排（App 侧使用）

    /// 收集当前全部用户数据并生成加密备份。
    /// SQLite 先 checkpoint 保证 WAL 日志合并，读出完整最新状态。
    static func createBackupData(password: String, lexicon: UserLexicon, appVersion: String) throws -> Data {
        lexicon.checkpointForBackup()

        var files: [String: Data] = [:]
        for name in jsonFileNames {
            let url = AppGroup.fileURL(name)
            if let data = try? Data(contentsOf: url), !data.isEmpty {
                files[name] = data
            }
        }
        let sqliteURL = AppGroup.fileURL(sqliteFileName)
        if let data = try? Data(contentsOf: sqliteURL), !data.isEmpty {
            files[sqliteFileName] = data
        }
        guard !files.isEmpty else { throw BackupError.emptyBackup }

        let payload = Payload(schemaVersion: currentSchemaVersion, createdAt: Date(), files: files)
        return try encrypt(password: password, payload: payload, appVersion: appVersion)
    }

    /// 将备份内容写回 App Group 并重载词库连接；返回恢复的文件数。
    /// 注意：必须传入 AppState 共享的同一个 UserLexicon 实例，
    /// 否则内存中的旧 SQLite 连接仍指向旧文件。
    @discardableResult
    static func restoreFiles(_ payload: Payload, lexicon: UserLexicon) throws -> Int {
        var restored = 0
        for (name, data) in payload.files {
            if name == sqliteFileName {
                try lexicon.restore(data: data)
            } else {
                try data.write(to: AppGroup.fileURL(name), options: [.atomic])
            }
            restored += 1
        }
        return restored
    }
}
