//
//  LicenseTypes.swift
//  Vantaview
//
//  Created by Vantaview on 12/19/24.
//

import Foundation

// MARK: - Plan Tiers

/// Subscription tiers available in Vantaview
enum PlanTier: String, CaseIterable, Codable {
    case stream = "stream"
    case live = "live" 
    case stage = "stage"
    case pro = "pro"
    
    var displayName: String {
        switch self {
        case .stream: return "Stream"
        case .live: return "Live"
        case .stage: return "Stage" 
        case .pro: return "Pro"
        }
    }
    
    var monthlyPrice: Int {
        switch self {
        case .stream: return 19
        case .live: return 49
        case .stage: return 99
        case .pro: return 199
        }
    }
    
    var description: String {
        switch self {
        case .stream: return "Real-time playback with basic controls"
        case .live: return "Advanced media control and multi-screen output"
        case .stage: return "3D Virtual Sets and LED wall tools"
        case .pro: return "AI-driven switching and broadcast optimization"
        }
    }
}

// MARK: - Feature Keys

/// All features that can be gated by subscription tier
enum FeatureKey: String, CaseIterable, Codable {
    // Stream tier features
    case realtimePlayback = "realtime_playback"
    case previewProgram = "preview_program"
    case letterboxVertical = "letterbox_vertical"
    case basicControls = "basic_controls"
    
    // Live tier features
    case advMediaControl = "adv_media_control"
    case multiScreen = "multi_screen"
    case effectsBasic = "effects_basic"
    case previewProgramIndependent = "preview_program_independent"
    
    // Stage tier features
    case virtualSet3D = "virtual_set_3d"
    case ledWallTools = "led_wall_tools"
    case aspectRatioSafeScale = "aspect_ratio_safe_scale"
    case manualGrabScale = "manual_grab_scale"
    
    // Pro tier features
    case aiCameraSwitch = "ai_camera_switch"
    case fxPremium = "fx_premium"
    case automation = "automation"
    case broadcastOptim = "broadcast_optim"
    
    var displayName: String {
        switch self {
        case .realtimePlayback: return "Real-time Playback"
        case .previewProgram: return "Preview + Program Panes"
        case .letterboxVertical: return "Vertical Letterboxing"
        case .basicControls: return "Basic Transport Controls"
        case .advMediaControl: return "Advanced Media Control"
        case .multiScreen: return "Multi-screen Output"
        case .effectsBasic: return "Customizable Effects"
        case .previewProgramIndependent: return "Independent Preview/Program"
        case .virtualSet3D: return "3D Virtual Set Builder"
        case .ledWallTools: return "LED Wall Tools"
        case .aspectRatioSafeScale: return "Aspect-ratio Safe Scaling"
        case .manualGrabScale: return "Manual Grab/Scale Positioning"
        case .aiCameraSwitch: return "AI-driven Camera Switching"
        case .fxPremium: return "Premium FX Library"
        case .automation: return "Automation Workflows"
        case .broadcastOptim: return "Broadcast-grade Optimizations"
        }
    }
    
    var description: String {
        switch self {
        case .realtimePlayback: return "Core real-time video playback engine"
        case .previewProgram: return "Dual-pane preview and program workflow"
        case .letterboxVertical: return "Proper letterboxing for vertical media"
        case .basicControls: return "Play, pause, seek, and basic transport"
        case .advMediaControl: return "Cue points, crossfades, and playlists"
        case .multiScreen: return "Route program to multiple displays"
        case .effectsBasic: return "Color correction and basic filters"
        case .previewProgramIndependent: return "Separate render pipelines, no mirroring"
        case .virtualSet3D: return "Build and control 3D virtual environments"
        case .ledWallTools: return "LED wall layout editor and calibration"
        case .aspectRatioSafeScale: return "Maintain aspect ratios during scaling"
        case .manualGrabScale: return "Interactive drag and zoom controls"
        case .aiCameraSwitch: return "Intelligent automated camera switching"
        case .fxPremium: return "Professional-grade visual effects library"
        case .automation: return "Timeline-based automation and triggers"
        case .broadcastOptim: return "Professional broadcast codecs and optimization"
        }
    }
}

// MARK: - Feature Matrix

/// Maps subscription tiers to their enabled features
struct FeatureMatrix {
    
