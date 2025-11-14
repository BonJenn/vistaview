import Foundation
import SwiftUI
import os

@MainActor
final class LicenseManager: ObservableObject {
    @Published private(set) var currentLicense: LicenseInfo?
    @Published private(set) var lastErrorMessage: String?

    @Published private(set) var currentTier: PlanTier?
    @Published private(set) var status: LicenseStatus = .unknown
    @Published private(set) var lastRefreshDate: Date?

    private let logger = Logger(subsystem: "app.vantaview", category: "LicenseManager")

    private let deviceService: DeviceService
    private let licenseAPI: LicenseAPI

    private var userID: String?
    private var autoRefreshTask: Task<Void, Never>?

    #if DEBUG
    @Published var debugImpersonatedTier: PlanTier?
    @Published var debugOfflineMode: Bool = false
    @Published var debugExpiredMode: Bool = false
    #endif

    init(deviceService: DeviceService = DeviceService(), licenseAPI: LicenseAPI = LicenseAPI()) {
        self.deviceService = deviceService
        self.licenseAPI = licenseAPI
    }

    func setCurrentUser(_ id: String?) {
        guard id != userID else { return }
        userID = id
        currentLicense = nil
        currentTier = nil
        status = .unknown
        lastRefreshDate = nil
        lastErrorMessage = nil
        stopAutomaticRefresh()
    }

    func refreshLicense(sessionToken: String, userID: String) async throws {
        try Task.checkCancellation()

        #if DEBUG
        if debugOfflineMode {
            let simulatedError = NSError(domain: "LicenseManager.Debug", code: -1009, userInfo: [NSLocalizedDescriptionKey: "Simulated offline mode"])
            lastErrorMessage = simulatedError.localizedDescription
            status = .error(simulatedError.localizedDescription)
            throw simulatedError
        }
        #endif

        do {
            let deviceID = DeviceID.deviceID()
            let deviceName = DeviceID.deviceName()
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

            // Single source of truth: fetch signedJWT and derive entitlements
            let jwtResponse = try await licenseAPI.fetchTier(sessionToken: sessionToken,
                                                             deviceID: deviceID,
                                                             deviceName: deviceName,
                                                             appVersion: appVersion)
            try Task.checkCancellation()
            let entitlements = try await LicenseVerifier.verify(jwt: jwtResponse.signedJWT)
            let verifiedTier = mapPlanTierToLicenseTier(entitlements.tier)

            var finalInfo = LicenseInfo(
                tier: verifiedTier,
                expiresAt: entitlements.expiresAt,
                features: []
            )

            #if DEBUG
            if debugExpiredMode {
                finalInfo = LicenseInfo(
                    tier: finalInfo.tier,
                    expiresAt: Date().addingTimeInterval(-60),
                    features: finalInfo.features
                )
            }
            if let forced = debugImpersonatedTier {
                finalInfo = LicenseInfo(
                    tier: mapPlanTierToLicenseTier(forced),
                    expiresAt: Date().addingTimeInterval(7 * 24 * 60 * 60),
                    features: finalInfo.features
                )
            }
            #endif

            currentLicense = finalInfo
            lastErrorMessage = nil
            lastRefreshDate = Date()
            currentTier = mapLicenseTierToPlanTier(finalInfo.tier)
            status = finalInfo.isExpired ? .expired : .active

            // Fire-and-forget heartbeat register to update last_seen_at
            Task.detached { [sessionToken] in
                try? await self.deviceService.registerDevice(sessionToken: sessionToken,
                                                             deviceID: deviceID,
                                                             deviceName: deviceName,
                                                             appVersion: appVersion)
                if !DeviceID.isInstalledTracked() {
                    DeviceID.markInstalledTracked()
                }
            }

        } catch is CancellationError {
            throw CancellationError()
        } catch {
            lastErrorMessage = error.localizedDescription
            status = .error(error.localizedDescription)
            throw error
        }
    }

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
        } catch {
        }
    }

    func startAutomaticRefresh(sessionToken: String, userID: String, every interval: Duration = .seconds(15 * 60)) {
        stopAutomaticRefresh()

        autoRefreshTask = Task { [weak self] in
            let clock = ContinuousClock()
            while true {
                do {
                    try await clock.sleep(for: interval)
                    try Task.checkCancellation()
                    guard let self else { return }
                    try await self.refreshLicense(sessionToken: sessionToken, userID: userID)
                } catch is CancellationError {
                    return
                } catch {
                    self?.lastErrorMessage = error.localizedDescription
                    self?.status = .error(error.localizedDescription)
                    continue
                }
            }
        }
    }

    func stopAutomaticRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    func isEnabled(_ feature: FeatureKey) -> Bool {
        #if DEBUG
        if let impersonated = debugImpersonatedTier {
            return FeatureMatrix.isEnabled(feature, for: impersonated)
        }
        if debugExpiredMode { return false }
        #endif

        guard let tier = currentTier, status.isValid else {
            return false
        }
        return FeatureMatrix.isEnabled(feature, for: tier)
    }

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

extension LicenseManager: FeatureGate {}