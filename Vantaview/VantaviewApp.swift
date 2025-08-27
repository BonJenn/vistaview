import SwiftUI
import Cocoa

@main
struct VantaviewApp: App {
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var licenseManager = LicenseManager()
    
    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    ContentView()
                        .environmentObject(licenseManager)
                        .onAppear {
                            setupLicensing()
                        }
                        .onChange(of: authManager.accessToken) { _, newToken in
                            if let token = newToken {
                                Task {
                                    await licenseManager.refreshLicense(sessionToken: token, userID: authManager.userID)
                                }
                            }
                        }
                        .frame(minWidth: 1200, minHeight: 800) // Full app size
                } else {
                    SignInView(authManager: authManager)
                        .frame(width: 400, height: 650) // Adjusted for proper fit
                }
            }
            .environmentObject(authManager)
        }
        .windowResizability(authManager.isAuthenticated ? .contentSize : .contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                if authManager.isAuthenticated {
                    Button("Account...") {
                        showAccountWindow()
                    }
                    .keyboardShortcut(",", modifiers: .command)
                    
                    Divider()
                    
                    Button("Sign Out") {
                        Task {
                            await authManager.signOut()
                        }
                    }
                    .keyboardShortcut("q", modifiers: [.command, .shift])
                    
                    #if DEBUG
                    Menu("Debug License") {
                        Button("Stream Tier") { licenseManager.debugImpersonatedTier = .stream }
                        Button("Live Tier") { licenseManager.debugImpersonatedTier = .live }
                        Button("Stage Tier") { licenseManager.debugImpersonatedTier = .stage }
                        Button("Pro Tier") { licenseManager.debugImpersonatedTier = .pro }
                        Button("Clear Debug") { licenseManager.debugImpersonatedTier = nil }
                        Divider()
                        Button("Simulate Offline") { licenseManager.debugOfflineMode.toggle() }
                        Button("Simulate Expired") { licenseManager.debugExpiredMode.toggle() }
                    }
                    #endif
                }
            }
        }
    }
    
    private func setupLicensing() {
        guard let userID = authManager.userID,
              let sessionToken = authManager.accessToken else {
            return
        }
        
        #if DEBUG
        licenseManager.debugImpersonatedTier = .pro
        licenseManager.debugOfflineMode = false
        licenseManager.debugExpiredMode = false
        #endif
        
        // Set current user for license caching
        licenseManager.setCurrentUser(userID)
        
        // Fetch initial license
        Task {
            await licenseManager.refreshLicense(sessionToken: sessionToken, userID: userID)
        }
        
        // Start automatic refresh with real session token
        licenseManager.startAutomaticRefresh(sessionToken: sessionToken)
    }
    
    private func showAccountWindow() {
        let accountWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        accountWindow.title = "Account"
        accountWindow.contentView = NSHostingView(
            rootView: AccountView(licenseManager: licenseManager)
                .environmentObject(authManager)
        )
        accountWindow.center()
        accountWindow.makeKeyAndOrderFront(nil)
    }
}