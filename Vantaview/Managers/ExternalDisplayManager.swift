import Foundation
import SwiftUI
import AppKit
import Combine
import Metal
import MetalKit
import CoreImage

@MainActor
class ExternalDisplayManager: ObservableObject {
    @Published var availableDisplays: [DisplayInfo] = []
    @Published var selectedDisplay: DisplayInfo?
    @Published var isFullScreenActive: Bool = false
    @Published var externalWindow: NSWindow?
    @Published var lastScanTime: Date = Date()
    @Published var displayConnectionStatus: String = "Scanning..."
    
    private var productionManager: UnifiedProductionManager?
    private var cancellables = Set<AnyCancellable>()
    private var displayChangeTimer: Timer?
    
    struct DisplayInfo: Identifiable, Equatable {
        let id: CGDirectDisplayID
        let name: String
        let bounds: CGRect
        let isMain: Bool
        let resolution: CGSize
        let refreshRate: Double
        let colorSpace: String
        let isActive: Bool
        
        var displayDescription: String {
            let width = Int(resolution.width)
            let height = Int(resolution.height)
            let rate = Int(refreshRate)
            return "\(width)×\(height) @ \(rate)Hz"
        }
        
        var statusColor: Color {
            return isActive ? .green : .orange
        }
        
        static func == (lhs: DisplayInfo, rhs: DisplayInfo) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    init() {
        scanForDisplays()
        setupDisplayChangeNotification()
        startPeriodicScan()
    }
    
    func setProductionManager(_ manager: UnifiedProductionManager) {
        self.productionManager = manager
        print("🖥️ External Display Manager: Production manager set")
    }
    
    private func setupCameraFeedSubscriptions() {
        guard let productionManager = productionManager else { return }
        
        cancellables.removeAll()
        
        if isFullScreenActive {
            print("🖥️ External Display: Setting up camera feed subscriptions")
            
            productionManager.cameraFeedManager.$selectedFeedForLiveProduction
                .sink { [weak self] selectedFeed in
                    Task { @MainActor in
                        self?.handleSelectedFeedChange(selectedFeed)
                    }
                }
                .store(in: &cancellables)
        }
    }
    
    private func handleSelectedFeedChange(_ selectedFeed: CameraFeed?) {
        print("🔄 External Display: Selected feed changed to \(selectedFeed?.device.displayName ?? "none")")
    }
    
    // MARK: - Display Scanning
    
    private func scanForDisplays() {
        var displayCount: UInt32 = 0
        var result = CGGetActiveDisplayList(0, nil, &displayCount)
        guard result == CGError.success else { 
            displayConnectionStatus = "Error scanning displays"
            return
        }
        
        let displays = UnsafeMutablePointer<CGDirectDisplayID>.allocate(capacity: Int(displayCount))
        defer { displays.deallocate() }
        
        result = CGGetActiveDisplayList(displayCount, displays, &displayCount)
        guard result == CGError.success else { 
            displayConnectionStatus = "Error reading display list"
            return
        }
        
        let newDisplays = (0..<displayCount).compactMap { index in
            let displayID = displays[Int(index)]
            return createDisplayInfo(for: displayID)
        }
        
        let previousCount = availableDisplays.count
        availableDisplays = newDisplays
        lastScanTime = Date()
        
        let externalCount = availableDisplays.filter { !$0.isMain }.count
        if externalCount == 0 {
            displayConnectionStatus = "No external displays detected"
        } else if externalCount == 1 {
            displayConnectionStatus = "1 external display found"
        } else {
            displayConnectionStatus = "\(externalCount) external displays found"
        }
        
        if previousCount != newDisplays.count {
            print("🖥️ Display configuration changed: \(previousCount) → \(newDisplays.count) displays")
        }
    }
    
    private func createDisplayInfo(for displayID: CGDirectDisplayID) -> DisplayInfo? {
        let bounds = CGDisplayBounds(displayID)
        let isMain = CGDisplayIsMain(displayID) != 0
        let isActive = CGDisplayIsActive(displayID) != 0
        
        let resolution = CGSize(width: bounds.width, height: bounds.height)
        let refreshRate = getDisplayRefreshRate(displayID)
        let colorSpace = getDisplayColorSpace(displayID)
        let name = generateDisplayName(for: displayID, isMain: isMain)
        
        return DisplayInfo(
            id: displayID,
            name: name,
            bounds: bounds,
            isMain: isMain,
            resolution: resolution,
            refreshRate: refreshRate,
            colorSpace: colorSpace,
            isActive: isActive
        )
    }
    
