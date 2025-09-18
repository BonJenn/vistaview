import SwiftUI
import Cocoa
import os

@MainActor
@main
struct VantaviewApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var licenseManager = LicenseManager()
    @StateObject private var projectCoordinator = ProjectCoordinator()
    
    private let logger = Logger(subsystem: "app.vantaview", category: "App")
    
    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    if projectCoordinator.hasOpenProject {
                        // Main content view with active project
                        ContentView()
                            .environmentObject(licenseManager)
                            .environmentObject(projectCoordinator)
                            .task {
                                await bootstrapLicensing()
                            }
                            .task(id: authManager.accessToken) {
                                await handleTokenChange()
                            }
                            .frame(minWidth: 1200, minHeight: 800)
                    } else {
                        // Project Hub when no project is open
                        ProjectHub()
                            .environmentObject(authManager)
                            .environmentObject(projectCoordinator)
                            .frame(minWidth: 1000, minHeight: 700)
                    }
                } else {
                    SignInView(authManager: authManager)
                        .frame(width: 400, height: 650)
                }
            }
            .environmentObject(authManager)
            .environmentObject(projectCoordinator)
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
            CommandGroup(after: .newItem) {
                if authManager.isAuthenticated {
                    Button("New Project...") {
                        // This will show Project Hub
                        Task {
                            await projectCoordinator.closeCurrentProject()
                        }
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    
                    Button("Open Project...") {
                        showOpenProjectDialog()
                    }
                    .keyboardShortcut("o", modifiers: .command)
                    
                    if projectCoordinator.hasOpenProject {
                        Button("Close Project") {
                            Task {
                                await projectCoordinator.closeCurrentProject()
                            }
                        }
                        .keyboardShortcut("w", modifiers: .command)
                    }
                }
            }
            
            CommandGroup(after: .saveItem) {
                if authManager.isAuthenticated && projectCoordinator.hasOpenProject {
                    Button("Save Project") {
                        Task {
                            try? await projectCoordinator.saveCurrentProject()
                        }
                    }
                    .keyboardShortcut("s", modifiers: .command)
                }
            }
            
            CommandGroup(after: .appInfo) {
                if authManager.isAuthenticated {
                    Button("Project Hub...") {
                        Task {
                            await projectCoordinator.closeCurrentProject()
                        }
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
    
    private func showOpenProjectDialog() {
        let panel = NSOpenPanel()
        panel.title = "Open Project"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.init("com.vantaview.project")].compactMap { $0 }
        
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                try? await projectCoordinator.openProject(at: url)
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