import Foundation
import SwiftUI
import AppKit
import Combine
import Metal
import MetalKit
import CoreImage
import AVFoundation
import AVKit
import QuartzCore

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

    private var layerManager: LayerStackManager?

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

    func setLayerStackManager(_ manager: LayerStackManager) {
        self.layerManager = manager
        // If window already live, connect immediately
        if let window = externalWindow, let professionalView = window.contentView as? ProfessionalVideoView {
            professionalView.setLayerManager(manager, productionManager: productionManager)
        }
    }
    
    // MARK: - Private Properties (add these)
    private var lastUpdateTime: CFTimeInterval = 0
    private let updateThrottleInterval: CFTimeInterval = 1.0/120.0  // 120fps
    
    private func setupCameraFeedSubscriptions() {
        guard let productionManager = productionManager else { return }
        
        cancellables.removeAll()
        
        print("🖥️ External Display: Setting up subscriptions")
        
        // Subscribe to program source changes for immediate updates
        productionManager.previewProgramManager.$programSource
            .receive(on: DispatchQueue.main)
            .sink { [weak self] programSource in
                self?.handleProgramSourceChange(programSource)
            }
            .store(in: &cancellables)
        
        // Subscribe to output mapping changes for real-time transformation
        NotificationCenter.default.publisher(for: .outputMappingDidChange)
            .throttle(for: .milliseconds(8), scheduler: DispatchQueue.main, latest: true)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let mapping = notification.userInfo?["mapping"] as? OutputMapping {
                    self?.handleOutputMappingChange(mapping)
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleProgramSourceChange(_ programSource: ContentSource) {
        print("🔄 External Display: Program source changed to \(programSource)")
        
        // Update all external windows immediately
        if let window = externalWindow,
           let professionalView = window.contentView as? ProfessionalVideoView {
            professionalView.updateProgramSource(programSource)
        }
    }
    
    private func handleOutputMappingChange(_ mapping: OutputMapping) {
        let currentTime = CACurrentMediaTime()
        
        // Throttle updates for smooth performance
        if currentTime - lastUpdateTime < updateThrottleInterval {
            return
        }
        
        lastUpdateTime = currentTime
        
        // Immediately apply new mapping to external display
        if let window = externalWindow,
           let professionalView = window.contentView as? ProfessionalVideoView {
            professionalView.updateOutputMapping(mapping)
        }
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
        
        let metalDevice = outputMappingManager.metalDevice
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
        
        stopFullScreenOutput()
        
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
        
        let screens = NSScreen.screens
        let nonMainScreens: [NSScreen] = {
            if let main = NSScreen.main {
                return screens.filter { $0 !== main }
            } else {
                return screens
            }
        }()
        
        let targetScreen: NSScreen? = nonMainScreens.max(by: { s1, s2 in
            (s1.frame.width * s1.frame.height) < (s2.frame.width * s2.frame.height)
        }) ?? nonMainScreens.first ?? NSScreen.main
        
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
        
        window.title = "Vantaview LED Output"
        window.backgroundColor = .black
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = false
        window.isOpaque = true
        
        let videoView = ProfessionalVideoView(
            productionManager: productionManager,
            displayInfo: display,
            frame: windowRect
        )
        
        window.contentView = videoView
        if let layerManager {
            videoView.setLayerManager(layerManager, productionManager: productionManager)
        }

        window.setFrame(windowRect, display: true, animate: false)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        
        // Store references
        self.externalWindow = window
        self.selectedDisplay = display
        self.isFullScreenActive = true
        
        print("🚀 PROFESSIONAL Video View CREATED!")

        setupCameraFeedSubscriptions()
        if let professionalView = window.contentView as? ProfessionalVideoView {
            professionalView.updateProgramSource(productionManager.previewProgramManager.programSource)
            professionalView.updateOutputMapping(productionManager.outputMappingManager.currentMapping)
        }
    }
    
    func toggleFullScreen() {
        guard let window = externalWindow else { return }
        window.toggleFullScreen(nil)
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
        
        testWindow.title = "Vantaview Test Window"
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
        
        _ = productionManager.outputMappingManager.metalDevice
        
        return true
    }
}

// MARK: - ENHANCED PROFESSIONAL Video View

class ProfessionalVideoView: NSView {
    private var productionManager: UnifiedProductionManager
    private let displayInfo: ExternalDisplayManager.DisplayInfo
    private var cancellables = Set<AnyCancellable>()
    
    // REAL-TIME VIDEO LAYERS
    private var videoLayer: CALayer!
    private var overlayLayer: CALayer!
    private var transformLayer: CALayer!

    private var layersContainer: CALayer!

    private var pipLayers: [UUID: CALayer] = [:]
    private var pipSubscriptions: [UUID: AnyCancellable] = [:]
    private var pipVideoLayers: [UUID: AVPlayerLayer] = [:]
    private var pipVideoPlayers: [UUID: AVQueuePlayer] = [:]
    private var pipVideoLoopers: [UUID: AVPlayerLooper] = [:]

    private weak var layerManagerRef: LayerStackManager?
    private var editingField: NSTextField?
    private var editingLayerId: UUID?
    private var editingLayerRef: CALayer?

    // LIVE IMAGE PROCESSING
    private var currentOutputMapping: OutputMapping = OutputMapping()
    private var lastProcessedFrameCount: Int = 0
    
    private let metalDevice: MTLDevice
    private let commandQueue: MTLCommandQueue
    
    // Performance tracking
    private var frameCount = 0
    private var lastFPSTime = CACurrentMediaTime()
    private var fps: Double = 0
    
    private var frameTimer: Timer?
    
    private var metalLayer: CAMetalLayer?
    private var programRenderer: ExternalProgramMetalRenderer?
    
    init(productionManager: UnifiedProductionManager, displayInfo: ExternalDisplayManager.DisplayInfo, frame: CGRect) {
        self.productionManager = productionManager
        self.displayInfo = displayInfo
        self.metalDevice = productionManager.outputMappingManager.metalDevice
        self.commandQueue = self.metalDevice.makeCommandQueue()!
        super.init(frame: frame)
        
        setupAdvancedVideoLayers()
        setupRealtimeImageObservation()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }
    
    private func setupAdvancedVideoLayers() {
        wantsLayer = true
        
        layer = CALayer()
        layer?.backgroundColor = CGColor.black
        
        transformLayer = CALayer()
        transformLayer.frame = bounds
        transformLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        transformLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        layer?.addSublayer(transformLayer)
        
        let mLayer = CAMetalLayer()
        mLayer.device = metalDevice
        mLayer.pixelFormat = .bgra8Unorm
        mLayer.framebufferOnly = true
        mLayer.isOpaque = true
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        mLayer.contentsScale = scale
        mLayer.frame = bounds
        mLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        transformLayer.addSublayer(mLayer)
        metalLayer = mLayer
        
        videoLayer = CALayer()
        videoLayer.frame = bounds
        videoLayer.backgroundColor = CGColor.black
        videoLayer.contentsGravity = .resizeAspect
        videoLayer.isOpaque = true
        videoLayer.drawsAsynchronously = true
        transformLayer.addSublayer(videoLayer)

        layersContainer = CALayer()
        layersContainer.frame = bounds
        layersContainer.isOpaque = false
        transformLayer.addSublayer(layersContainer)
        
        overlayLayer = CALayer()
        overlayLayer.frame = bounds
        layer?.addSublayer(overlayLayer)
        
        print("🚀 Advanced video layers initialized")
    }
    

    private func setupRealtimeImageObservation() {
        // Observe program source changes
        productionManager.previewProgramManager.$programSource
            .receive(on: DispatchQueue.main)
            .sink { [weak self] programSource in
                self?.handleProgramSourceChange(programSource)
            }
            .store(in: &cancellables)
        
        // Start with current program source
        handleProgramSourceChange(productionManager.previewProgramManager.programSource)
    }
    
    func updateProgramSource(_ programSource: ContentSource) {
        handleProgramSourceChange(programSource)
    }
    
    func updateOutputMapping(_ mapping: OutputMapping) {
        currentOutputMapping = mapping
        applyTransformToVideoLayer()
        // Keep layersContainer frame in sync
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layersContainer.frame = bounds
        CATransaction.commit()
    }
    
    private func handleProgramSourceChange(_ programSource: ContentSource) {
        // Clear previous observers
        cancellables.removeAll()
        stopFrameTimer()
        
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
            stopProgramMetalRenderer()
            print("🚀 LIVE: Setting up camera feed for \(feed.device.displayName)")
            
            feed.$previewImage
                .compactMap { $0 }
                .throttle(for: .milliseconds(16), scheduler: DispatchQueue.main, latest: true)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] cgImage in
                    self?.displayLiveFrame(cgImage)
                }
                .store(in: &cancellables)
            
            feed.$frameCount
                .receive(on: DispatchQueue.main)
                .sink { [weak self] frameCount in
                    if frameCount > (self?.lastProcessedFrameCount ?? 0) {
                        self?.lastProcessedFrameCount = frameCount
                    }
                }
                .store(in: &cancellables)
                
        case .media(let mediaFile, _):
            if mediaFile.fileType == .image {
                stopProgramMetalRenderer()
                displayMediaPreview(mediaFile)
            } else {
                startProgramMetalRenderer()
            }
            
        case .virtual(let camera):
            stopProgramMetalRenderer()
            displayVirtualCameraPreview(camera)
            
        case .none:
            stopProgramMetalRenderer()
            displayPlaceholder(text: "No Program Source", color: .systemGray)
        }
    }
    
    private func displayLiveFrame(_ cgImage: CGImage) {
        var processedImage = cgImage
        
        if let effectChain = productionManager.previewProgramManager.getProgramEffectChain(),
           !effectChain.effects.isEmpty,
           effectChain.isEnabled {
            if let effectsProcessed = productionManager.previewProgramManager.processImageWithEffects(cgImage, for: .program) {
                processedImage = effectsProcessed
            }
        }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.contents = processedImage
        CATransaction.commit()
        
        updateFPS()
    }
    
    private func displayMediaPreview(_ mediaFile: MediaFile) {
        print("🎬 Displaying media preview: \(mediaFile.name)")
        if mediaFile.fileType == .image {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                if let image = NSImage(contentsOf: mediaFile.url),
                   let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    DispatchQueue.main.async {
                        self?.displayLiveFrame(cgImage)
                    }
                }
            }
        } else {
            startProgramMetalRenderer()
        }
    }
    
    private func displayVirtualCameraPreview(_ camera: VirtualCamera) {
        print("🎥 Displaying virtual camera: \(camera.name)")
        
        // TODO: Integrate with virtual camera renderer
        displayPlaceholder(text: "Virtual: \(camera.name)", color: .systemTeal)
    }
    
    private func applyTransformToVideoLayer() {
        let mapping = currentOutputMapping
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        let scaledW = mapping.size.width * mapping.scale
        let scaledH = mapping.size.height * mapping.scale
        let centerXNorm = mapping.position.x + scaledW / 2.0
        let centerYNorm = mapping.position.y + scaledH / 2.0
        let dx = (centerXNorm - 0.5) * bounds.width
        let dy = (centerYNorm - 0.5) * bounds.height
        
        transformLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        transformLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        
        var transform = CATransform3DIdentity
        transform = CATransform3DTranslate(transform, dx, dy, 0)
        if abs(mapping.rotation) > 0.01 {
            let radians = mapping.rotation * .pi / 180.0
            transform = CATransform3DRotate(transform, CGFloat(radians), 0, 0, 1)
        }
        transform = CATransform3DScale(transform, scaledW, scaledH, 1.0)
        
        transformLayer.transform = transform
        transformLayer.opacity = Float(mapping.opacity)
        
        CATransaction.commit()
    }
    
    // MARK: - Metal Helper Methods
    
    private func convertCGImageToMetalTexture(_ cgImage: CGImage) -> MTLTexture? {
        let device = productionManager.outputMappingManager.metalDevice
        let textureLoader = MTKTextureLoader(device: device)
        
        do {
            let options: [MTKTextureLoader.Option: Any] = [
                .textureUsage: MTLTextureUsage.shaderRead.rawValue,
                .textureStorageMode: MTLStorageMode.private.rawValue
            ]
            
            return try textureLoader.newTexture(cgImage: cgImage, options: options)
        } catch {
            print("❌ Failed to convert CGImage to Metal texture: \(error)")
            return nil
        }
    }
    
    private func convertMetalTextureToCGImage(_ texture: MTLTexture) -> CGImage? {
        let width = texture.width
        let height = texture.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow
        
        var readableTexture = texture
        
        if texture.storageMode == .private {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: texture.pixelFormat,
                width: width,
                height: height,
                mipmapped: false
            )
            desc.usage = [.shaderRead]
            desc.storageMode = .shared
            
            guard let stagingTexture = metalDevice.makeTexture(descriptor: desc),
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let blit = commandBuffer.makeBlitCommandEncoder() else {
                print("❌ Failed to create staging resources for readback")
                return nil
            }
            
            let origin = MTLOrigin(x: 0, y: 0, z: 0)
            let size = MTLSize(width: width, height: height, depth: 1)
            blit.copy(
                from: texture,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: origin,
                sourceSize: size,
                to: stagingTexture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: origin
            )
            blit.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            readableTexture = stagingTexture
        }
        
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: totalBytes, alignment: 64)
        defer { buffer.deallocate() }
        
        let region = MTLRegionMake2D(0, 0, width, height)
        readableTexture.getBytes(buffer, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        
        guard let context = CGContext(
            data: buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }
        
        return context.makeImage()
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

    private func startProgramFrameTimer() {
    }
    
    private func stopFrameTimer() {
        frameTimer?.invalidate()
        frameTimer = nil
    }
    
    private func startProgramMetalRenderer() {
        guard programRenderer == nil, let mLayer = metalLayer else { return }
        let provider: () -> MTLTexture? = { [weak self] in
            self?.productionManager.previewProgramManager.programCurrentTexture
        }
        if let renderer = ExternalProgramMetalRenderer(device: metalDevice, metalLayer: mLayer, textureProvider: provider) {
            programRenderer = renderer
            renderer.start()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            videoLayer.isHidden = true
            CATransaction.commit()
        }
    }
    
    private func stopProgramMetalRenderer() {
        programRenderer?.stop()
        programRenderer = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.isHidden = false
        CATransaction.commit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        transformLayer.frame = bounds
        transformLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        videoLayer.frame = bounds
        layersContainer.frame = bounds
        overlayLayer.frame = bounds
        
        if let mLayer = metalLayer {
            let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
            mLayer.frame = bounds
            mLayer.contentsScale = scale
            mLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        }
        
        CATransaction.commit()
    }

    func setLayerManager(_ manager: LayerStackManager?, productionManager: UnifiedProductionManager?) {
        // Clear old
        pipSubscriptions.values.forEach { $0.cancel() }
        pipSubscriptions.removeAll()
        pipLayers.values.forEach { $0.removeFromSuperlayer() }
        pipLayers.removeAll()
        for (_, layer) in pipVideoLayers { layer.removeFromSuperlayer() }
        pipVideoLayers.removeAll()
        pipVideoPlayers.values.forEach { $0.pause() }
        pipVideoPlayers.removeAll()
        pipVideoLoopers.removeAll()

        self.layerManagerRef = manager

        if let manager, let productionManager {
            self.cancellables.insert(
                manager.$layers
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in self?.refreshPipLayers(manager: manager, pm: productionManager) }
            )
            // Initial build
            refreshPipLayers(manager: manager, pm: productionManager)
        }
    }

    private func refreshPipLayers(manager: LayerStackManager, pm: UnifiedProductionManager) {
        // Remove missing
        let alive = Set(manager.layers.map { $0.id })
        for (id, layerObj) in pipLayers where !alive.contains(id) {
            layerObj.removeFromSuperlayer()
            pipLayers.removeValue(forKey: id)
            pipSubscriptions[id]?.cancel()
            pipSubscriptions.removeValue(forKey: id)
            if let av = pipVideoLayers[id] {
                av.removeFromSuperlayer()
                pipVideoLayers.removeValue(forKey: id)
            }
            if let p = pipVideoPlayers[id] {
                p.pause()
                pipVideoPlayers.removeValue(forKey: id)
            }
            pipVideoLoopers.removeValue(forKey: id)
        }

        // Sort by zIndex for ordering
        let sorted = manager.layers.sorted { $0.zIndex < $1.zIndex }

        // Ensure layers exist and are configured
        for model in sorted {
            // Create or get
            let lay: CALayer
            if let existing = pipLayers[model.id] {
                lay = existing
            } else {
                lay = CALayer()
                lay.isOpaque = false
                lay.masksToBounds = true
                lay.contentsGravity = .resizeAspect
                layersContainer.addSublayer(lay)
                pipLayers[model.id] = lay
            }

            // Visibility and ordering
            lay.isHidden = !model.isEnabled
            lay.opacity = model.opacity

            // Geometry
            let w = bounds.width * model.sizeNorm.width
            let h = bounds.height * model.sizeNorm.height
            lay.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            lay.position = CGPoint(x: bounds.width * model.centerNorm.x,
                                   y: bounds.height * model.centerNorm.y)

            // Rotation
            var t = CATransform3DIdentity
            if abs(model.rotationDegrees) > 0.01 {
                let r = CGFloat(model.rotationDegrees * .pi / 180)
                t = CATransform3DRotate(t, r, 0, 0, 1)
            }
            lay.transform = t

            // Bind source
            switch model.source {
            case .camera(let feedId):
                if pipSubscriptions[model.id] == nil {
                    if let feed = pm.cameraFeedManager.activeFeeds.first(where: { $0.id == feedId }) {
                        let sub = feed.$previewImage
                            .receive(on: DispatchQueue.main)
                            .sink { [weak lay] cg in
                                guard let lay else { return }
                                CATransaction.begin()
                                CATransaction.setDisableActions(true)
                                lay.contents = cg
                                CATransaction.commit()
                            }
                        pipSubscriptions[model.id] = sub
                    }
                }
            case .media(let file):
                switch file.fileType {
                case .image:
                    if let ns = NSImage(contentsOf: file.url),
                       let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        lay.contents = cg
                        CATransaction.commit()
                    }
                case .video:
                    // Ensure AVPlayerLayer
                    let avLayer: AVPlayerLayer
                    if let exist = pipVideoLayers[model.id] {
                        avLayer = exist
                    } else {
                        avLayer = AVPlayerLayer()
                        avLayer.videoGravity = .resizeAspect
                        lay.addSublayer(avLayer)
                        pipVideoLayers[model.id] = avLayer
                    }
                    avLayer.frame = lay.bounds

                    // Ensure Player + Looper
                    if pipVideoPlayers[model.id] == nil {
                        let asset = AVURLAsset(url: file.url)
                        let item = AVPlayerItem(asset: asset)
                        let player = AVQueuePlayer(items: [item])
                        let looper = AVPlayerLooper(player: player, templateItem: item)
                        player.isMuted = true
                        player.play()
                        avLayer.player = player
                        pipVideoPlayers[model.id] = player
                        pipVideoLoopers[model.id] = looper
                    } else {
                        avLayer.player = pipVideoPlayers[model.id]
                    }
                case .audio:
                    break
                }
            case .title(let overlay):
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                lay.contents = nil
                lay.sublayers?.forEach { $0.removeFromSuperlayer() }
                let textLayer = CATextLayer()
                textLayer.frame = lay.bounds
                textLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
                textLayer.isWrapped = true
                textLayer.truncationMode = .none
                textLayer.string = overlay.text
                textLayer.fontSize = overlay.fontSize
                textLayer.font = NSFont.systemFont(ofSize: overlay.fontSize, weight: .bold)
                let color = NSColor(srgbRed: overlay.color.r, green: overlay.color.g, blue: overlay.color.b, alpha: overlay.color.a)
                textLayer.foregroundColor = color.cgColor
                switch overlay.alignment {
                case .leading:
                    textLayer.alignmentMode = .left
                case .trailing:
                    textLayer.alignmentMode = .right
                default:
                    textLayer.alignmentMode = .center
                }
                lay.addSublayer(textLayer)
                CATransaction.commit()
            }

        }

        // Apply ordering (zPosition)
        for (i, model) in sorted.enumerated() {
            pipLayers[model.id]?.zPosition = CGFloat(i + 1)
        }

        // Apply ordering (zPosition)
        for (i, model) in sorted.enumerated() {
            pipLayers[model.id]?.zPosition = CGFloat(i + 1)
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard event.clickCount == 2 else { return }
        let pInWindow = event.locationInWindow
        let pInView = convert(pInWindow, from: nil)
        guard let root = self.layer else { return }
        let pInTransform = transformLayer.convert(pInView, from: root)
        guard let hit = layersContainer.hitTest(pInTransform) else { return }

        guard let (hitId, hitLay) = pipLayers.first(where: { (_, lay) in
            hit === lay || hit.isDescendant(of: lay)
        }) else { return }

        guard let mgr = layerManagerRef,
              let model = mgr.layers.first(where: { $0.id == hitId }),
              case .title(let overlay) = model.source else { return }

        beginEditingTitle(for: hitId, in: hitLay, currentText: overlay.text, fontSize: overlay.fontSize, alignment: overlay.alignment)
    }

    // Note: CALayer doesn't expose isDescendant(of:) directly; implement manually
    // We'll use this simple walk-up method via an extension.
}

