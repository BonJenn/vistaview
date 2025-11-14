//
//  LicenseAPI.swift
//  Vantaview
//
//  Created by Vantaview on 12/19/24.
//

import Foundation

actor LicenseAPI {

    private let session: URLSession
    private let url: URL

    init(session: URLSession = .shared,
         baseURL: URL = LicenseConstants.websiteBaseURL.appendingPathComponent(LicenseConstants.licenseIssuePath.trimmingCharacters(in: CharacterSet(charactersIn: "/")).hasPrefix("api")
                                                                               ? String(LicenseConstants.licenseIssuePath.dropFirst())
                                                                               : LicenseConstants.licenseIssuePath)) {
        self.session = session
        self.url = baseURL
    }

    struct SignedJWTResponse: Decodable {
        let signedJWT: String
    }

    // CHANGE: Accept device info in the request body
    func fetchTier(sessionToken: String,
                   deviceID: String,
                   deviceName: String,
                   appVersion: String) async throws -> SignedJWTResponse {
        try Task.checkCancellation()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "device_id": deviceID,
            "device_name": deviceName,
            "app_version": appVersion
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        if LicenseConstants.debugLoggingEnabled {
            print("🔐 LicenseAPI: POST \(url.absoluteString)")
        }

        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()

        guard let http = response as? HTTPURLResponse else {
            throw LicenseAPIError.invalidResponse
        }

        if LicenseConstants.debugLoggingEnabled {
            print("🔐 LicenseAPI: Response \(http.statusCode)")
        }

        switch http.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(SignedJWTResponse.self, from: data)
            } catch {
                throw LicenseAPIError.decodingFailed(error)
            }
        case 401: throw LicenseAPIError.unauthorized
        case 403: throw LicenseAPIError.forbidden
        case 404: throw LicenseAPIError.userNotFound
        case 429: throw LicenseAPIError.rateLimited
        case 500...599: throw LicenseAPIError.serverError(http.statusCode)
        default: throw LicenseAPIError.unknownError(http.statusCode)
        }
    }
}

// MARK: - API Errors

enum LicenseAPIError: LocalizedError {
    case invalidResponse
    case decodingFailed(Error)
    case unauthorized
    case forbidden
    case userNotFound
    case rateLimited
    case serverError(Int)
    case unknownError(Int)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from server"
        case .decodingFailed(let error): return "Failed to decode server response: \(error.localizedDescription)"
        case .unauthorized: return "Authentication failed"
        case .forbidden: return "Access denied"
        case .userNotFound: return "User account not found"
        case .rateLimited: return "Too many requests. Please try again later."
        case .serverError(let code): return "Server error (\(code)). Please try again later."
        case .unknownError(let code): return "Unknown error (\(code))"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unauthorized: return "Please sign in again"
        case .userNotFound: return "Please check your account status"
        case .rateLimited: return "Wait a few minutes before trying again"
        case .serverError, .unknownError: return "Check your internet connection and try again"
        case .networkError: return "Check your internet connection"
        default: return nil
        }
    }

    var shouldRetry: Bool {
        switch self {
        case .rateLimited, .serverError, .networkError:
            return true
        default:
            return false
        }
    }
}