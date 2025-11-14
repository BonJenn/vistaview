//
//  JWTVerifier.swift
//  Vantaview
//
//  Real Ed25519 JWT verification for license tokens
//

import Foundation
import CryptoKit

struct JWTVerifier {

    // Replace with the real 32-byte Ed25519 public key (raw bytes, base64-encoded)
    static let publicKeyRawBase64 = "dj8Bqg9rPjxlq1kLAmxML2IDQdHdnHmPT4ikZrOOHBc="

    static var publicKeyFingerprintBase64URL: String {
        guard let raw = Data(base64Encoded: publicKeyRawBase64) else { return "" }
        let digest = SHA256.hash(data: raw)
        var b64 = Data(digest).base64EncodedString()
        b64 = b64.replacingOccurrences(of: "+", with: "-")
                 .replacingOccurrences(of: "/", with: "_")
                 .replacingOccurrences(of: "=", with: "")
        return b64
    }

    struct Header: Codable {
        let alg: String
        let typ: String?
        let kid: String?
    }

    static func verify(token: String) throws -> JWTClaims {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { throw JWTError.malformedToken }

        let headerPart = String(parts[0])
        let payloadPart = String(parts[1])
        let signaturePart = String(parts[2])

        guard let headerData = base64URLDecode(headerPart),
              let payloadData = base64URLDecode(payloadPart),
              let signatureData = base64URLDecode(signaturePart) else {
            throw JWTError.base64DecodingFailed
        }

        let header = try JSONDecoder().decode(Header.self, from: headerData)
        guard header.alg.uppercased() == "EDDSA" else { throw JWTError.unsupportedAlgorithm }

        let message = Data("\(headerPart).\(payloadPart)".utf8)
        let pubRaw = Data(base64Encoded: Self.publicKeyRawBase64) ?? Data()
        if pubRaw.count != 32 { throw JWTError.invalidPublicKey }
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: pubRaw)
        guard publicKey.isValidSignature(signatureData, for: message) else {
            throw JWTError.invalidSignature
        }

        let claims = try JSONDecoder().decode(JWTClaims.self, from: payloadData)
        let now = Date()
        if Date(timeIntervalSince1970: claims.exp) < now { throw JWTError.tokenExpired }
        if let nbf = claims.nbf, Date(timeIntervalSince1970: nbf) > now { throw JWTError.tokenNotYetValid }
        if claims.iss != LicenseConstants.jwtIssuer { throw JWTError.invalidIssuer }
        if claims.aud != LicenseConstants.jwtAudience { throw JWTError.invalidAudience }

        return claims
    }

    private static func base64URLDecode(_ s: String) -> Data? {
        var base64 = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        return Data(base64Encoded: base64)
    }

    enum JWTError: LocalizedError {
        case malformedToken, base64DecodingFailed, unsupportedAlgorithm, invalidPublicKey, invalidSignature, tokenExpired, tokenNotYetValid, invalidIssuer, invalidAudience

        var errorDescription: String? {
            switch self {
            case .malformedToken: return "Malformed JWT"
            case .base64DecodingFailed: return "Failed to decode base64url"
            case .unsupportedAlgorithm: return "Unsupported JWT alg"
            case .invalidPublicKey: return "Invalid public key"
            case .invalidSignature: return "Invalid signature"
            case .tokenExpired: return "JWT expired"
            case .tokenNotYetValid: return "JWT not yet valid"
            case .invalidIssuer: return "Invalid issuer"
            case .invalidAudience: return "Invalid audience"
            }
        }
    }
}

struct JWTClaims: Codable {
    let iss: String
    let aud: String
    let sub: String
    let iat: TimeInterval
    let exp: TimeInterval
    let nbf: TimeInterval?
    let tier: String
    let trial: Bool?
    let deviceID: String?

    enum CodingKeys: String, CodingKey {
        case iss, aud, sub, iat, exp, nbf, tier, trial
        case deviceID = "device_id"
    }

    var planTier: PlanTier? { PlanTier(rawValue: tier) }
}
