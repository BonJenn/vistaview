import Foundation
import os

public enum LicenseTier: String, Codable, Sendable, CaseIterable {
    case stream
    case live
    case stage
    case pro
}

public struct LicenseInfo: Codable, Sendable, Equatable {
    public let tier: LicenseTier
    public let expiresAt: Date
    public let features: [String]
    
    public var isExpired: Bool { Date() >= expiresAt }
    
    public init(tier: LicenseTier, expiresAt: Date, features: [String]) {
        self.tier = tier
        self.expiresAt = expiresAt
        self.features = features
    }
}

public extension LicenseInfo {
    func hasFeature(_ name: String) -> Bool { features.contains(name) && !isExpired }
}

public actor LicenseService {
    public enum ServiceError: Error, LocalizedError, Sendable {
        case invalidURL
        case invalidResponse
        case httpError(status: Int)
        case decodingError
        case cancelled
        
        public var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid URL."
            case .invalidResponse: return "Invalid server response."
            case .httpError(let status): return "HTTP error with status code \(status)."
            case .decodingError: return "Failed to decode license."
            case .cancelled: return "Request was cancelled."
            }
        }
    }
    
    private let logger = Logger(subsystem: "app.vantaview", category: "LicenseService")
    private let baseURL: URL
    
    public init(baseURL: URL = URL(string: "https://api.vantaview.app")!) {
        self.baseURL = baseURL
    }
    
    public func fetchLicense(sessionToken: String, userID: String) async throws -> LicenseInfo {
        try Task.checkCancellation()
        
        guard let url = URL(string: "/v1/license", relativeTo: baseURL) else {
            logger.error("Failed to build license URL")
            throw ServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue(userID, forHTTPHeaderField: "X-User-ID")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            try Task.checkCancellation()
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            
            guard let http = response as? HTTPURLResponse else {
                logger.error("Non-HTTP response")
                throw ServiceError.invalidResponse
            }
            
            guard (200...299).contains(http.statusCode) else {
                logger.error("HTTP error status=\(http.statusCode)")
                throw ServiceError.httpError(status: http.statusCode)
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            struct LicenseDTO: Decodable {
                let tier: String
                let expiresAt: Date
                let features: [String]
                
                enum CodingKeys: String, CodingKey {
                    case tier
                    case expiresAt = "expires_at"
                    case features
                }
            }
            
            do {
                let dto = try decoder.decode(LicenseDTO.self, from: data)
                let tier = LicenseTier(rawValue: dto.tier) ?? .stream
                let info = LicenseInfo(tier: tier, expiresAt: dto.expiresAt, features: dto.features)
                logger.debug("Fetched license: tier=\(info.tier.rawValue, privacy: .public) expired=\(info.isExpired, privacy: .public)")
                return info
            } catch {
                logger.error("Decoding error: \(error.localizedDescription, privacy: .public)")
                throw ServiceError.decodingError
            }
        } catch is CancellationError {
            logger.debug("Fetch license cancelled")
            throw ServiceError.cancelled
        } catch {
            logger.error("Fetch license failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}