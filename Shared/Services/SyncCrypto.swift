import CryptoKit
import Foundation

// MARK: - E2EE 编解码层（M2）
///
/// SyncProtocols.swift 约定：`SyncChange.ciphertext` 由调用方加密，协议层不感知加密细节。
/// 本层是该约定的唯一实现：
/// - 密钥来源：M3 认证完成后由用户凭据材料经 HKDF-SHA256 派生的 256 位对称密钥——
///   服务端（零逻辑只存转发）与任何中间人在数学上拿不到明文（Bitwarden 模式）；
/// - 算法：AES-256-GCM，nonce 每次随机生成，认证标签天然防篡改；
/// - 明文边界：只加密业务 value 字节；命名空间/键/Lamport 时钟/墓碑等元数据
///   走协议层明文字段（合并调度必需，不含用户内容语义）。
public enum SyncCrypto {

    public enum CryptoError: Error, Equatable {
        /// 密封失败（极少见：系统随机源异常）
        case sealFailed
        /// 解密失败：密钥错误或密文被篡改（GCM 认证不通过），统一归类不泄漏细节
        case decryptFailed
    }

    /// HKDF 域分离标识：确保同步密钥与其他用途（如备份）派生结果不同
    private static let hkdfInfo = Data("lingxi-e2ee-sync.v1".utf8)
    private static let hkdfSalt = Data("com.lingxi.sync".utf8)

    /// 从主密钥材料派生同步专用密钥。
    /// - Parameter masterSecret: M3 由认证凭据提供的高熵密钥材料（≥32 字节推荐）
    public static func deriveSyncKey(from masterSecret: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: masterSecret),
            salt: hkdfSalt,
            info: hkdfInfo,
            outputByteCount: 32
        )
    }

    /// 将业务 value 加密为 SyncChange.ciphertext（combined：nonce + 密文 + 认证标签）
    public static func seal(_ value: Data, key: SymmetricKey) throws -> Data {
        guard let combined = try? AES.GCM.seal(value, using: key).combined,
              !combined.isEmpty else {
            throw CryptoError.sealFailed
        }
        return combined
    }

    /// 解密 SyncChange.ciphertext 为业务 value；密钥错误或密文被篡改统一抛 decryptFailed
    public static func open(_ ciphertext: Data, key: SymmetricKey) throws -> Data {
        guard let box = try? AES.GCM.SealedBox(combined: ciphertext),
              let plain = try? AES.GCM.open(box, using: key) else {
            throw CryptoError.decryptFailed
        }
        return plain
    }
}
