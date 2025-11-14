import Foundation

struct LicenseEntitlements: Sendable, Equatable {
    let tier: PlanTier
    let isTrial: Bool
    let expiresAt: Date
    let userID: String
}

enum LicenseVerifyError: LocalizedError {
    case invalidTier
    case deviceMismatch
    case verifyFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidTier: return "Invalid tier in license token"
        case .deviceMismatch: return "License is not bound to this device"
        case .verifyFailed(let reason): return "License verification failed: \(reason)"
        }
    }
}

actor LicenseVerifier {
    static func verify(jwt: String) async throws -> LicenseEntitlements {
        do {
            let claims = try JWTVerifier.verify(token: jwt)

            // Device binding check
            if let deviceID = claims.deviceID {
                if deviceID != DeviceID.deviceID() {
                    throw LicenseVerifyError.deviceMismatch
                }
            }

            guard let tier = PlanTier(rawValue: claims.tier) else {
                throw LicenseVerifyError.invalidTier
            }
            let exp = Date(timeIntervalSince1970: claims.exp)
            return LicenseEntitlements(
                tier: tier,
                isTrial: claims.trial ?? false,
                expiresAt: exp,
                userID: claims.sub
            )
        } catch {
            throw LicenseVerifyError.verifyFailed(error.localizedDescription)
        }
    }
}