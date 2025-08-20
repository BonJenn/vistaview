//
//  AuthenticationManager.swift
//  Vantaview
//
//  Created by Vantaview on 12/19/24.
//

import Foundation
import Combine
import AppKit

@MainActor
class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var accessToken: String?
    @Published var userID: String?
    @Published var currentUser: VantaviewUser?
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Try to restore session on app launch
        restoreSession()
    }
    
    // MARK: - Google OAuth Sign In
    
    func signInWithGoogle() async throws {
        guard OAuthConfig.isGoogleConfigured else {
            throw AuthError.configurationError("Google OAuth not configured")
        }
        
        // Step 1: Open browser for OAuth
        let authURL = try buildGoogleAuthURL()
        
        // Open the URL in default browser
        if let url = URL(string: authURL), 
           await NSWorkspace.shared.open(url) {
            
            // Step 2: Wait for callback (this is a simplified version)
            // In a real implementation, you'd set up URL scheme handling
            // For now, we'll simulate the flow
            
            // TODO: Implement proper OAuth callback handling
            throw AuthError.notImplemented("OAuth callback handling not yet implemented")
            
        } else {
            throw AuthError.browserError("Could not open authentication URL")
        }
    }
    
    private func buildGoogleAuthURL() throws -> String {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        
        // Generate state for security
        let state = UUID().uuidString
        
        components.queryItems = [
            URLQueryItem(name: "client_id", value: OAuthConfig.googleClientId),
            URLQueryItem(name: "redirect_uri", value: OAuthConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: OAuthConfig.googleScopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        
        guard let url = components.url?.absoluteString else {
            throw AuthError.urlGenerationError("Could not generate auth URL")
        }
        
        return url
    }
    
    // MARK: - Manual Token Entry (for testing)
    
    func signInWithToken(_ token: String, userID: String) async {
        self.accessToken = token
        self.userID = userID
        self.isAuthenticated = true
        
        // Save to keychain
        saveSession()
        
        // Fetch user info
        await fetchUserInfo()
    }
    
    // MARK: - Session Management
    
    private func saveSession() {
        guard let token = accessToken, let userID = userID else { return }
        
        let sessionData = SessionData(accessToken: token, userID: userID)
        
        do {
            let data = try JSONEncoder().encode(sessionData)
            let status = SecItemAdd([
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: "app.vantaview.session",
                kSecAttrAccount: "current_user",
                kSecValueData: data
            ] as CFDictionary, nil)
            
            if status != errSecSuccess && status != errSecDuplicateItem {
                print("Failed to save session to keychain: \(status)")
            }
        } catch {
            print("Failed to encode session data: \(error)")
        }
    }
    
    private func restoreSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.vantaview.session",
            kSecAttrAccount as String: "current_user",
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess,
           let data = dataTypeRef as? Data,
           let sessionData = try? JSONDecoder().decode(SessionData.self, from: data) {
            
            self.accessToken = sessionData.accessToken
            self.userID = sessionData.userID
            self.isAuthenticated = true
            
            // Fetch fresh user info
            Task {
                await fetchUserInfo()
            }
        }
    }
    
    private func clearSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.vantaview.session",
            kSecAttrAccount as String: "current_user"
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - User Info
    
    private func fetchUserInfo() async {
        // TODO: Fetch user info from your API
        // For now, create a basic user object
        currentUser = VantaviewUser(
            id: userID ?? "",
            email: "user@example.com", // TODO: Get from API
            name: "User Name" // TODO: Get from API
        )
    }
    
    // MARK: - Sign Out
    
    func signOut() async {
        self.isAuthenticated = false
        self.accessToken = nil
        self.userID = nil
        self.currentUser = nil
        
        clearSession()
    }
}

// MARK: - Models

struct SessionData: Codable {
    let accessToken: String
    let userID: String
}

struct VantaviewUser: Codable {
    let id: String
    let email: String
    let name: String
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case configurationError(String)
    case browserError(String)
    case urlGenerationError(String)
    case notImplemented(String)
    
    var errorDescription: String? {
        switch self {
        case .configurationError(let message):
            return "Configuration Error: \(message)"
        case .browserError(let message):
            return "Browser Error: \(message)"
        case .urlGenerationError(let message):
            return "URL Error: \(message)"
        case .notImplemented(let message):
            return "Not Implemented: \(message)"
        }
    }
}

// MARK: - OAuth Integration

// This should match your Google OAuth setup from vantaview-landing
extension AuthenticationManager {
    func handleOAuthCallback(url: URL) async throws {
        // Extract authorization code from callback URL
        let redirectURI = "https://vantaview.app/auth/callback"
        
        // TODO: Implement OAuth callback parsing and token exchange
        // This would parse the callback URL, extract the auth code,
        // exchange it for tokens, and complete the sign-in process
        
        throw AuthError.notImplemented("OAuth callback handling needs implementation")
    }
}

extension AuthenticationManager {
    /// Sign in with a session token (for development/testing)
    func debugSignIn(sessionToken: String = "debug_session_token") {
        Task {
            await signInWithToken(sessionToken, userID: "debug_user_123")
        }
    }
}

// MARK: - Keychain Query Extensions

extension AuthenticationManager {
    private func keychainQuery() -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.vantaview.session",
            kSecAttrAccount as String: "current_user"
        ]
    }
    
    private func updateKeychainItem(_ data: Data) {
        let query = keychainQuery()
        let updateQuery: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, updateQuery as CFDictionary)
        if status != errSecSuccess {
            print("Failed to update keychain item: \(status)")
        }
    }
}

// MARK: - User Management

extension AuthenticationManager {
    /// Update current user information
    func updateUser(_ user: VantaviewUser) {
        self.currentUser = user
    }
    
    /// Check if user has valid session
    var hasValidSession: Bool {
        return isAuthenticated && accessToken != nil && userID != nil
    }
}