private extension CALayer {
    func isDescendant(of ancestor: CALayer) -> Bool {
        var node: CALayer? = self
        while let n = node {
            if n === ancestor { return true }
            node = n.superlayer
        }
        return false
    }
}

extension ProfessionalVideoView: NSTextFieldDelegate {
    private func beginEditingTitle(for id: UUID, in layer: CALayer, currentText: String, fontSize: CGFloat, alignment: TextAlignment) {
        if let field = editingField {
            field.removeFromSuperview()
            editingField = nil
            editingLayerId = nil
            editingLayerRef = nil
        }
        guard let root = self.layer else { return }

        var rect = layer.frame
        rect = layersContainer.convert(rect, to: transformLayer)
        rect = transformLayer.convert(rect, to: root)

        let field = NSTextField(frame: rect.insetBy(dx: 4, dy: 4))
        field.stringValue = currentText
        field.font = .systemFont(ofSize: fontSize, weight: .bold)
        field.isEditable = true
        field.isBordered = true
        field.drawsBackground = true
        field.backgroundColor = NSColor.black.withAlphaComponent(0.35)
        field.textColor = .white
        field.focusRingType = .none
        field.isBezeled = true
        field.usesSingleLineMode = false
        field.lineBreakMode = .byWordWrapping
        field.delegate = self

        switch alignment {
        case .leading: field.alignment = .left
        case .trailing: field.alignment = .right
        default: field.alignment = .center
        }

        addSubview(field)
        window?.makeFirstResponder(field)
        editingField = field
        editingLayerId = id
        editingLayerRef = layer

        layer.isHidden = true

        relayoutEditingField()
    }