    private func getDisplayRefreshRate(_ displayID: CGDirectDisplayID) -> Double {
        let mode = CGDisplayCopyDisplayMode(displayID)
        return mode?.refreshRate ?? 60.0
    }
    
    private func getDisplayColorSpace(_ displayID: CGDirectDisplayID) -> String {
        let bounds = CGDisplayBounds(displayID)
        if bounds.width >= 3840 {
            return "P3"
        } else if bounds.width >= 2560 {
            return "sRGB/P3"
        } else {
            return "sRGB"
        }
    }
    
    private func generateDisplayName(for displayID: CGDirectDisplayID, isMain: Bool) -> String {
        if isMain {
            return "Main Display"
        } else {
            return "External Display \(displayID)"
        }
    }
    
    private func startPeriodicScan() {
        displayChangeTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanForDisplays()
            }
        }
    }
    
    private func setupDisplayChangeNotification() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    self?.scanForDisplays()
                    print("🖥️ Display configuration change detected")
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - External Display Output
    
    func startFullScreenOutput(on display: DisplayInfo) {
        print("🖥️ [DEBUG] startFullScreenOutput called for: \(display.name)")
        
        // ESSENTIAL VALIDATION - only check what's truly necessary
        guard let productionManager = productionManager else { 
            print("❌ [DEBUG] No production manager available")
            showErrorAlert("External Display Error", "The production system is not ready yet. Please wait a moment and try again.")
            return 
        }
        
        // Validate production manager components
        guard let previewProgramManager = productionManager.previewProgramManager as PreviewProgramManager? else {
            print("❌ [DEBUG] PreviewProgramManager is not available")
            showErrorAlert("System Not Ready", "The preview/program system is not initialized. Please restart the application.")
            return
        }
        
        guard let outputMappingManager = productionManager.outputMappingManager as OutputMappingManager? else {
            print("❌ [DEBUG] OutputMappingManager is not available")
            showErrorAlert("Graphics System Error", "The output mapping system is not available. Please restart the application.")
            return
        }
        
        guard let metalDevice = outputMappingManager.metalDevice as MTLDevice? else {
            print("❌ [DEBUG] Metal device is not available")
            showErrorAlert("Graphics Device Error", "Metal graphics device is not available. External display requires hardware acceleration.")
            return
        }
        
        print("✅ [DEBUG] All components validated successfully")
        print("✅ [DEBUG] Metal device: \(metalDevice.name)")
        
        guard availableDisplays.contains(where: { $0.id == display.id }) else {
            print("❌ [DEBUG] Display \(display.name) is no longer available")
            
            // Refresh displays and show error
            scanForDisplays()
            showErrorAlert("Display Not Available", "The selected display '\(display.name)' is no longer available. Please select a different display.")
            return
        }
        
        print("🖥️ [DEBUG] Starting external output on \(display.name)...")
        print("🖥️ [DEBUG] Display ID: \(display.id)")
        print("🖥️ [DEBUG] Display bounds: \(display.bounds)")
        print("🖥️ [DEBUG] Is main display: \(display.isMain)")
        
        // Close existing window if any (with error handling)
        do {
            stopFullScreenOutput()
        } catch {
            print("⚠️ [DEBUG] Error stopping previous output: \(error)")
        }
        
        // Set up camera feed subscriptions
        setupCameraFeedSubscriptions()
        
        // Create external window with comprehensive error handling
        do {
            try createExternalWindowSafe(for: display, productionManager: productionManager)
        } catch {
            print("❌ [DEBUG] Failed to create external window: \(error)")
            showErrorAlert("External Window Creation Failed", "Failed to create external display window: \(error.localizedDescription)")
        }
    }
    
    private func createExternalWindowSafe(for display: DisplayInfo, productionManager: UnifiedProductionManager) throws {
        print("🚀 [LED WALL] Creating INSTANT external window")
        
        // Find target screen efficiently
        var targetScreen: NSScreen?
        let nonMainScreens = NSScreen.screens.filter { $0 != NSScreen.main }
        
        if let largest = nonMainScreens.max(by: { s1, s2 in
            (s1.frame.width * s1.frame.height) < (s2.frame.width * s2.frame.height)
        }) {
            targetScreen = largest
        } else if let firstExternal = nonMainScreens.first {
            targetScreen = firstExternal
        } else {
            targetScreen = NSScreen.main
        }
        
        guard let screen = targetScreen else {
            throw ExternalDisplayError.noMatchingScreen(displayName: display.name)
        }
        
        let screenFrame = screen.frame
        let windowRect = CGRect(
            x: screenFrame.origin.x,
            y: screenFrame.origin.y,
            width: screenFrame.width,
            height: screenFrame.height
        )
        
        // Create window with optimized settings
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        
        window.title = "Vistaview LED Output"
        window.backgroundColor = .black
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = false
        window.isOpaque = true
        
        // CORRECT: Use AVFoundation-based view like Final Cut Pro
        let videoView = ProfessionalVideoView(
            productionManager: productionManager,
            displayInfo: display,
            frame: windowRect
        )
        
        window.contentView = videoView
        window.setFrame(windowRect, display: true, animate: false)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        
        // Store references
        self.externalWindow = window
        self.selectedDisplay = display
        self.isFullScreenActive = true
        
        print("🚀 PROFESSIONAL Video View CREATED!")
    }
    
    func toggleFullScreen() {
        guard let window = externalWindow else { return }
        
        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
            print("🖥️ Exited full-screen mode")
        } else {
            window.toggleFullScreen(nil)
            print("🖥️ Entered full-screen mode")
        }
    }
    
    func stopFullScreenOutput() {
        if let window = externalWindow {
            window.delegate = nil
            window.close()
        }
        
        cancellables.removeAll()
        
        externalWindow = nil
        selectedDisplay = nil
        isFullScreenActive = false
        
        print("🖥️ Stopped external output")
    }
    
    // MARK: - Utility Functions
    
    func refreshDisplays() {
        scanForDisplays()
        print("🔄 Manual display refresh completed")
    }
    
    func getExternalDisplays() -> [DisplayInfo] {
        return availableDisplays.filter { !$0.isMain && $0.isActive }
    }
    
    func validateSelectedDisplay() -> Bool {
        guard let selected = selectedDisplay else { return false }
        return availableDisplays.contains(where: { $0.id == selected.id && $0.isActive })
    }
    
    deinit {
        displayChangeTimer?.invalidate()
        cancellables.removeAll()
    }
    
    // MARK: - Debug Functions
    
    func testExternalWindow() {
        print("🧪 Testing external window creation...")
        
        guard let firstExternal = getExternalDisplays().first else {
            print("❌ No external displays found for testing")
            return
        }
        
        print("🧪 Creating test window on: \(firstExternal.name)")
        
        // Create a simple test window
        let testWindow = NSWindow(
            contentRect: CGRect(x: 100, y: 100, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        testWindow.title = "Vistaview Test Window"
        testWindow.backgroundColor = .red
        testWindow.makeKeyAndOrderFront(nil)
        
        print("🧪 Test window created and shown")
        
        // Auto-close after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            testWindow.close()
            print("🧪 Test window closed")
        }
    }
    
    // Helper method to show user-friendly error alerts
    private func showErrorAlert(_ title: String, _ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            
            // Show alert on main window if available
            if let mainWindow = NSApplication.shared.mainWindow {
                alert.beginSheetModal(for: mainWindow) { _ in }
            } else {
                alert.runModal()
            }
        }
    }
    
    // Add computed property to check initialization status
    var isProperlyInitialized: Bool {
        guard let productionManager = productionManager else {
            print("❌ ExternalDisplayManager: No production manager")
            return false
        }
        
        guard productionManager.previewProgramManager != nil else {
            print("❌ ExternalDisplayManager: No preview program manager")
            return false
        }
        
        guard productionManager.outputMappingManager.metalDevice != nil else {
            print("❌ ExternalDisplayManager: No Metal device")
            return false
        }
        
        return true
    }
}

