//
//  LicenseConstants.swift
//  Vantaview
//
//  Created by Vantaview on 12/19/24.
//

import Foundation

struct LicenseConstants {

    // MARK: - Grace Period

    static let graceHoursDefault: Int = 48
    static let maxGraceHours: Int = 72

    // MARK: - Refresh Intervals

    static let licenseRefreshInterval: TimeInterval = 4 * 3600
    static let minimumRefreshInterval: TimeInterval = 300

    // MARK: - JWT Configuration

    static let jwkSetURL = URL(string: "https://vantaview.live/.well-known/jwks.json")!

    // Website-aligned JWT contract
    static let jwtIssuer = "vantaview.licenses"
    static let jwtAudience = "vantaview.live"

    // MARK: - API Endpoints (website origin + paths)

    // Website origin (do not include /api here)
    static let websiteBaseURL = URL(string: "https://vantaview.live")!

    // Server routes (App Router /api/*)
    static let licenseIssuePath = "/api/license/issue"
    static let deviceRegisterPath = "/api/devices/register"
    static let deviceTransferPath = "/api/devices/transfer"

    // Billing portal used in Account/Paywall views
    static let billingPortalURL = URL(string: "https://vantaview.live/billing")!

    // MARK: - Keychain Configuration

    static let keychainService = "app.vantaview.license"
    static let keychainAccount = "cached_license"

    // MARK: - Trial Configuration

    static let trialLengthDays: Int = 7
    static let trialWarningDays: Int = 3

    // MARK: - Feature Flags

    static let offlineGraceEnabled: Bool = true
    static let jwtVerificationEnabled: Bool = true
    static let licenseCachingEnabled: Bool = true

    // MARK: - Debug

    #if DEBUG
    static let debugLoggingEnabled: Bool = true
    static let debugImpersonationEnabled: Bool = true
    #else
    static let debugLoggingEnabled: Bool = false
    static let debugImpersonationEnabled: Bool = false
    #endif
}
