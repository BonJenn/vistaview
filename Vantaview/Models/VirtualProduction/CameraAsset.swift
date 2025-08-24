//
//  CameraAsset.swift
//  Vantaview
//
//  Created by Jonathan Benn on 7/18/25.
//

import Foundation
import SceneKit

// Note: CameraAsset is already defined in StudioSharedTypes.swift
// This file can contain camera-specific extensions or additional functionality

extension CameraAsset {
    var previewImage: String {
        switch type.lowercased() {
        case "broadcast": return "video.fill"
        case "cinema": return "video.3d"
        case "security": return "video.circle"
        case "ptz": return "video.badge.ellipsis"
        default: return "video"
        }
    }
    
    var recommendedDistance: Float {
        switch focalLength {
        case 0..<35: return 15.0  // Wide angle
        case 35..<85: return 8.0  // Standard
        case 85...: return 4.0    // Telephoto
        default: return 8.0
        }
    }
    
    static func forStudioType(_ studioType: String) -> [CameraAsset] {
        switch studioType.lowercased() {
        case "news":
            return [
                CameraAsset(name: "Main News Camera", focalLength: 50, fieldOfView: 60),
                CameraAsset(name: "Interview Camera", focalLength: 85, fieldOfView: 28),
                CameraAsset(name: "Wide Establishing", focalLength: 24, fieldOfView: 84)
            ]
        case "talkshow":
            return [
                CameraAsset(name: "Host Camera", focalLength: 50, fieldOfView: 60),
                CameraAsset(name: "Guest Camera", focalLength: 85, fieldOfView: 28),
                CameraAsset(name: "Wide Audience", focalLength: 28, fieldOfView: 75),
                CameraAsset(name: "Profile Shot", focalLength: 100, fieldOfView: 24)
            ]
        case "podcast":
            return [
                CameraAsset(name: "Wide Room Shot", focalLength: 28, fieldOfView: 75),
                CameraAsset(name: "Host Close-up", focalLength: 85, fieldOfView: 28),
                CameraAsset(name: "Guest Close-up", focalLength: 85, fieldOfView: 28)
            ]
        case "concert":
            return [
                CameraAsset(name: "Stage Wide", focalLength: 24, fieldOfView: 84),
                CameraAsset(name: "Performer Close", focalLength: 100, fieldOfView: 24),
                CameraAsset(name: "Audience Reaction", focalLength: 50, fieldOfView: 60),
                CameraAsset(name: "Side Stage", focalLength: 35, fieldOfView: 63),
                CameraAsset(name: "Overhead Rig", focalLength: 28, fieldOfView: 75)
            ]
        default:
            return predefinedCameras
        }
    }
}