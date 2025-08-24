//
//  KeychainHelper.swift
//  Vantaview
//
//  Created by Vantaview on 12/19/24.
//

import Foundation
import Security

/// Helper for storing and retrieving license data from Keychain
struct KeychainHelper {
    
    /// Store cached license in Keychain
    static func storeCachedLicense(_ license: CachedLicense, for userID: String) -> Bool {
        guard let data = try? JSONEncoder().encode(license) else {
            return false
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: LicenseConstants.keychainService,
            kSecAttrAccount as String: "\(LicenseConstants.keychainAccount)_\(userID)",
            kSecValueData as String: data
        ]
        
        // Delete existing entry first
        SecItemDelete(query as CFDictionary)
        
        // Add new entry
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if LicenseConstants.debugLoggingEnabled {
            print("🔐 Keychain: Store cached license result: \(status)")
        }
        
        return status == errSecSuccess
    }
    
    /// Retrieve cached license from Keychain
    static func getCachedLicense(for userID: String) -> CachedLicense? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: LicenseConstants.keychainService,
            kSecAttrAccount as String: "\(LicenseConstants.keychainAccount)_\(userID)",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if LicenseConstants.debugLoggingEnabled {
            print("🔐 Keychain: Get cached license result: \(status)")
        }
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let license = try? JSONDecoder().decode(CachedLicense.self, from: data) else {
            return nil
        }
        
        return license
    }
    
    /// Delete cached license from Keychain
    static func deleteCachedLicense(for userID: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: LicenseConstants.keychainService,
            kSecAttrAccount as String: "\(LicenseConstants.keychainAccount)_\(userID)"
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if LicenseConstants.debugLoggingEnabled {
            print("🔐 Keychain: Delete cached license result: \(status)")
        }
        
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    /// Clear all cached licenses (useful for debugging or account switching)
    static func clearAllCachedLicenses() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: LicenseConstants.keychainService
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if LicenseConstants.debugLoggingEnabled {
            print("🔐 Keychain: Clear all cached licenses result: \(status)")
        }
        
        return status == errSecSuccess || status == errSecItemNotFound
    }
}