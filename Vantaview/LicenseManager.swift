import Foundation
import SwiftUI
import os

@MainActor
final class LicenseManager: ObservableObject {
    // Derived UI state
    @Published private(set) var currentLicense: LicenseInfo?
    @Published private(set) var lastErrorMessage: String?
    
    // Back-compat for existing UI (AccountView, FeatureGatingModifiers, etc.)
    @Published private(set) var currentTier: PlanTier?
    @Published private(set) var status: LicenseStatus = .unknown
    @Published private(set) var lastRefreshDate: Date?
    
    private let service: LicenseService
    private var userID: String?
    private var autoRefreshTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "app.vantaview", category: "LicenseManager")
    
    #if DEBUG
    @Published var debugImpersonatedTier: PlanTier?
    @Published var debugOfflineMode: Bool = false
    @Published var debugExpiredMode: Bool = false
    #endif
    
    init(service: LicenseService = LicenseService()) {
        self.service = service
    }
    
    func setCurrentUser(_ id: String?) {
        guard id != userID else { return }
        logger.debug("Set current user: \(id ?? "nil", privacy: .public)")
        userID = id
        currentLicense = nil
        currentTier = nil
        status = .unknown
        lastRefreshDate = nil
        lastErrorMessage = nil
        stopAutomaticRefresh()
    }
    
    // Main API (async throws)
    func refreshLicense(sessionToken: String, userID: String) async throws {
        try Task.checkCancellation()
        
        #if DEBUG
        if debugOfflineMode {
            logger.warning("DEBUG: Simulating offline mode")
            let simulatedError = NSError(domain: "LicenseManager.Debug", code: -1009, userInfo: [NSLocalizedDescriptionKey: "Simulated offline mode"])
            lastErrorMessage = simulatedError.localizedDescription
            status = .error(simulatedError.localizedDescription)
            throw simulatedError
        }
        #endif
        
        do {
            let fetched = try await service.fetchLicense(sessionToken: sessionToken, userID: userID)
            try Task.checkCancellation()
            
            var finalInfo = fetched
            
            #if DEBUG
            if debugExpiredMode {
                logger.warning("DEBUG: Forcing expired license")
                finalInfo = LicenseInfo(
                    tier: fetched.tier,
                    expiresAt: Date().addingTimeInterval(-60),
                    features: fetched.features
                )
            }
            if let forced = debugImpersonatedTier {
                logger.warning("DEBUG: Impersonating tier: \(forced.rawValue, privacy: .public)")
                finalInfo = LicenseInfo(
                    tier: mapPlanTierToLicenseTier(forced),
                    expiresAt: Date().addingTimeInterval(7 * 24 * 60 * 60),
                    features: fetched.features
                )
            }
            #endif
            
            currentLicense = finalInfo
            lastErrorMessage = nil
            lastRefreshDate = Date()
            currentTier = mapLicenseTierToPlanTier(finalInfo.tier)
            status = finalInfo.isExpired ? .expired : .active
            logger.debug("License updated: tier=\(finalInfo.tier.rawValue, privacy: .public) expired=\(finalInfo.isExpired, privacy: .public)")
        } catch is CancellationError {
            logger.debug("refreshLicense cancelled")
            throw CancellationError()
        } catch {
            lastErrorMessage = error.localizedDescription
            status = .error(error.localizedDescription)
            logger.error("refreshLicense failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
    
    // Back-compat utility for legacy call sites (non-throwing, optionals)
    func refreshLicense(sessionToken: String?, userID: String?) async {
        do {
            try Task.checkCancellation()
            guard let token = sessionToken, let id = userID ?? self.userID else {
                lastErrorMessage = "No valid session"
                status = .error("No valid session")
                return
            }
            try await refreshLicense(sessionToken: token, userID: id)
        } catch is CancellationError {
            logger.debug("refreshLicense(sessionToken:userID:) cancelled")
        } catch {
        }
    }
    
    func startAutomaticRefresh(sessionToken: String, userID: String, every interval: Duration = .seconds(15 * 60)) {
        stopAutomaticRefresh()
        logger.debug("Starting auto-refresh loop every \(Int(interval.components.seconds), privacy: .public)s")
        
        autoRefreshTask = Task { [weak self] in
            let clock = ContinuousClock()
            while true {
                do {
                    try await clock.sleep(for: interval)
                    try Task.checkCancellation()
                    guard let self else { return }
                    try await self.refreshLicense(sessionToken: sessionToken, userID: userID)
                } catch is CancellationError {
                    self?.logger.debug("Auto-refresh cancelled")
                    return
                } catch {
                    self?.lastErrorMessage = error.localizedDescription
                    self?.status = .error(error.localizedDescription)
                    self?.logger.error("Auto-refresh error: \(error.localizedDescription, privacy: .public). Will continue.")
                    continue
                }
            }
        }
    }
    
    func stopAutomaticRefresh() {
        if let task = autoRefreshTask {
            logger.debug("Stopping auto-refresh loop")
            task.cancel()
        }
        autoRefreshTask = nil
    }
    
    // Feature gating back-compat used by UI
    func isEnabled(_ feature: FeatureKey) -> Bool {
        #if DEBUG
        if let impersonated = debugImpersonatedTier {
            let enabled = FeatureMatrix.isEnabled(feature, for: impersonated)
            return enabled
        }
        if debugExpiredMode {
            return false
        }
        #endif
        
        guard let tier = currentTier, status.isValid else {
            return false
        }
        return FeatureMatrix.isEnabled(feature, for: tier)
    }
    
    // MARK: - Mapping Helpers
    
    private func mapLicenseTierToPlanTier(_ tier: LicenseTier) -> PlanTier {
        switch tier {
        case .stream: return .stream
        case .live: return .live
        case .stage: return .stage
        case .pro: return .pro
        }
    }
    
    private func mapPlanTierToLicenseTier(_ tier: PlanTier) -> LicenseTier {
        switch tier {
        case .stream: return .stream
        case .live: return .live
        case .stage: return .stage
        case .pro: return .pro
        }
    }
}

// Internal protocol conformance preserved for existing code
extension LicenseManager: FeatureGate {}