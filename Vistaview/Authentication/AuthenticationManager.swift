//
//  AuthenticationManager.swift
//  Vistaview
//
//  Created by Vistaview on 12/19/24.
//

import Foundation
import SwiftUI

/// Manages Supabase authentication and user session
@MainActor
final class AuthenticationManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isAuthenticated = false
    @Published var currentUser: VistaviewUser?
    @Published var isLoading = false
    @Published var authError: AuthError?
    
    // MARK: - Debug Properties
    
    #if DEBUG
    @Published var debugMode = true // Enable debug mode for testing
    #else
    @Published var debugMode = false
    #endif
    
    // MARK: - Private Properties
    
    private var sessionToken: String?
    private var refreshToken: String?
    
    // MARK: - Computed Properties
    
    var userID: String? {
        return currentUser?.id
    }
    
    var accessToken: String? {
        return sessionToken
    }
    
    // MARK: - Initialization
    
    init() {
        // Load persisted session on app start
        loadPersistedSession()
    }
    
    // MARK: - Public Methods
    
    /// Sign in with email and password
    func signIn(email: String, password: String) async {
        isLoading = true
        authError = nil
        
        defer { isLoading = false }
        
        #if DEBUG
        // Debug mode bypass
        if debugMode {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // Simulate network delay
            await handleDebugSignIn(email: email)
            return
        }
        #endif
        
        guard SupabaseConfig.isConfigured else {
            authError = .configurationError("Supabase not configured")
            return
        }
        
        do {
            let authResponse = try await performSignIn(email: email, password: password)
            await handleAuthenticationSuccess(authResponse)
            
        } catch {
            authError = AuthError.from(error)
            if LicenseConstants.debugLoggingEnabled {
                print("🔐 Auth: Sign in failed - \(error)")
            }
        }
    }
    
    /// Sign up with email and password
    func signUp(email: String, password: String) async {
        isLoading = true
        authError = nil
        
        defer { isLoading = false }
        
        #if DEBUG
        // Debug mode bypass
        if debugMode {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // Simulate network delay
            await handleDebugSignIn(email: email)
            return
        }
        #endif
        
        guard SupabaseConfig.isConfigured else {
            authError = .configurationError("Supabase not configured")
            return
        }
        
        do {
            let authResponse = try await performSignUp(email: email, password: password)
            await handleAuthenticationSuccess(authResponse)
            
        } catch {
            authError = AuthError.from(error)
            if LicenseConstants.debugLoggingEnabled {
                print("🔐 Auth: Sign up failed - \(error)")
            }
        }
    }
    
    /// Sign out current user
    func signOut() async {
        isLoading = true
        
        defer { isLoading = false }
        
        do {
            try await performSignOut()
            await handleSignOut()
            
        } catch {
            if LicenseConstants.debugLoggingEnabled {
                print("🔐 Auth: Sign out error - \(error)")
            }
            // Even if server sign-out fails, clear local session
            await handleSignOut()
        }
    }
    
    /// Refresh the current session
    func refreshSession() async -> Bool {
        guard let refreshToken = refreshToken else {
            await handleSignOut()
            return false
        }
        
        do {
            let authResponse = try await performRefreshToken(refreshToken)
            await handleAuthenticationSuccess(authResponse)
            return true
            
        } catch {
            if LicenseConstants.debugLoggingEnabled {
                print("🔐 Auth: Token refresh failed - \(error)")
            }
            await handleSignOut()
            return false
        }
    }
    
    // MARK: - Private Methods - Network Calls
    
    private func performSignIn(email: String, password: String) async throws -> AuthResponse {
        // Simulate Supabase auth API call
        // TODO: Replace with actual Supabase SDK calls
        
        let url = SupabaseConfig.projectURL.appendingPathComponent("auth/v1/token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        
        let body = [
            "email": email,
            "password": password,
            "grant_type": "password"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError("Invalid response")
        }
        
        if httpResponse.statusCode == 200 {
            return try JSONDecoder().decode(AuthResponse.self, from: data)
        } else {
            let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = errorData?["error_description"] as? String ?? "Authentication failed"
            throw AuthError.authenticationFailed(message)
        }
    }
    
    private func performSignUp(email: String, password: String) async throws -> AuthResponse {
        // Simulate Supabase auth API call
        // TODO: Replace with actual Supabase SDK calls
        
        let url = SupabaseConfig.projectURL.appendingPathComponent("auth/v1/signup")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        
        let body = [
            "email": email,
            "password": password
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError("Invalid response")
        }
        
        if httpResponse.statusCode == 200 {
            return try JSONDecoder().decode(AuthResponse.self, from: data)
        } else {
            let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = errorData?["error_description"] as? String ?? "Sign up failed"
            throw AuthError.registrationFailed(message)
        }
    }
    
    private func performSignOut() async throws {
        guard let token = sessionToken else { return }
        
        let url = SupabaseConfig.projectURL.appendingPathComponent("auth/v1/logout")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 204 else {
            throw AuthError.networkError("Sign out failed")
        }
    }
    
    private func performRefreshToken(_ refreshToken: String) async throws -> AuthResponse {
        let url = SupabaseConfig.projectURL.appendingPathComponent("auth/v1/token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        
        let body = [
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError("Invalid response")
        }
        
        if httpResponse.statusCode == 200 {
            return try JSONDecoder().decode(AuthResponse.self, from: data)
        } else {
            throw AuthError.tokenRefreshFailed("Token refresh failed")
        }
    }
    
    // MARK: - Private Methods - Session Management
    
    private func handleAuthenticationSuccess(_ authResponse: AuthResponse) async {
        sessionToken = authResponse.accessToken
        refreshToken = authResponse.refreshToken
        
        currentUser = VistaviewUser(
            id: authResponse.user.id,
            email: authResponse.user.email,
            emailConfirmed: authResponse.user.emailConfirmedAt != nil,
            createdAt: authResponse.user.createdAt,
            lastSignInAt: authResponse.user.lastSignInAt
        )
        
        isAuthenticated = true
        authError = nil
        
        // Persist session
        persistSession(authResponse)
        
        if LicenseConstants.debugLoggingEnabled {
            print("🔐 Auth: Authentication successful for user: \(currentUser?.email ?? "unknown")")
        }
    }
    
    private func handleSignOut() async {
        sessionToken = nil
        refreshToken = nil
        currentUser = nil
        isAuthenticated = false
        authError = nil
        
        // Clear persisted session
        clearPersistedSession()
        
        if LicenseConstants.debugLoggingEnabled {
            print("🔐 Auth: User signed out")
        }
    }
    
    // MARK: - Session Persistence
    
    private func persistSession(_ authResponse: AuthResponse) {
        let sessionData = PersistedSession(
            accessToken: authResponse.accessToken,
            refreshToken: authResponse.refreshToken,
            user: authResponse.user,
            expiresAt: authResponse.expiresAt
        )
        
        if let data = try? JSONEncoder().encode(sessionData) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "app.vistaview.session",
                kSecAttrAccount as String: "current_session",
                kSecValueData as String: data
            ]
            
            // Delete existing
            SecItemDelete(query as CFDictionary)
            
            // Add new
            SecItemAdd(query as CFDictionary, nil)
        }
    }
    
    private func loadPersistedSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.vistaview.session",
            kSecAttrAccount as String: "current_session",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let sessionData = try? JSONDecoder().decode(PersistedSession.self, from: data) else {
            return
        }
        
        // Check if session is still valid
        if sessionData.expiresAt > Date() {
            sessionToken = sessionData.accessToken
            refreshToken = sessionData.refreshToken
            currentUser = VistaviewUser(
                id: sessionData.user.id,
                email: sessionData.user.email,
                emailConfirmed: sessionData.user.emailConfirmedAt != nil,
                createdAt: sessionData.user.createdAt,
                lastSignInAt: sessionData.user.lastSignInAt
            )
            isAuthenticated = true
            
            if LicenseConstants.debugLoggingEnabled {
                print("🔐 Auth: Restored persisted session for: \(currentUser?.email ?? "unknown")")
            }
        } else {
            // Session expired, try to refresh
            Task {
                _ = await refreshSession()
            }
        }
    }
    
    private func clearPersistedSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.vistaview.session",
            kSecAttrAccount as String: "current_session"
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    #if DEBUG
    /// Debug sign in that bypasses real authentication
    private func handleDebugSignIn(email: String) async {
        let debugUser = VistaviewUser(
            id: "debug-user-\(UUID().uuidString)",
            email: email,
            emailConfirmed: true,
            createdAt: Date(),
            lastSignInAt: Date()
        )
        
        currentUser = debugUser
        isAuthenticated = true
        authError = nil
        
        // Create a mock session token for license verification
        sessionToken = "debug-session-token-\(UUID().uuidString)"
        refreshToken = "debug-refresh-token"
        
        if LicenseConstants.debugLoggingEnabled {
            print("🔐 Auth: Debug authentication successful for: \(email)")
        }
    }
    #endif
}

