import CryptoKit
import Foundation
import Security

/// 本地加密：AES-GCM 加密剪贴内容，密钥保存在登录钥匙串里。
enum Vault {
    private static let service = "com.luojilab.clipkeep"
    private static let account = "database-key"

    /// 启动时加载；nil 表示钥匙串读取失败（比如用户拒绝了访问）。
    static let key: SymmetricKey? = loadOrCreateKey()

    static var ready: Bool { key != nil }

    static func seal(_ data: Data) -> Data {
        guard let key, let box = try? AES.GCM.seal(data, using: key) else { return Data() }
        return box.combined ?? Data()
    }

    static func open(_ data: Data) -> Data? {
        guard let key, let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    /// 用于去重的指纹：带密钥的 HMAC，数据库被拿走也没法用来反查内容。
    static func fingerprint(_ data: Data) -> String {
        guard let key else { return UUID().uuidString }
        return HMAC<SHA256>.authenticationCode(for: data, using: key)
            .map { String(format: "%02x", $0) }.joined()
    }

    private static func loadOrCreateKey() -> SymmetricKey? {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        var query = base
        query[kSecReturnData as String] = true
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecSuccess, let data = out as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else { return nil }

        let key = SymmetricKey(size: .bits256)
        var add = base
        add[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecAttrLabel as String] = "ClipKeep 数据库密钥"
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { return nil }
        return key
    }
}
