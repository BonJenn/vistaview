import SwiftUI
import Cocoa
import os

@MainActor
@main
struct VantaviewApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var licenseManager = LicenseManager()
    
    private let logger = Logger(subsystem: "app.vantaview", category: "App")
    
    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    ContentView()
                        .environmentObject(licenseManager)
                        .task {
                            await bootstrapLicensing()
                        }
                        .task(id: authManager.accessToken) {
                            await handleTokenChange()
                        }
                        .frame(minWidth: 1200, minHeight: 800)
                } else {
                    SignInView(authManager: authManager)
                        .frame(width: 400, height: 650)
                }
            }
            .environmentObject(authManager)
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    guard authManager.isAuthenticated,
                          let token = authManager.accessToken,
                          let userID = authManager.userID else { return }
                    licenseManager.startAutomaticRefresh(sessionToken: token, userID: userID)
                case .inactive, .background:
                    licenseManager.stopAutomaticRefresh()
                @unknown default:
                    licenseManager.stopAutomaticRefresh()
                }
            }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                if authManager.isAuthenticated {
                    Button("Project Hub...") {
                        showProjectHubWindow()
                    }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                    
                    Divider()
                    
                    Button("Account...") {
                        showAccountWindow()
                    }
                    .keyboardShortcut(",", modifiers: .command)
                    
                    Divider()
                    
                    Button("Sign Out") {
                        licenseManager.stopAutomaticRefresh()
                        Task {
                            try? Task.checkCancellation()
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
    
    private func bootstrapLicensing() async {
        do {
            try Task.checkCancellation()
            guard authManager.isAuthenticated,
                  let token = authManager.accessToken,
                  let userID = authManager.userID else {
                return
            }
            
            licenseManager.setCurrentUser(userID)
            try await licenseManager.refreshLicense(sessionToken: token, userID: userID)
            licenseManager.startAutomaticRefresh(sessionToken: token, userID: userID)
        } catch is CancellationError {
            logger.debug("bootstrapLicensing cancelled")
        } catch {
            logger.error("bootstrapLicensing failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func handleTokenChange() async {
        do {
            try Task.checkCancellation()
            guard authManager.isAuthenticated else {
                licenseManager.stopAutomaticRefresh()
                licenseManager.setCurrentUser(nil)
                return
            }
            guard let token = authManager.accessToken,
                  let userID = authManager.userID else {
                licenseManager.stopAutomaticRefresh()
                return
            }
            licenseManager.setCurrentUser(userID)
            try await licenseManager.refreshLicense(sessionToken: token, userID: userID)
            licenseManager.startAutomaticRefresh(sessionToken: token, userID: userID)
        } catch is CancellationError {
            logger.debug("handleTokenChange cancelled")
        } catch {
            logger.error("handleTokenChange failed: \(error.localizedDescription, privacy: .public)")
        }
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
    
    private func showProjectHubWindow() {
        let projectHubWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        projectHubWindow.title = "Project Hub"
        projectHubWindow.contentView = NSHostingView(
            rootView: ProjectHub()
                .environmentObject(authManager)
        )
        projectHubWindow.center()
        projectHubWindow.makeKeyAndOrderFront(nil)
    }
}