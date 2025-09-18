import Foundation
import SwiftUI

// MARK: - Project Manifest

struct ProjectManifest: Codable, Sendable {
    let schemaVersion: Int
    var projectId: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    let appVersion: String
    var mediaPolicy: MediaPolicy
    
    enum MediaPolicy: String, Codable, CaseIterable {
        case copy = "copy"
        case link = "link"
        
        var displayName: String {
            switch self {
            case .copy: return "Copy into Project"
            case .link: return "Link to External"
            }
        }
    }
    
    init(title: String, mediaPolicy: MediaPolicy = .copy) {
        self.schemaVersion = 1
        self.projectId = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        self.mediaPolicy = mediaPolicy
    }
    
    mutating func markUpdated() {
        updatedAt = Date()
    }
}

// MARK: - Project Timeline

struct ProjectTimeline: Codable, Sendable {
    var sequences: [TimelineSequence]
    var layers: [TimelineLayer]
    var transitions: [TimelineTransition]
    var cueList: [CuePoint]
    
    init() {
        self.sequences = []
        self.layers = []
        self.transitions = []
        self.cueList = []
    }
}

struct TimelineSequence: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var startTime: TimeInterval
    var duration: TimeInterval
    var mediaFileId: UUID?
    var cameraDeviceId: String?
    
    init(name: String, startTime: TimeInterval, duration: TimeInterval) {
        self.id = UUID()
        self.name = name
        self.startTime = startTime
        self.duration = duration
    }
}

struct TimelineLayer: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var isVisible: Bool
    var opacity: Double
    var blendMode: String
    var transform: LayerTransform
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.isVisible = true
        self.opacity = 1.0
        self.blendMode = "normal"
        self.transform = LayerTransform()
    }
}

struct LayerTransform: Codable, Sendable {
    var x: Double = 0
    var y: Double = 0
    var width: Double = 1920
    var height: Double = 1080
    var rotation: Double = 0
    var scaleX: Double = 1
    var scaleY: Double = 1
}

struct TimelineTransition: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var type: TransitionType
    var duration: TimeInterval
    var parameters: [String: Double]
    
    enum TransitionType: String, Codable, CaseIterable {
        case cut = "cut"
        case fade = "fade"
        case dissolve = "dissolve"
        case slide = "slide"
        case wipe = "wipe"
    }
    
    init(name: String, type: TransitionType, duration: TimeInterval) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.duration = duration
        self.parameters = [:]
    }
}

struct CuePoint: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var timestamp: TimeInterval
    var action: CueAction
    var parameters: [String: String]
    
    enum CueAction: String, Codable, CaseIterable {
        case switchCamera = "switchCamera"
        case applyEffect = "applyEffect"
        case startTransition = "startTransition"
        case changeScene = "changeScene"
    }
    
    init(name: String, timestamp: TimeInterval, action: CueAction) {
        self.id = UUID()
        self.name = name
        self.timestamp = timestamp
        self.action = action
        self.parameters = [:]
    }
}

// MARK: - Project Routing

struct ProjectRouting: Codable, Sendable {
    var inputSources: [InputSource]
    var previewProgramMapping: PreviewProgramMapping
    var busConfiguration: BusConfiguration
    
    init() {
        self.inputSources = []
        self.previewProgramMapping = PreviewProgramMapping()
        self.busConfiguration = BusConfiguration()
    }
}

struct InputSource: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var type: SourceType
    var deviceId: String?
    var mediaFileId: UUID?
    var virtualCameraId: UUID?
    
    enum SourceType: String, Codable, CaseIterable {
        case camera = "camera"
        case mediaFile = "mediaFile"
        case virtualCamera = "virtualCamera"
        case screenCapture = "screenCapture"
    }
    
    init(name: String, type: SourceType) {
        self.id = UUID()
        self.name = name
        self.type = type
    }
}

