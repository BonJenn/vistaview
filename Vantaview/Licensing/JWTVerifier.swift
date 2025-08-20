//
//  JWTVerifier.swift
//  Vistaview
//
//  Created by Vistaview on 12/19/24.
//

import Foundation
import CryptoKit

/// Simple JWT verification for license tokens
/// NOTE: This is a simplified implementation. In production, you'd want a more robust JWT library.
struct JWTVerifier {
    
    /// Verify a JWT token (simplified implementation)
    static func verify(token: String) -> JWTClaims? {
        // For now, we'll implement basic JWT parsing without signature verification
        // In production, you should use a proper JWT library that verifies signatures
        
        let components = token.components(separatedBy: ".")
        guard components.count == 3 else {
            if LicenseConstants.debugLoggingEnabled {
                print("🔐 JWT: Invalid token format")
            }
            return nil
        }
        
        // Decode payload (second component)
        let payloadComponent = components[1]
        guard let payloadData = base64URLDecode(payloadComponent) else {
            if LicenseConstants.debugLoggingEnabled {
                print("🔐 JWT: Failed to decode payload")
            }
            return nil
        }
        
        do {
            let claims = try JSONDecoder().decode(JWTClaims.self, from: payloadData)
            
            // Basic validation
            let now = Date()
            if Date(timeIntervalSince1970: claims.exp) < now {
                if LicenseConstants.debugLoggingEnabled {
                    print("🔐 JWT: Token expired")
                }
                return nil
            }
            
            if let nbf = claims.nbf, Date(timeIntervalSince1970: nbf) > now {
                if LicenseConstants.debugLoggingEnabled {
                    print("🔐 JWT: Token not yet valid")
                }
                return nil
            }
            
            // Verify issuer and audience
            if claims.iss != LicenseConstants.jwtIssuer {
                if LicenseConstants.debugLoggingEnabled {
                    print("🔐 JWT: Invalid issuer")
                }
                return nil
            }
            
            if claims.aud != LicenseConstants.jwtAudience {
                if LicenseConstants.debugLoggingEnabled {
                    print("🔐 JWT: Invalid audience")
                }
                return nil
            }
            
            if LicenseConstants.debugLoggingEnabled {
                print("🔐 JWT: Token verified successfully for tier: \(claims.tier)")
            }
            
            return claims
            
        } catch {
            if LicenseConstants.debugLoggingEnabled {
                print("🔐 JWT: Failed to decode claims: \(error)")
            }
            return nil
        }
    }
    
    private static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Add padding if needed
        while base64.count % 4 != 0 {
            base64 += "="
        }
        
        return Data(base64Encoded: base64)
    }
}

// MARK: - JWT Claims

struct JWTClaims: Codable {
    let iss: String       // Issuer
    let aud: String       // Audience
    let sub: String       // Subject (user ID)
    let iat: TimeInterval // Issued at
    let exp: TimeInterval // Expires at
    let nbf: TimeInterval? // Not before
    let tier: String      // Subscription tier
    let trial: Bool?      // Is trial
    
    var planTier: PlanTier? {
        return PlanTier(rawValue: tier)
    }
}