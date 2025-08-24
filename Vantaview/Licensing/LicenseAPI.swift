//
//  LicenseAPI.swift
//  Vantaview
//
//  Created by Vantaview on 12/19/24.
//

import Foundation

/// API client for license operations
actor LicenseAPI {
    
    private let session: URLSession
    private let baseURL: URL
    
    init(session: URLSession = .shared, baseURL: URL = SupabaseConfig.licenseVerificationURL) {
        self.session = session
        self.baseURL = baseURL
    }
    
    /// Fetch license information from server using real Supabase session
    func fetchTier(sessionToken: String) async throws -> LicenseDTO {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        
        // Send the session token to verify and get subscription info
        let requestBody = [
            "action": "verify_license"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        if LicenseConstants.debugLoggingEnabled {
            print("🔐 LicenseAPI: Fetching tier from \(baseURL)")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseAPIError.invalidResponse
        }
        
        if LicenseConstants.debugLoggingEnabled {
            print("🔐 LicenseAPI: Response status \(httpResponse.statusCode)")
        }
        
        switch httpResponse.statusCode {
        case 200:
            do {
                let licenseDTO = try JSONDecoder().decode(LicenseDTO.self, from: data)
                if LicenseConstants.debugLoggingEnabled {
                    print("🔐 LicenseAPI: Successfully decoded tier: \(licenseDTO.tier)")
                }
                return licenseDTO
            } catch {
                if LicenseConstants.debugLoggingEnabled {
                    print("🔐 LicenseAPI: Failed to decode response: \(error)")
                }
                throw LicenseAPIError.decodingFailed(error)
            }
            
        case 401:
            throw LicenseAPIError.unauthorized
            
        case 403:
            throw LicenseAPIError.forbidden
            
        case 404:
            throw LicenseAPIError.userNotFound
            
        case 429:
            throw LicenseAPIError.rateLimited
            
        case 500...599:
            throw LicenseAPIError.serverError(httpResponse.statusCode)
            
        default:
            throw LicenseAPIError.unknownError(httpResponse.statusCode)
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
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingFailed(let error):
            return "Failed to decode server response: \(error.localizedDescription)"
        case .unauthorized:
            return "Authentication failed"
        case .forbidden:
            return "Access denied"
        case .userNotFound:
            return "User account not found"
        case .rateLimited:
            return "Too many requests. Please try again later."
        case .serverError(let code):
            return "Server error (\(code)). Please try again later."
        case .unknownError(let code):
            return "Unknown error (\(code))"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .unauthorized:
            return "Please sign in again"
        case .userNotFound:
            return "Please check your account status"
        case .rateLimited:
            return "Wait a few minutes before trying again"
        case .serverError, .unknownError:
            return "Check your internet connection and try again"
        case .networkError:
            return "Check your internet connection"
        default:
            return nil
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