//
//  LicenseConstants.swift
//  Vantaview
//
//  Created by Vantaview on 12/19/24.
//

import Foundation

/// Configuration constants for the licensing system
struct LicenseConstants {
    
    // MARK: - Grace Period
    
    /// Default grace period in hours when offline or expired
    static let graceHoursDefault: Int = 48
    
    /// Maximum grace period in hours
    static let maxGraceHours: Int = 72
    
    // MARK: - Refresh Intervals
    
    /// How often to refresh license from server (in seconds)
    static let licenseRefreshInterval: TimeInterval = 4 * 3600 // 4 hours
    
    /// Minimum time between refresh attempts (prevents spam)
    static let minimumRefreshInterval: TimeInterval = 300 // 5 minutes
    
    // MARK: - JWT Configuration
    
    /// URL for server's JSON Web Key Set (for JWT verification)
    /// TODO: Replace with actual production URL
    static let jwkSetURL = URL(string: "https://vantaview.app/.well-known/jwks.json")!
    
    /// JWT issuer expected in tokens
    static let jwtIssuer = "vantaview.app"
    
    /// JWT audience expected in tokens
    static let jwtAudience = "vantaview-app"
    
    // MARK: - API Endpoints
    
    /// Base URL for Vantaview API
    static let apiBaseURL = URL(string: "https://vantaview.app/api")!
    
    /// License verification endpoint
    static let licenseEndpoint = "license/verify"
    
    /// Billing management portal URL
    static let billingPortalURL = URL(string: "https://vantaview.app/billing")!
    
    // MARK: - Keychain Configuration
    
    /// Keychain service identifier for storing cached licenses
    static let keychainService = "app.vantaview.license"
    
    /// Keychain account for cached license data
    static let keychainAccount = "cached_license"
    
    // MARK: - Trial Configuration
    
    /// Default trial length in days
    static let trialLengthDays: Int = 7
    
    /// Days before trial end to show upgrade prompts
    static let trialWarningDays: Int = 3
    
    // MARK: - Feature Flags
    
    /// Enable/disable offline grace period
    static let offlineGraceEnabled: Bool = true
    
    /// Enable/disable JWT signature verification
    static let jwtVerificationEnabled: Bool = true
    
    /// Enable/disable license caching
    static let licenseCachingEnabled: Bool = true
    
    // MARK: - Debug Configuration
    
    #if DEBUG
    /// Enable debug logging for license operations
    static let debugLoggingEnabled: Bool = true
    
    /// Allow license tier impersonation in debug builds
    static let debugImpersonationEnabled: Bool = true
    #else
    static let debugLoggingEnabled: Bool = false
    static let debugImpersonationEnabled: Bool = false
    #endif
}