    /// Get all features enabled for a specific tier
    static func features(for tier: PlanTier) -> Set<FeatureKey> {
        switch tier {
        case .stream:
            return streamFeatures
        case .live:
            return streamFeatures.union(liveFeatures)
        case .stage:
            return streamFeatures.union(liveFeatures).union(stageFeatures)
        case .pro:
            return streamFeatures.union(liveFeatures).union(stageFeatures).union(proFeatures)
        }
    }
    
    /// Check if a feature is enabled for a specific tier
    static func isEnabled(_ feature: FeatureKey, for tier: PlanTier) -> Bool {
        return features(for: tier).contains(feature)
    }
    
    /// Get the minimum tier required for a feature
    static func minimumTier(for feature: FeatureKey) -> PlanTier {
        for tier in PlanTier.allCases {
            if isEnabled(feature, for: tier) {
                return tier
            }
        }
        return .pro // Fallback to highest tier
    }
    
    // MARK: - Private Feature Sets
    
    private static let streamFeatures: Set<FeatureKey> = [
        .realtimePlayback,
        .previewProgram,
        .letterboxVertical,
        .basicControls
    ]
    
    private static let liveFeatures: Set<FeatureKey> = [
        .advMediaControl,
        .multiScreen,
        .effectsBasic,
        .previewProgramIndependent
    ]
    
    private static let stageFeatures: Set<FeatureKey> = [
        .virtualSet3D,
        .ledWallTools,
        .aspectRatioSafeScale,
        .manualGrabScale
    ]
    
    private static let proFeatures: Set<FeatureKey> = [
        .aiCameraSwitch,
        .fxPremium,
        .automation,
        .broadcastOptim
    ]
}

// MARK: - Feature Gate Protocol

/// Protocol for checking feature availability
protocol FeatureGate {
    /// Check if a specific feature is enabled
    func isEnabled(_ feature: FeatureKey) -> Bool
    
    /// Current subscription tier
    var currentTier: PlanTier? { get }
}

// MARK: - License Status

/// Current status of the user's license
enum LicenseStatus: Equatable {
    case unknown
    case trial(daysRemaining: Int)
    case active
    case grace(hoursRemaining: Int)
    case expired
    case error(String)
    
    var displayText: String {
        switch self {
        case .unknown:
            return "License status unknown"
        case .trial(let days):
            return "Trial: \(days) days remaining"
        case .active:
            return "Active subscription"
        case .grace(let hours):
            return "Grace period: \(hours) hours remaining"
        case .expired:
            return "Subscription expired"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    var isValid: Bool {
        switch self {
        case .active, .trial, .grace:
            return true
        case .unknown, .expired, .error:
            return false
        }
    }
    
    var needsAttention: Bool {
        switch self {
        case .trial(let days) where days <= 3:
            return true
        case .grace:
            return true
        case .expired, .error:
            return true
        default:
            return false
        }
    }
}

// MARK: - License DTO

/// Data transfer object for license information from server
struct LicenseDTO: Codable {
    let tier: String
    let expiresAt: Date
    let isTrial: Bool
    let trialEndsAt: Date?
    let signedJWT: String
    
    var planTier: PlanTier? {
        return PlanTier(rawValue: tier)
    }
}

// MARK: - License Cache

/// Cached license information stored locally
struct CachedLicense: Codable {
    let tier: PlanTier
    let expiresAt: Date
    let isTrial: Bool
    let trialEndsAt: Date?
    let cachedAt: Date
    let etag: String?
    
    var isExpired: Bool {
        return Date() > expiresAt
    }
    
    var isInGracePeriod: Bool {
        guard isExpired else { return false }
        let graceEndTime = expiresAt.addingTimeInterval(TimeInterval(LicenseConstants.graceHoursDefault * 3600))
        return Date() < graceEndTime
    }
    
    var gracePeriodHoursRemaining: Int {
        guard isInGracePeriod else { return 0 }
        let graceEndTime = expiresAt.addingTimeInterval(TimeInterval(LicenseConstants.graceHoursDefault * 3600))
        let remaining = graceEndTime.timeIntervalSince(Date())
        return max(0, Int(remaining / 3600))
    }
    
    var trialDaysRemaining: Int? {
        guard isTrial, let trialEnd = trialEndsAt else { return nil }
        let remaining = trialEnd.timeIntervalSince(Date())
        return max(0, Int(remaining / 86400)) // 86400 seconds in a day
    }
}