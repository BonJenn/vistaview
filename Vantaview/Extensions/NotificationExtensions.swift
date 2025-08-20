import Foundation

extension Notification.Name {
    static let loadNewVideo = Notification.Name("loadNewVideo")
    
    // Raycast-style UI shortcuts
    static let toggleCommandPalette = Notification.Name("toggleCommandPalette")
    static let toggleLeftPanel = Notification.Name("toggleLeftPanel")
    static let toggleRightPanel = Notification.Name("toggleRightPanel")
    
    // NEW: LED Wall camera feed notifications
    static let showLEDWallCameraFeedModal = Notification.Name("showLEDWallCameraFeedModal")
    static let ledWallCameraFeedDisconnected = Notification.Name("ledWallCameraFeedDisconnected")
}