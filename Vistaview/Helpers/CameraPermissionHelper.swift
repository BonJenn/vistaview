//
//  CameraPermissionHelper.swift
//  Vistaview
//
//  Created by AI Assistant
//

import Foundation
import AVFoundation
import AppKit

@MainActor
class CameraPermissionHelper {
    
    static func checkAndRequestCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        print("📹 Camera permission status: \(status.rawValue)")
        
        switch status {
        case .authorized:
            print("✅ Camera permission already granted")
            return true
            
        case .notDetermined:
            print("❓ Camera permission not determined - requesting...")
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            print(granted ? "✅ Camera permission granted!" : "❌ Camera permission denied")
            return granted
            
        case .denied:
            print("❌ Camera permission denied - user needs to enable in System Preferences")
            return false
            
        case .restricted:
            print("⚠️ Camera permission restricted")
            return false
            
        @unknown default:
            print("❓ Unknown camera permission status")
            return false
        }
    }
    
    static func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Camera Permission Required"
        alert.informativeText = "Vistaview needs camera access to show live previews. Please enable camera access in System Preferences > Security & Privacy > Camera."
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}