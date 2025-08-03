import Foundation

/// Represents a media file that can be loaded into preview/program
struct MediaFile: Identifiable, Equatable, Codable {
    let id: UUID
    let name: String
    let url: URL
    let duration: TimeInterval?
    let fileType: MediaFileType
    
    enum MediaFileType: String, CaseIterable, Codable {
        case video = "video"
        case audio = "audio"
        case image = "image"
        
        var icon: String {
            switch self {
            case .video: return "video.fill"
            case .audio: return "waveform"
            case .image: return "photo.fill"
            }
        }
    }
    
    init(name: String, url: URL, fileType: MediaFileType, duration: TimeInterval? = nil) {
        self.id = UUID()
        self.name = name
        self.url = url
        self.fileType = fileType
        self.duration = duration
    }
    
    // Codable conformance
    enum CodingKeys: String, CodingKey {
        case id, name, url, duration, fileType
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        let urlString = try container.decode(String.self, forKey: .url)
        self.url = URL(string: urlString) ?? URL(fileURLWithPath: "")
        self.duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        self.fileType = try container.decode(MediaFileType.self, forKey: .fileType)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(url.absoluteString, forKey: .url)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encode(fileType, forKey: .fileType)
    }
    
    static func == (lhs: MediaFile, rhs: MediaFile) -> Bool {
        return lhs.id == rhs.id
    }
}
