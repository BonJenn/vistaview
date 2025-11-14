import SwiftUI
import Cocoa
import os

@MainActor
@main
struct VantaviewApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var licenseManager = LicenseManager()
    @State private var deviceConflict: DeviceConflict?
    @State private var pendingToken: String?
    @State private var pendingUserID: String?
    @State private var showTransferSuccess: Bool = false

    private let deviceService = DeviceService()
    private let logger = Logger(subsystem: "app.vantaview", category: "App")

    var body: some Scene {
        WindowGroup(id: "main") {
            Group {
                if authManager.isAuthenticated {
                    if projectCoordinator.hasOpenProject {
                        ContentView()
                            .environmentObject(licenseManager)
                            .environmentObject(projectCoordinator)
                            .task { await bootstrapFlow() }
                            .task(id: authManager.accessToken) { await handleTokenChange() }
                    } else {
                        ProjectHub()
                            .environmentObject(authManager)
                            .environmentObject(projectCoordinator)
                    }
                } else {
                    SignInView(authManager: authManager)
                }
            }
            .environmentObject(authManager)
            .environmentObject(projectCoordinator)
            .frame(
                minWidth: authManager.isAuthenticated ? (projectCoordinator.hasOpenProject ? 1200 : 1000) : 400,
                minHeight: authManager.isAuthenticated ? (projectCoordinator.hasOpenProject ? 800 : 700) : 650
            )
            .sheet(item: $deviceConflict) { conflict in
                DeviceConflictSheet(conflict: conflict) {
                    Task {
                        await handleTransfer()
                    }
                } onCancel: {
                    deviceConflict = nil
                }
            }
            .alert("Transferred to this Mac", isPresented: $showTransferSuccess) {
                Button("OK", role: .cancel) { }
            }
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
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .onAppear {
                // Ensure only one window exists
                if let window = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: Set(arrayLiteral: "main"))
        .commands {
            CommandGroup(after: .newItem) {
                if authManager.isAuthenticated {
                    Button("New Project...") {
                        Task { await projectCoordinator.closeCurrentProject() }
                    }
                    .keyboardShortcut("n", modifiers: .command)

                    Button("Open Project...") {
                        showOpenProjectDialog()
                    }
                    .keyboardShortcut("o", modifiers: .command)

                    if projectCoordinator.hasOpenProject {
                        Button("Close Project") {
                            Task { await projectCoordinator.closeCurrentProject() }
                        }
                        .keyboardShortcut("w", modifiers: .command)
                    }
                }
            }

            CommandGroup(after: .saveItem) {
                if authManager.isAuthenticated && projectCoordinator.hasOpenProject {
                    Button("Save Project") {
                        Task { try? await projectCoordinator.saveCurrentProject() }
                    }
                    .keyboardShortcut("s", modifiers: .command)
                }
            }

            CommandGroup(after: .appInfo) {
                if authManager.isAuthenticated {
                    Button("Project Hub...") {
                        Task { await projectCoordinator.closeCurrentProject() }
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

    @StateObject private var projectCoordinator = ProjectCoordinator()

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

    private func showAccountWindow() {
        AccountWindowController.show(licenseManager: licenseManager, authManager: authManager)
    }

    private func bootstrapFlow() async {
        do {
            try Task.checkCancellation()
            guard authManager.isAuthenticated,
                  let token = authManager.accessToken,
                  let userID = authManager.userID else {
                return
            }
            try await registerAndRefresh(token: token, userID: userID)
        } catch is CancellationError {
        } catch {
            logger.error("bootstrapFlow failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleTokenChange() async {
        do {
            try Task.checkCancellation()
            guard authManager.isAuthenticated,
                  let token = authManager.accessToken,
                  let userID = authManager.userID else {
                licenseManager.stopAutomaticRefresh()
                licenseManager.setCurrentUser(nil)
                return
            }
            try await registerAndRefresh(token: token, userID: userID)
        } catch is CancellationError {
        } catch {
            logger.error("handleTokenChange failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func registerAndRefresh(token: String, userID: String) async throws {
        pendingToken = token
        pendingUserID = userID

        let deviceID = DeviceID.deviceID()
        let deviceName = DeviceID.deviceName()
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

        do {
            try await deviceService.registerDevice(sessionToken: token,
                                                   deviceID: deviceID,
                                                   deviceName: deviceName,
                                                   appVersion: appVersion)
        } catch DeviceServiceError.conflict(let conflict) {
            deviceConflict = conflict
            return
        }

        licenseManager.setCurrentUser(userID)
        try await licenseManager.refreshLicense(sessionToken: token, userID: userID)
        licenseManager.startAutomaticRefresh(sessionToken: token, userID: userID)
    }

    private func handleTransfer() async {
        guard let token = pendingToken else { return }
        let deviceID = DeviceID.deviceID()
        let deviceName = DeviceID.deviceName()
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

        do {
            try await deviceService.transferDevice(sessionToken: token,
                                                   deviceID: deviceID,
                                                   deviceName: deviceName,
                                                   appVersion: appVersion)
            deviceConflict = nil
            showTransferSuccess = true

            if let token = pendingToken, let userID = pendingUserID {
                licenseManager.setCurrentUser(userID)
                try await licenseManager.refreshLicense(sessionToken: token, userID: userID)
                licenseManager.startAutomaticRefresh(sessionToken: token, userID: userID)
            }
        } catch {
            logger.error("Device transfer failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleDeepLink(_ url: URL) {
        logger.info("🔗 Deep link received: \(url.absoluteString, privacy: .public)")
        print("🔗 Deep link received: \(url.absoluteString)")

        // Expected format: vantaview://auth?access_token=...&user_id=...
        guard url.scheme == "vantaview" else {
            logger.warning("Invalid URL scheme: \(url.scheme ?? "none", privacy: .public)")
            print("❌ Invalid URL scheme: \(url.scheme ?? "none")")
            return
        }

        guard url.host == "auth" else {
            logger.warning("Unknown deep link host: \(url.host ?? "none", privacy: .public)")
            print("❌ Unknown deep link host: \(url.host ?? "none")")
            return
        }

        // Parse query parameters
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            logger.error("Failed to parse deep link URL")
            print("❌ Failed to parse deep link URL")
            return
        }

        var accessToken: String?
        var userID: String?

        for item in queryItems {
            switch item.name {
            case "access_token":
                accessToken = item.value
            case "user_id":
                userID = item.value
            default:
                break
            }
        }

        guard let token = accessToken, !token.isEmpty,
              let uid = userID, !uid.isEmpty else {
            logger.error("Missing access_token or user_id in deep link")
            print("❌ Missing access_token or user_id in deep link")
            return
        }

        logger.info("✅ Deep link auth successful for user: \(uid, privacy: .public)")
        logger.info("📊 Token preview: \(String(token.prefix(20)), privacy: .public)...")
        print("✅ Deep link parsed successfully!")
        print("📊 User ID: \(uid)")
        print("📊 Token length: \(token.count)")

        // Sign in with the token
        Task { @MainActor in
            logger.info("🚀 Starting signInWithToken...")
            print("🚀 Starting signInWithToken...")

            await authManager.signInWithToken(token, userID: uid)

            logger.info("✅ signInWithToken completed. isAuthenticated: \(authManager.isAuthenticated, privacy: .public)")
            print("✅ signInWithToken completed. isAuthenticated: \(authManager.isAuthenticated)")
            print("📊 Current user: \(authManager.currentUser?.email ?? "nil")")
        }
    }
}

#if DEBUG
private func runJWTTest() { }
#else
private func runJWTTest() { }
#endif

struct DeviceConflictSheet: View {
    let conflict: DeviceConflict
    let onTransfer: () -> Void
    let onCancel: () -> Void

    private var relativeLastSeen: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: conflict.lastSeenAt, relativeTo: Date())
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("License Active on Another Device")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your license is currently active on \(conflict.deviceName) (last seen \(relativeLastSeen)). Transfer to this Mac?")
                .multilineTextAlignment(.center)

            HStack {
                Button("Cancel") { onCancel() }
                Spacer()
                Button("Transfer") { onTransfer() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 460)
    }
}