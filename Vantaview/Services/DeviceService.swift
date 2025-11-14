import Foundation

public struct DeviceConflict: Identifiable, Codable, Sendable {
    public let id = UUID()
    public let deviceName: String
    public let lastSeenAt: Date
}

public enum DeviceServiceError: LocalizedError, Sendable {
    case conflict(DeviceConflict)
    case invalidResponse
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .conflict: return "Device conflict"
        case .invalidResponse: return "Invalid response"
        case .http(let code): return "HTTP \(code)"
        }
    }
}

public actor DeviceService {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func registerDevice(sessionToken: String,
                               deviceID: String,
                               deviceName: String,
                               appVersion: String) async throws {
        try Task.checkCancellation()
        let url = LicenseConstants.websiteBaseURL.appendingPathComponent(LicenseConstants.deviceRegisterPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")).hasPrefix("api")
                                                                         ? String(LicenseConstants.deviceRegisterPath.dropFirst())
                                                                         : LicenseConstants.deviceRegisterPath)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "device_id": deviceID,
            "device_name": deviceName,
            "app_version": appVersion
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await session.data(for: req)
        try Task.checkCancellation()
        guard let http = resp as? HTTPURLResponse else { throw DeviceServiceError.invalidResponse }

        switch http.statusCode {
        case 200, 201, 204:
            return
        case 409:
            struct ConflictDTO: Codable {
                let active_device_name: String
                let active_last_seen: String
            }
            let dto = try? JSONDecoder().decode(ConflictDTO.self, from: data)
            let lastSeen = ISO8601DateFormatter().date(from: dto?.active_last_seen ?? "") ?? Date()
            let conflict = DeviceConflict(deviceName: dto?.active_device_name ?? "Another Mac", lastSeenAt: lastSeen)
            throw DeviceServiceError.conflict(conflict)
        default:
            throw DeviceServiceError.http(http.statusCode)
        }
    }

    public func transferDevice(sessionToken: String,
                               deviceID: String,
                               deviceName: String,
                               appVersion: String) async throws {
        try Task.checkCancellation()
        let url = LicenseConstants.websiteBaseURL.appendingPathComponent(LicenseConstants.deviceTransferPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")).hasPrefix("api")
                                                                         ? String(LicenseConstants.deviceTransferPath.dropFirst())
                                                                         : LicenseConstants.deviceTransferPath)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "device_id": deviceID,
            "device_name": deviceName,
            "app_version": appVersion
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, resp) = try await session.data(for: req)
        try Task.checkCancellation()
        guard let http = resp as? HTTPURLResponse else { throw DeviceServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw DeviceServiceError.http(http.statusCode) }
    }
}