struct PreviewProgramMapping: Codable, Sendable {
    var previewSourceId: UUID?
    var programSourceId: UUID?
    var transitionDuration: TimeInterval = 1.0
    var transitionType: TimelineTransition.TransitionType = .fade
}

struct BusConfiguration: Codable, Sendable {
    var audioBuses: [AudioBus]
    var videoBuses: [VideoBus]
    
    init() {
        self.audioBuses = []
        self.videoBuses = []
    }
}

struct AudioBus: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var level: Double
    var isMuted: Bool
    var inputSourceIds: [UUID]
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.level = 0.75
        self.isMuted = false
        self.inputSourceIds = []
    }
}

struct VideoBus: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var isActive: Bool
    var inputSourceIds: [UUID]
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.isActive = true
        self.inputSourceIds = []
    }
}

// MARK: - Project Mixer

struct ProjectMixer: Codable, Sendable {
    var audioBuses: [AudioBusConfig]
    var levels: [String: Double]
    var meterConfigs: [MeterConfig]
    
    init() {
        self.audioBuses = []
        self.levels = [:]
        self.meterConfigs = []
    }
}

struct AudioBusConfig: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var level: Double
    var isMuted: Bool
    var isSolo: Bool
    var effectChain: [String]
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.level = 0.75
        self.isMuted = false
        self.isSolo = false
        self.effectChain = []
    }
}

struct MeterConfig: Codable, Identifiable, Sendable {
    let id: UUID
    var busId: UUID
    var type: MeterType
    var position: MeterPosition
    
    enum MeterType: String, Codable, CaseIterable {
        case vu = "vu"
        case peak = "peak"
        case rms = "rms"
    }
    
    enum MeterPosition: String, Codable, CaseIterable {
        case left = "left"
        case right = "right"
        case center = "center"
    }
    
    init(busId: UUID, type: MeterType, position: MeterPosition) {
        self.id = UUID()
        self.busId = busId
        self.type = type
        self.position = position
    }
}

// MARK: - Project Effects

struct ProjectEffects: Codable, Sendable {
    var pipConfigs: [PiPConfig]
    var chromaKeyConfigs: [ChromaKeyConfig]
    var filterConfigs: [FilterConfig]
    var effectParameters: [String: EffectParameterSet]
    
    init() {
        self.pipConfigs = []
        self.chromaKeyConfigs = []
        self.filterConfigs = []
        self.effectParameters = [:]
    }
}

struct PiPConfig: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var sourceId: UUID
    var position: CGRect
    var borderWidth: Double
    var borderColor: String
    var cornerRadius: Double
    var isEnabled: Bool
    
    init(name: String, sourceId: UUID) {
        self.id = UUID()
        self.name = name
        self.sourceId = sourceId
        self.position = CGRect(x: 0.7, y: 0.7, width: 0.25, height: 0.25)
        self.borderWidth = 2.0
        self.borderColor = "#FFFFFF"
        self.cornerRadius = 8.0
        self.isEnabled = true
    }
}

struct ChromaKeyConfig: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var sourceId: UUID
    var keyColor: String
    var tolerance: Double
    var featherAmount: Double
    var spillSuppression: Double
    var isEnabled: Bool
    
    init(name: String, sourceId: UUID) {
        self.id = UUID()
        self.name = name
        self.sourceId = sourceId
        self.keyColor = "#00FF00"
        self.tolerance = 0.3
        self.featherAmount = 0.1
        self.spillSuppression = 0.2
        self.isEnabled = true
    }
}

struct FilterConfig: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var type: FilterType
    var sourceId: UUID?
    var parameters: [String: Double]
    var isEnabled: Bool
    
    enum FilterType: String, Codable, CaseIterable {
        case blur = "blur"
        case sharpen = "sharpen"
        case colorCorrection = "colorCorrection"
        case exposure = "exposure"
        case saturation = "saturation"
        case contrast = "contrast"
        case vignette = "vignette"
    }
    
    init(name: String, type: FilterType) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.parameters = [:]
        self.isEnabled = true
    }
}