// MARK: - PROFESSIONAL Video View (Final Cut Pro Style)

class ProfessionalVideoView: NSView {
    private var productionManager: UnifiedProductionManager
    private let displayInfo: ExternalDisplayManager.DisplayInfo
    private var cancellables = Set<AnyCancellable>()
    
    // Core video display layer
    private var videoLayer: CALayer!
    private var lastProcessedFrameCount: Int = 0
    
    // Performance tracking
    private var frameCount = 0
    private var lastFPSTime = CACurrentMediaTime()
    private var fps: Double = 0
    
    init(productionManager: UnifiedProductionManager, displayInfo: ExternalDisplayManager.DisplayInfo, frame: CGRect) {
        self.productionManager = productionManager
        self.displayInfo = displayInfo
        super.init(frame: frame)
        
        setupVideoLayer()
        setupCameraObservation()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }
    
    private func setupVideoLayer() {
        // Simple, efficient CALayer for video display
        videoLayer = CALayer()
        videoLayer.frame = bounds
        videoLayer.backgroundColor = CGColor.black
        videoLayer.contentsGravity = .resizeAspectFill
        
        // Optimize for video playback
        videoLayer.isOpaque = true
        videoLayer.drawsAsynchronously = true
        
        // Enable layer backing
        wantsLayer = true
        layer = videoLayer
        
        print("🚀 Professional video layer initialized")
    }
    
