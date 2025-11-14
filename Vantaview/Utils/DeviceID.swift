import Foundation
import AppKit
import Security

enum DeviceID {
    private static let service = "app.vantaview.device"
    private static let account = "device_id"
    private static let installedTrackedAccount = "installed_tracked"

    static func deviceID() -> String {
        if let existing = readKeychain(account: account) {
            return existing
        }
        let id = UUID().uuidString
        _ = writeKeychain(account: account, value: id)
        return id
    }

    static func deviceName() -> String {
        Host.current().localizedName ?? "Mac"
    }

    static func markInstalledTracked() {
        _ = writeKeychain(account: installedTrackedAccount, value: "1")
    }

    static func isInstalledTracked() -> Bool {
        readKeychain(account: installedTrackedAccount) == "1"
    }

    private static func readKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(account: String, value: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        return status == errSecSuccess
    }
}