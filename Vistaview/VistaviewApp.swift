import SwiftUI
import Cocoa

@main
struct VistaviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1400, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
        
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var hasInitializedWindows = false
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        print("🚀 Application will finish launching")
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("✅ Application did finish launching")
        
        // SINGLE window placement check instead of 5 repeated ones
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.setupWindowsOnce()
        }
    }
    
    private func setupWindowsOnce() {
        guard !hasInitializedWindows else { return }
        hasInitializedWindows = true
        
        print("🔧 Setting up windows once")
        
        // Simple, efficient window setup
        if let mainWindow = NSApplication.shared.mainWindow {
            positionMainWindow(mainWindow)
        }
    }
    
    private func positionMainWindow(_ window: NSWindow) {
        guard let mainScreen = NSScreen.main else { return }
        
        let screenFrame = mainScreen.visibleFrame
        let windowSize = CGSize(width: 1400, height: 900)
        
        let centeredFrame = CGRect(
            x: screenFrame.midX - windowSize.width / 2,
            y: screenFrame.midY - windowSize.height / 2,
            width: windowSize.width,
            height: windowSize.height
        )
        
        window.setFrame(centeredFrame, display: true, animate: false)
        print("✅ Positioned main window efficiently")
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        // Only reposition if we haven't done initial setup
        if !hasInitializedWindows {
            setupWindowsOnce()
        }
    }
    
    /// Simple method to get external display for ExternalDisplayManager
    func getExternalDisplay() -> NSScreen? {
        let externalScreens = NSScreen.screens.filter { $0 != NSScreen.main }
        return externalScreens.first
    }
}