// MARK: - Supporting Types

struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let user: SupabaseUser
    let expiresAt: Date
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
        case expiresAt = "expires_at"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decode(String.self, forKey: .refreshToken)
        user = try container.decode(SupabaseUser.self, forKey: .user)
        
        // Handle expires_at as timestamp or date string
        if let timestamp = try? container.decode(TimeInterval.self, forKey: .expiresAt) {
            expiresAt = Date(timeIntervalSince1970: timestamp)
        } else if let dateString = try? container.decode(String.self, forKey: .expiresAt) {
            let formatter = ISO8601DateFormatter()
            expiresAt = formatter.date(from: dateString) ?? Date().addingTimeInterval(3600)
        } else {
            expiresAt = Date().addingTimeInterval(3600) // Default 1 hour
        }
    }
}

struct SupabaseUser: Codable {
    let id: String
    let email: String
    let emailConfirmedAt: Date?
    let createdAt: Date
    let lastSignInAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case emailConfirmedAt = "email_confirmed_at"
        case createdAt = "created_at"
        case lastSignInAt = "last_sign_in_at"
    }
}

struct VistaviewUser {
    let id: String
    let email: String
    let emailConfirmed: Bool
    let createdAt: Date
    let lastSignInAt: Date?
}

struct PersistedSession: Codable {
    let accessToken: String
    let refreshToken: String
    let user: SupabaseUser
    let expiresAt: Date
}

enum AuthError: LocalizedError {
    case configurationError(String)
    case networkError(String)
    case authenticationFailed(String)
    case registrationFailed(String)
    case tokenRefreshFailed(String)
    case invalidCredentials
    case emailNotConfirmed
    case userNotFound
    
    var errorDescription: String? {
        switch self {
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .registrationFailed(let message):
            return "Registration failed: \(message)"
        case .tokenRefreshFailed(let message):
            return "Token refresh failed: \(message)"
        case .invalidCredentials:
            return "Invalid email or password"
        case .emailNotConfirmed:
            return "Please check your email and confirm your account"
        case .userNotFound:
            return "User account not found"
        }
    }
    
    static func from(_ error: Error) -> AuthError {
        if let authError = error as? AuthError {
            return authError
        }
        
        let errorString = error.localizedDescription.lowercased()
        
        if errorString.contains("invalid") && errorString.contains("password") {
            return .invalidCredentials
        } else if errorString.contains("email") && errorString.contains("confirm") {
            return .emailNotConfirmed
        } else if errorString.contains("user") && errorString.contains("not found") {
            return .userNotFound
        } else {
            return .networkError(error.localizedDescription)
        }
    }
}