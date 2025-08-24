//
//  CameraPermissionHelper.swift
//  Vantaview
//
//  Created by AI Assistant
//

import Foundation
import AVFoundation

/// Helper class for managing camera permissions
class CameraPermissionHelper {
    
    /// Check and request camera permission if needed
    static func checkAndRequestCameraPermission() async -> Bool {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch currentStatus {
        case .authorized:
            print("✅ Camera permission already granted")
            return true
            
        case .denied:
            print("❌ Camera permission denied")
            return false
            
        case .restricted:
            print("⚠️ Camera permission restricted")
            return false
            
        case .notDetermined:
            print("❓ Camera permission not determined - requesting...")
            return await AVCaptureDevice.requestAccess(for: .video)
            
        @unknown default:
            print("❓ Unknown camera permission status")
            return false
        }
    }
    
    /// Get current camera permission status
    static func getCurrentPermissionStatus() -> AVAuthorizationStatus {
        return AVCaptureDevice.authorizationStatus(for: .video)
    }
    
    /// Check if camera permission is granted
    static func isCameraPermissionGranted() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }
}