struct EffectParameterSet: Codable, Sendable {
    var parameters: [String: ProjectEffectParameter]
    
    init() {
        self.parameters = [:]
    }
}

struct ProjectEffectParameter: Codable, Sendable {
    var name: String
    var value: Double
    var minValue: Double
    var maxValue: Double
    var defaultValue: Double
    
    init(name: String, value: Double, min: Double = 0, max: Double = 1, defaultValue: Double = 0) {
        self.name = name
        self.value = value
        self.minValue = min
        self.maxValue = max
        self.defaultValue = defaultValue
    }
}

// MARK: - Project Media Reference

struct ProjectMediaReference: Codable, Identifiable, Sendable {
    let id: UUID
    var originalPath: String
    var relativePath: String?
    var absolutePath: String?
    var fileName: String
    var fileSize: Int64
    var duration: TimeInterval?
    var mediaType: MediaType
    var thumbnailPath: String?
    var isLinked: Bool
    var lastModified: Date
    var fileBookmark: Data?
    
    enum MediaType: String, Codable, CaseIterable {
        case video = "video"
        case audio = "audio"
        case image = "image"
    }
    
    init(originalPath: String, fileName: String, mediaType: MediaType, isLinked: Bool = false) {
        self.id = UUID()
        self.originalPath = originalPath
        self.fileName = fileName
        self.fileSize = 0
        self.mediaType = mediaType
        self.isLinked = isLinked
        self.lastModified = Date()
    }
    
    var resolvedPath: String? {
        return relativePath ?? absolutePath ?? originalPath
    }
}

// MARK: - Project Template

enum ProjectTemplate: String, CaseIterable, Identifiable {
    case blank = "blank"
    case news = "news"
    case talkShow = "talkShow"
    case podcast = "podcast"
    case gaming = "gaming"
    case concert = "concert"
    case productDemo = "productDemo"
    case webinar = "webinar"
    case interview = "interview"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .blank: return "Blank Project"
        case .news: return "News Studio"
        case .talkShow: return "Talk Show"
        case .podcast: return "Podcast"
        case .gaming: return "Gaming Stream"
        case .concert: return "Concert/Performance"
        case .productDemo: return "Product Demo"
        case .webinar: return "Webinar"
        case .interview: return "Interview Setup"
        }
    }
    
    var description: String {
        switch self {
        case .blank: return "Start with an empty project"
        case .news: return "Professional news broadcasting setup"
        case .talkShow: return "Multi-camera talk show configuration"
        case .podcast: return "Audio-focused podcast recording"
        case .gaming: return "Gaming stream with overlays"
        case .concert: return "Live performance with multiple angles"
        case .productDemo: return "Product demonstration setup"
        case .webinar: return "Webinar and presentation layout"
        case .interview: return "Two-person interview setup"
        }
    }
    
    var icon: String {
        switch self {
        case .blank: return "doc"
        case .news: return "tv"
        case .talkShow: return "person.2"
        case .podcast: return "mic"
        case .gaming: return "gamecontroller"
        case .concert: return "music.note"
        case .productDemo: return "cube.box"
        case .webinar: return "presentation"
        case .interview: return "person.2.circle"
        }
    }
    
    var resolution: CGSize {
        switch self {
        case .blank, .news, .talkShow, .concert, .productDemo, .webinar, .interview:
            return CGSize(width: 1920, height: 1080)
        case .podcast:
            return CGSize(width: 1280, height: 720)
        case .gaming:
            return CGSize(width: 1920, height: 1080)
        }
    }
    
    var frameRate: Double {
        switch self {
        case .blank, .news, .talkShow, .podcast, .productDemo, .webinar, .interview:
            return 30.0
        case .gaming, .concert:
            return 60.0
        }
    }
}