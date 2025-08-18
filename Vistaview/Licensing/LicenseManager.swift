//
//  LicenseManager.swift
//  Vistaview
//
//  Created by Vistaview on 12/19/24.
//

import Foundation
import SwiftUI

/// Main license management service
@MainActor
final class LicenseManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentTier: PlanTier?
    @Published var status: LicenseStatus = .unknown
    @Published var lastRefreshDate: Date?
    @Published var isRefreshing = false
    
    // MARK: - Private Properties
    
    private let licenseAPI: LicenseAPI
    private var refreshTimer: Timer?
    private var lastRefreshAttempt: Date?
    private var currentUserID: String?
    
    // Debug properties
    #if DEBUG
    @Published var debugImpersonatedTier: PlanTier?
    @Published var debugOfflineMode = false
    @Published var debugExpiredMode = false
    #endif
    
    // MARK: - Initialization
    
    init(licenseAPI: LicenseAPI = LicenseAPI()) {
        self.licenseAPI = licenseAPI
        
        if LicenseConstants.debugLoggingEnabled {
            print("🔐 LicenseManager: Initialized")
        }
    }
    
    // MARK: - Public Methods
    
    /// Refresh license from server
    func refreshLicense(sessionToken: String?, userID: String? = nil) async {
        guard !isRefreshing else {
            if LicenseConstants.debugLoggingEnabled {
                print("🔐 LicenseManager: Refresh already in progress")
            }
            return
        }
        
        // Rate limiting
        if let lastAttempt = lastRefreshAttempt,
           Date().timeIntervalSince(lastAttempt) < LicenseConstants.minimumRefreshInterval {
            if LicenseConstants.debugLoggingEnabled {
                print("🔐 LicenseManager: Rate limited, skipping refresh")
            }
            return
        }
        
        isRefreshing = true
        lastRefreshAttempt = Date()
        
        defer {
            isRefreshing = false
        }
        
        #if DEBUG
        // Debug mode overrides
        if debugOfflineMode {
            await handleOfflineMode(userID: userID)
            return
        }
        
        if debugExpiredMode {
            status = .expired
            currentTier = nil
            return
        }
        
        if let impersonatedTier = debugImpersonatedTier {
            currentTier = impersonatedTier
            status = .active
            lastRefreshDate = Date()
            if LicenseConstants.debugLoggingEnabled {
                print("🔐 LicenseManager: Using debug impersonated tier: \(impersonatedTier)")
            }
            return
        }
        #endif
        
        guard let sessionToken = sessionToken else {
            await handleMissingSession(userID: userID)
            return
        }
        
        do {
            let licenseDTO = try await licenseAPI.fetchTier(sessionToken: sessionToken)
            await handleSuccessfulRefresh(licenseDTO: licenseDTO, userID: userID)
            
        } catch {
            await handleRefreshError(error: error, userID: userID)
        }
    }
    
    /// Set current user (for cache management)
    func setCurrentUser(_ userID: String?) {
        currentUserID = userID
        
        if let userID = userID {
            // Load cached license for this user
            loadCachedLicense(for: userID)
        } else {
            // Clear current state when user logs out
            currentTier = nil
            status = .unknown
            lastRefreshDate = nil
        }
    }
    
    /// Start automatic license refresh timer
    func startAutomaticRefresh(sessionToken: String?) {
        stopAutomaticRefresh()
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: LicenseConstants.licenseRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshLicense(sessionToken: sessionToken)
            }
        }
        
        if LicenseConstants.debugLoggingEnabled {
            print("🔐 LicenseManager: Started automatic refresh timer")
        }
    }
    
    /// Stop automatic license refresh timer
    func stopAutomaticRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        
        if LicenseConstants.debugLoggingEnabled {
            print("🔐 LicenseManager: Stopped automatic refresh timer")
        }
    }
    
    // MARK: - Private Methods
    
    private func handleSuccessfulRefresh(licenseDTO: LicenseDTO, userID: String?) async {
        // Verify JWT if enabled
        if LicenseConstants.jwtVerificationEnabled {
            guard let claims = JWTVerifier.verify(token: licenseDTO.signedJWT),
                  claims.planTier == licenseDTO.planTier else {
                if LicenseConstants.debugLoggingEnabled {
                    print("🔐 LicenseManager: JWT verification failed")
                }
                await handleRefreshError(error: LicenseAPIError.unauthorized, userID: userID)
                return
            }
        }
        
        // Update current state
        currentTier = licenseDTO.planTier
        lastRefreshDate = Date()
        
        // Determine status
        let now = Date()
        if licenseDTO.isTrial {
            if let trialEnd = licenseDTO.trialEndsAt {
                let daysRemaining = max(0, Int(trialEnd.timeIntervalSince(now) / 86400))
                status = .trial(daysRemaining: daysRemaining)
            } else {
                status = .active
            }
        } else if now < licenseDTO.expiresAt {
            status = .active
        } else {
            status = .expired
        }
        
        // Cache the license
        if LicenseConstants.licenseCachingEnabled, let userID = userID ?? currentUserID {
            let cachedLicense = CachedLicense(
                tier: licenseDTO.planTier ?? .stream,
                expiresAt: licenseDTO.expiresAt,
                isTrial: licenseDTO.isTrial,
                trialEndsAt: licenseDTO.trialEndsAt,
                cachedAt: Date(),
                etag: nil // TODO: Implement ETag support
            )
            
            _ = KeychainHelper.storeCachedLicense(cachedLicense, for: userID)
        }
        
        if LicenseConstants.debugLoggingEnabled {
            print("🔐 LicenseManager: Successfully refreshed license - Tier: \(currentTier?.displayName ?? "None"), Status: \(status)")
        }
    }
    
    private func handleRefreshError(error: Error, userID: String?) async {
        if LicenseConstants.debugLoggingEnabled {
            print("🔐 LicenseManager: Refresh error: \(error)")
        }
        
        // Try to fall back to cached license
        if let userID = userID ?? currentUserID,
           let cachedLicense = KeychainHelper.getCachedLicense(for: userID) {
            
            if cachedLicense.isInGracePeriod {
                currentTier = cachedLicense.tier
                status = .grace(hoursRemaining: cachedLicense.gracePeriodHoursRemaining)
                
                if LicenseConstants.debugLoggingEnabled {
                    print("🔐 LicenseManager: Using cached license in grace period")
                }
                return
            } else if !cachedLicense.isExpired {
                currentTier = cachedLicense.tier
                
                if let daysRemaining = cachedLicense.trialDaysRemaining {
                    status = .trial(daysRemaining: daysRemaining)
                } else {
                    status = .active
                }
                
                if LicenseConstants.debugLoggingEnabled {
                    print("🔐 LicenseManager: Using valid cached license")
                }
                return
            }
        }
        
        // No valid cache, set error state
        currentTier = nil
        
        if let apiError = error as? LicenseAPIError {
            status = .error(apiError.localizedDescription)
        } else {
            status = .error(error.localizedDescription)
        }
    }
    
    private func handleMissingSession(userID: String?) async {
        // Try cached license
        if let userID = userID ?? currentUserID,
           let cachedLicense = KeychainHelper.getCachedLicense(for: userID),
           (cachedLicense.isInGracePeriod || !cachedLicense.isExpired) {
            
            currentTier = cachedLicense.tier
            
            if cachedLicense.isInGracePeriod {
                status = .grace(hoursRemaining: cachedLicense.gracePeriodHoursRemaining)
            } else if let daysRemaining = cachedLicense.trialDaysRemaining {
                status = .trial(daysRemaining: daysRemaining)
            } else {
                status = .active
            }
            
            if LicenseConstants.debugLoggingEnabled {
                print("🔐 LicenseManager: Using cached license (no session)")
            }
        } else {
            currentTier = nil
            status = .error("No valid session")
        }
    }
    
    private func handleOfflineMode(userID: String?) async {
        if let userID = userID ?? currentUserID,
           let cachedLicense = KeychainHelper.getCachedLicense(for: userID) {
            
            if cachedLicense.isInGracePeriod || !cachedLicense.isExpired {
                currentTier = cachedLicense.tier
                
                if cachedLicense.isInGracePeriod {
                    status = .grace(hoursRemaining: cachedLicense.gracePeriodHoursRemaining)
                } else if let daysRemaining = cachedLicense.trialDaysRemaining {
                    status = .trial(daysRemaining: daysRemaining)
                } else {
                    status = .active
                }
                
                if LicenseConstants.debugLoggingEnabled {
                    print("🔐 LicenseManager: Using cached license (offline)")
                }
            } else {
                currentTier = nil
                status = .expired
            }
        } else {
            currentTier = nil
            status = .error("Offline with no cached license")
        }
    }
    
    private func loadCachedLicense(for userID: String) {
        guard let cachedLicense = KeychainHelper.getCachedLicense(for: userID) else {
            return
        }
        
        if cachedLicense.isInGracePeriod || !cachedLicense.isExpired {
            currentTier = cachedLicense.tier
            
            if cachedLicense.isInGracePeriod {
                status = .grace(hoursRemaining: cachedLicense.gracePeriodHoursRemaining)
            } else if let daysRemaining = cachedLicense.trialDaysRemaining {
                status = .trial(daysRemaining: daysRemaining)
            } else {
                status = .active
            }
            
            if LicenseConstants.debugLoggingEnabled {
                print("🔐 LicenseManager: Loaded cached license for user")
            }
        }
    }
}

// MARK: - FeatureGate Conformance

extension LicenseManager: FeatureGate {
    
    func isEnabled(_ feature: FeatureKey) -> Bool {
        #if DEBUG
        // Debug overrides
        if let impersonatedTier = debugImpersonatedTier {
            let enabled = FeatureMatrix.isEnabled(feature, for: impersonatedTier)
            if LicenseConstants.debugLoggingEnabled && !enabled {
                print("🔐 Feature '\(feature.displayName)' denied for debug tier \(impersonatedTier.displayName)")
            }
            return enabled
        }
        
        if debugExpiredMode {
            if LicenseConstants.debugLoggingEnabled {
                print("🔐 Feature '\(feature.displayName)' denied (debug expired mode)")
            }
            return false
        }
        #endif
        
        guard let tier = currentTier, status.isValid else {
            if LicenseConstants.debugLoggingEnabled {
                print("🔐 Feature '\(feature.displayName)' denied (no valid license)")
            }
            return false
        }
        
        let enabled = FeatureMatrix.isEnabled(feature, for: tier)
        
        if LicenseConstants.debugLoggingEnabled && !enabled {
            print("🔐 Feature '\(feature.displayName)' denied for tier \(tier.displayName)")
        }
        
        return enabled
    }
}