    private func setupCameraObservation() {
        // Direct observation of program source changes
        productionManager.previewProgramManager.$programSource
            .receive(on: DispatchQueue.main)
            .sink { [weak self] programSource in
                self?.handleProgramSourceChange(programSource)
            }
            .store(in: &cancellables)
        
        // Start initial observation
        handleProgramSourceChange(productionManager.previewProgramManager.programSource)
    }
    
    private func handleProgramSourceChange(_ programSource: ContentSource) {
        // Clear previous observers
        cancellables.removeAll()
        
        // Re-add program source observer
        productionManager.previewProgramManager.$programSource
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSource in
                if newSource != programSource {
                    self?.handleProgramSourceChange(newSource)
                }
            }
            .store(in: &cancellables)
        
        switch programSource {
        case .camera(let feed):
            print("🚀 Setting up camera observation for \(feed.device.displayName)")
            
            // Observe camera frames directly
            feed.$previewImage
                .compactMap { $0 }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] cgImage in
                    self?.displayFrame(cgImage)
                }
                .store(in: &cancellables)
                
        case .media(let mediaFile, _):
            displayPlaceholder(text: "Media: \(mediaFile.name)", color: .systemPurple)
            
        case .virtual(let camera):
            displayPlaceholder(text: "Virtual: \(camera.name)", color: .systemTeal)
            
        case .none:
            displayPlaceholder(text: "No Program Source", color: .systemGray)
        }
    }
    
    private func displayFrame(_ cgImage: CGImage) {
        // Apply effects if they exist
        var processedImage = cgImage
        
        if let effectChain = productionManager.previewProgramManager.getProgramEffectChain(),
           !effectChain.effects.isEmpty {
            if let effectsProcessed = productionManager.previewProgramManager.processImageWithEffects(cgImage, for: .program) {
                processedImage = effectsProcessed
            }
        }
        
        // EFFICIENT: Direct layer contents update (no Metal overhead)
        CATransaction.begin()
        CATransaction.setDisableActions(true)  // No animations for performance
        videoLayer.contents = processedImage
        CATransaction.commit()
        
        updateFPS()
    }
    
    private func displayPlaceholder(text: String, color: NSColor) {
        // Create simple placeholder image
        let size = CGSize(width: 1920, height: 1080)
        
        let image = NSImage(size: size)
        image.lockFocus()
        
        // Fill background
        color.withAlphaComponent(0.3).setFill()
        NSRect(origin: .zero, size: size).fill()
        
        // Draw text
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 72, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        let textRect = NSRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        attributedString.draw(in: textRect)
        image.unlockFocus()
        
        // Convert to CGImage and display
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            videoLayer.contents = cgImage
            CATransaction.commit()
        }
    }
    
    private func updateFPS() {
        frameCount += 1
        let currentTime = CACurrentMediaTime()
        let timeDiff = currentTime - lastFPSTime
        
        if timeDiff >= 1.0 {
            fps = Double(frameCount) / timeDiff
            frameCount = 0
            lastFPSTime = currentTime
            
            if Int(currentTime) % 5 == 0 {
                print("🚀 External Display: \(Int(fps)) FPS")
            }
        }
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
    }
    
    deinit {
        cancellables.removeAll()
        print("🚀 Professional video view deinitialized")
    }
}

// MARK: - Error Types

enum ExternalDisplayError: LocalizedError {
    case metalDeviceUnavailable
    case previewProgramManagerUnavailable
    case noMatchingScreen(displayName: String)
    case windowCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .metalDeviceUnavailable:
            return "Metal graphics device is not available"
        case .previewProgramManagerUnavailable:
            return "Preview/Program manager is not available"
        case .noMatchingScreen(let displayName):
            return "Could not find matching screen for display '\(displayName)'"
        case .windowCreationFailed:
            return "Failed to create external display window"
        }
    }
}