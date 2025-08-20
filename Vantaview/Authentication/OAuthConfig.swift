//
//  OAuthConfig.swift
//  Vantaview
//
//  Created by Vantaview on 12/19/24.
//

import Foundation

/// Configuration for OAuth providers
struct OAuthConfig {
    
    // MARK: - Google OAuth
    
    /// Your Google OAuth client ID (same as vantaview-landing)
    /// TODO: Replace with your actual Google client ID
    static let googleClientId = "YOUR_GOOGLE_CLIENT_ID_HERE"
    
    /// OAuth redirect URI (should match your web app)
    static let redirectURI = "https://vantaview.app/auth/callback"
    
    /// Google OAuth scopes
    static let googleScopes = "openid email profile"
    
    // MARK: - Apple OAuth
    
    /// Apple OAuth configuration (placeholder)
    static let appleClientId = "app.vantaview.signin"
    
    // MARK: - Validation
    
    static var isGoogleConfigured: Bool {
        return !googleClientId.contains("YOUR_GOOGLE_CLIENT_ID")
    }
    
    static var isAppleConfigured: Bool {
        return false // Not implemented yet
    }
}