    // LIVE update while typing
    func controlTextDidChange(_ obj: Notification) {
        guard let field = editingField, let id = editingLayerId else { return }
        if let mgr = layerManagerRef, let idx = mgr.layers.firstIndex(where: { $0.id == id }) {
            var model = mgr.layers[idx]
            if case .title(var ov) = model.source {
                ov.text = field.stringValue
                model.source = .title(ov)

                if ov.autoFit {
                    let padW: CGFloat = 20
                    let padH: CGFloat = 20
                    field.sizeToFit()
                    let pref = field.fittingSize
                    let baseBounds = editingLayerRef?.bounds ?? .zero
                    let desiredW = min(self.bounds.width - 20, max(pref.width + padW, baseBounds.width))
                    let desiredH = min(self.bounds.height - 20, max(pref.height + padH, baseBounds.height))
                    let wNorm = min(1.0, max(24, desiredW) / self.bounds.width)
                    let hNorm = min(1.0, max(20, desiredH) / self.bounds.height)
                    model.sizeNorm = CGSize(width: wNorm, height: hNorm)
                }

                mgr.update(model)
            }
        }
        relayoutEditingField()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        endEditingUI()
    }

    override func keyDown(with event: NSEvent) {
        if editingField != nil {
            if event.keyCode == 53 {
                endEditingUI()
                return
            }
        }
        super.keyDown(with: event)
    }

    private func relayoutEditingField() {
        guard let field = editingField, let layer = editingLayerRef, let root = self.layer else { return }

        let maxW = bounds.width - 20
        let maxH = bounds.height - 20

        let fitting = field.intrinsicContentSize
        let prefW = min(maxW, max(fitting.width + 20, layer.bounds.width))
        let prefH = min(maxH, max(fitting.height + 20, layer.bounds.height))

        var rect = layer.frame
        rect = layersContainer.convert(rect, to: transformLayer)
        rect = transformLayer.convert(rect, to: root)
        let center = CGPoint(x: rect.midX, y: rect.midY)

        field.setFrameSize(NSSize(width: prefW, height: prefH))
        field.setFrameOrigin(NSPoint(x: center.x - prefW / 2, y: center.y - prefH / 2))
        field.needsLayout = true
    }

    private func endEditingUI() {
        if let field = editingField {
            field.removeFromSuperview()
        }
        editingLayerRef?.isHidden = false
        editingField = nil
        editingLayerId = nil
        editingLayerRef = nil
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