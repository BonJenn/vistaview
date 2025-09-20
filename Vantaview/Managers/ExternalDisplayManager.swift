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
    
    private weak var productionManager: UnifiedProductionManager?
    private var cancellables = Set<AnyCancellable>()
    private var displayChangeTimer: Timer?
    private weak var layerManager: LayerStackManager?

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
    
    // MEMORY OPTIMIZATION: Throttling and cleanup
    private var lastUpdateTime: CFTimeInterval = 0
    private let updateThrottleInterval: CFTimeInterval = 1.0/30.0
    private var textureCache: [String: (texture: MTLTexture, timestamp: CFTimeInterval)] = [:]
    private let maxTextureCacheSize = 5
    
    init() {
        scanForDisplays()
        setupDisplayChangeNotification()
        startPeriodicScan()
    }
    
    deinit {
        displayChangeTimer?.invalidate()
        displayChangeTimer = nil
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        textureCache.removeAll()
        print("🧹 External Display Manager: Deinit cleanup completed")
    }
    
    func cleanup() {
        print("🧹 External Display Manager: Starting comprehensive cleanup")
        displayChangeTimer?.invalidate()
        displayChangeTimer = nil
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        if let window = externalWindow {
            if let professionalView = window.contentView as? OptimizedProfessionalVideoView {
                professionalView.cleanup()
            }
            window.delegate = nil
            window.close()
        }
        textureCache.removeAll()
        externalWindow = nil
        selectedDisplay = nil
        isFullScreenActive = false
        print("🧹 External Display Manager: Cleanup completed")
    }
    
    func setProductionManager(_ manager: UnifiedProductionManager) {
        self.productionManager = manager
        print("🖥️ External Display Manager: Production manager set")
    }
    
    // RESTORED API: Keep original method name for compatibility
    func setLayerStackManager(_ manager: LayerStackManager) {
        setLayerManager(manager)
    }

    // Internal implementation used by restored API
    func setLayerManager(_ manager: LayerStackManager) {
        self.layerManager = manager
        if let window = externalWindow, let professionalView = window.contentView as? OptimizedProfessionalVideoView {
            professionalView.setLayerManager(manager, productionManager: productionManager)
        }
    }
    
    private func setupCameraFeedSubscriptions() {
        guard let productionManager = productionManager else { return }
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        print("🖥️ External Display: Setting up subscriptions")
        
        productionManager.previewProgramManager.$programSource
            .throttle(for: .milliseconds(33), scheduler: DispatchQueue.main, latest: true)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] programSource in
                autoreleasepool {
                    self?.handleProgramSourceChange(programSource)
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .outputMappingDidChange)
            .throttle(for: .milliseconds(33), scheduler: DispatchQueue.main, latest: true)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                autoreleasepool {
                    if let mapping = notification.userInfo?["mapping"] as? OutputMapping {
                        self?.handleOutputMappingChange(mapping)
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleProgramSourceChange(_ programSource: ContentSource) {
        print("🔄 External Display: Program source changed to \(programSource)")
        if let window = externalWindow,
           let professionalView = window.contentView as? OptimizedProfessionalVideoView {
            professionalView.updateProgramSource(programSource)
        }
    }
    
    private func handleOutputMappingChange(_ mapping: OutputMapping) {
        let currentTime = CACurrentMediaTime()
        if currentTime - lastUpdateTime < updateThrottleInterval {
            return
        }
        lastUpdateTime = currentTime
        if let window = externalWindow,
           let professionalView = window.contentView as? OptimizedProfessionalVideoView {
            professionalView.updateOutputMapping(mapping)
        }
    }

    // MARK: - Display Scanning
    
    private func scanForDisplays() {
        autoreleasepool {
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
        displayChangeTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                autoreleasepool {
                    self?.scanForDisplays()
                }
            }
        }
    }
    
    private func setupDisplayChangeNotification() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    autoreleasepool {
                        self?.scanForDisplays()
                    }
                    print("🖥️ Display configuration change detected")
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - External Display Output
    
    func startFullScreenOutput(on display: DisplayInfo) {
        print("🖥️ [DEBUG] startFullScreenOutput called for: \(display.name)")
        
        guard let productionManager = productionManager else {
            print("❌ [DEBUG] No production manager available")
            showErrorAlert("External Display Error", "The production system is not ready yet. Please wait a moment and try again.")
            return
        }
        
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
            scanForDisplays()
            showErrorAlert("Display Not Available", "The selected display '\(display.name)' is no longer available. Please select a different display.")
            return
        }
        
        print("🖥️ [DEBUG] Starting external output on \(display.name)...")
        print("🖥️ [DEBUG] Display ID: \(display.id)")
        print("🖥️ [DEBUG] Display bounds: \(display.bounds)")
        print("🖥️ [DEBUG] Is main display: \(display.isMain)")
        
        stopFullScreenOutput()
        setupCameraFeedSubscriptions()
        
        do {
            try createExternalWindowSafe(for: display, productionManager: productionManager)
        } catch {
            print("❌ [DEBUG] Failed to create external window: \(error)")
            showErrorAlert("External Window Creation Failed", "Failed to create external display window: \(error.localizedDescription)")
        }
    }
    
    private func createExternalWindowSafe(for display: DisplayInfo, productionManager: UnifiedProductionManager) throws {
        print("🚀 [LED WALL] Creating OPTIMIZED external window")
        
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
        
        let videoView = OptimizedProfessionalVideoView(
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
        
        self.externalWindow = window
        self.selectedDisplay = display
        self.isFullScreenActive = true
        
        print("🚀 OPTIMIZED Professional Video View CREATED!")

        setupCameraFeedSubscriptions()
        if let professionalView = window.contentView as? OptimizedProfessionalVideoView {
            professionalView.updateProgramSource(productionManager.previewProgramManager.programSource)
            professionalView.updateOutputMapping(productionManager.outputMappingManager.currentMapping)
        }
    }
    
    func toggleFullScreen() {
        guard let window = externalWindow else { return }
        window.toggleFullScreen(nil)
    }
    
    func stopFullScreenOutput() {
        cleanup()
        print("🖥️ Stopped external output")
    }
    
    // MARK: - Texture Cache Management
    
    private func getCachedTexture(for key: String) -> MTLTexture? {
        let currentTime = CACurrentMediaTime()
        if let cached = textureCache[key], currentTime - cached.timestamp < 0.1 {
            return cached.texture
        }
        return nil
    }
    
    private func cacheTexture(_ texture: MTLTexture, for key: String) {
        let currentTime = CACurrentMediaTime()
        textureCache[key] = (texture: texture, timestamp: currentTime)
        if textureCache.count > maxTextureCacheSize {
            let sortedByTime = textureCache.sorted { $0.value.timestamp < $1.value.timestamp }
            let oldestKey = sortedByTime.first?.key
            if let oldestKey = oldestKey {
                textureCache.removeValue(forKey: oldestKey)
            }
        }
    }
    
    // MARK: - Utility Functions
    
    func refreshDisplays() {
        autoreleasepool {
            scanForDisplays()
        }
        print("🔄 Manual display refresh completed")
    }
    
    func getExternalDisplays() -> [DisplayInfo] {
        return availableDisplays.filter { !$0.isMain && $0.isActive }
    }
    
    func validateSelectedDisplay() -> Bool {
        guard let selected = selectedDisplay else { return false }
        return availableDisplays.contains(where: { $0.id == selected.id && $0.isActive })
    }
    
    // MARK: - Debug Functions
    
    func testExternalWindow() {
        print("🧪 Testing external window creation...")
        
        guard let firstExternal = getExternalDisplays().first else {
            print("❌ No external displays found for testing")
            return
        }
        
        print("🧪 Creating test window on: \(firstExternal.name)")
        
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
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            testWindow.close()
            print("🧪 Test window closed")
        }
    }
    
    private func showErrorAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        
        if let mainWindow = NSApplication.shared.mainWindow {
            alert.beginSheetModal(for: mainWindow) { _ in }
        } else {
            alert.runModal()
        }
    }
    
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

// MARK: - MEMORY-OPTIMIZED PROFESSIONAL Video View

class OptimizedProfessionalVideoView: NSView {
    private weak var productionManager: UnifiedProductionManager?
    private let displayInfo: ExternalDisplayManager.DisplayInfo
    private var cancellables = Set<AnyCancellable>()
    
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
    private weak var editingLayerRef: CALayer?

    private var currentOutputMapping: OutputMapping = OutputMapping()
    private var lastProcessedFrameCount: Int = 0
    
    private let metalDevice: MTLDevice
    private let commandQueue: MTLCommandQueue
    
    private var frameCount = 0
    private var lastFPSTime = CACurrentMediaTime()
    private var fps: Double = 0
    private var lastFrameTime = CACurrentMediaTime()
    private let targetFrameInterval: CFTimeInterval = 1.0/30.0
    
    private var frameTimer: Timer?
    private var metalLayer: CAMetalLayer?
    private var programRenderer: ExternalProgramMetalRenderer?
    
    private var ckPipelineState: MTLComputePipelineState?
    private var ckFallbackBGTexture: MTLTexture?
    
    init(productionManager: UnifiedProductionManager, displayInfo: ExternalDisplayManager.DisplayInfo, frame: CGRect) {
        self.productionManager = productionManager
        self.displayInfo = displayInfo
        self.metalDevice = productionManager.outputMappingManager.metalDevice
        self.commandQueue = self.metalDevice.makeCommandQueue()!
        super.init(frame: frame)
        
        setupAdvancedVideoLayers()
        setupOptimizedImageObservation()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }
    
    deinit {
        cleanup()
    }
    
    func cleanup() {
        print("🧹 OptimizedProfessionalVideoView: Starting cleanup")
        frameTimer?.invalidate()
        frameTimer = nil
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        pipSubscriptions.values.forEach { $0.cancel() }
        pipSubscriptions.removeAll()
        pipVideoPlayers.values.forEach { player in
            player.pause()
            player.removeAllItems()
        }
        pipVideoPlayers.removeAll()
        pipVideoLoopers.removeAll()
        pipVideoLayers.values.forEach { layer in
            layer.player = nil
            layer.removeFromSuperlayer()
        }
        pipVideoLayers.removeAll()
        pipLayers.values.forEach { $0.removeFromSuperlayer() }
        pipLayers.removeAll()
        programRenderer?.stop()
        programRenderer = nil
        if let field = editingField {
            field.removeFromSuperview()
            editingField = nil
        }
        editingLayerId = nil
        editingLayerRef = nil
        productionManager = nil
        layerManagerRef = nil
        print("🧹 OptimizedProfessionalVideoView: Cleanup completed")
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
        
        print("🚀 Advanced video layers initialized with optimizations")
    }
    
    private func setupOptimizedImageObservation() {
        guard let productionManager = productionManager else { return }
        productionManager.previewProgramManager.$programSource
            .throttle(for: .milliseconds(33), scheduler: DispatchQueue.main, latest: true)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] programSource in
                autoreleasepool {
                    self?.handleProgramSourceChange(programSource)
                }
            }
            .store(in: &cancellables)
        handleProgramSourceChange(productionManager.previewProgramManager.programSource)
    }
    
    func updateProgramSource(_ programSource: ContentSource) {
        autoreleasepool {
            handleProgramSourceChange(programSource)
        }
    }
    
    func updateOutputMapping(_ mapping: OutputMapping) {
        currentOutputMapping = mapping
        applyTransformToVideoLayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layersContainer.frame = bounds
        CATransaction.commit()
    }
    
    private func handleProgramSourceChange(_ programSource: ContentSource) {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        stopFrameTimer()
        
        guard let productionManager = productionManager else { return }
        
        productionManager.previewProgramManager.$programSource
            .throttle(for: .milliseconds(33), scheduler: DispatchQueue.main, latest: true)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSource in
                if newSource != programSource {
                    autoreleasepool {
                        self?.handleProgramSourceChange(newSource)
                    }
                }
            }
            .store(in: &cancellables)
        
        switch programSource {
        case .camera(let feed):
            stopProgramMetalRenderer()
            print("🚀 LIVE: Setting up camera feed for \(feed.device.displayName)")
            feed.$previewImage
                .compactMap { $0 }
                .throttle(for: .milliseconds(33), scheduler: DispatchQueue.main, latest: true)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] cgImage in
                    autoreleasepool {
                        self?.displayLiveFrameThrottled(cgImage)
                    }
                }
                .store(in: &cancellables)
            feed.$frameCount
                .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
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
    
    private func displayLiveFrameThrottled(_ cgImage: CGImage) {
        let currentTime = CACurrentMediaTime()
        if currentTime - lastFrameTime < targetFrameInterval {
            return
        }
        lastFrameTime = currentTime
        
        autoreleasepool {
            var processedImage = cgImage
            if let effectChain = productionManager?.previewProgramManager.getProgramEffectChain(),
               !effectChain.effects.isEmpty,
               effectChain.isEnabled {
                if let effectsProcessed = productionManager?.previewProgramManager.processImageWithEffects(cgImage, for: .program) {
                    processedImage = effectsProcessed
                }
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            videoLayer.contents = processedImage
            CATransaction.commit()
            updateFPS()
        }
    }
    
    private func displayMediaPreview(_ mediaFile: MediaFile) {
        print("🎬 Displaying media preview: \(mediaFile.name)")
        if mediaFile.fileType == .image {
            Task.detached { [weak self] in
                autoreleasepool {
                    guard let self else { return }
                    if let image = NSImage(contentsOf: mediaFile.url),
                       let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        Task { @MainActor in
                            autoreleasepool {
                                self.displayLiveFrameThrottled(cgImage)
                            }
                        }
                    }
                }
            }
        } else {
            startProgramMetalRenderer()
        }
    }
    
    private func displayVirtualCameraPreview(_ camera: VirtualCamera) {
        print("🎥 Displaying virtual camera: \(camera.name)")
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
    
    private func displayPlaceholder(text: String, color: NSColor) {
        autoreleasepool {
            let size = CGSize(width: 1920, height: 1080)
            let image = NSImage(size: size)
            image.lockFocus()
            color.withAlphaComponent(0.3).setFill()
            NSRect(origin: .zero, size: size).fill()
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
            if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                videoLayer.contents = cgImage
                CATransaction.commit()
            }
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
            if Int(currentTime) % 10 == 0 {
                print("🚀 External Display: \(Int(fps)) FPS (Optimized)")
            }
        }
    }
    
    private func stopFrameTimer() {
        frameTimer?.invalidate()
        frameTimer = nil
    }
    
    private func startProgramMetalRenderer() {
        guard programRenderer == nil, let mLayer = metalLayer else { return }
        let provider: () -> MTLTexture? = { [weak self] in
            self?.productionManager?.previewProgramManager.programCurrentTexture
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
        pipSubscriptions.values.forEach { $0.cancel() }
        pipSubscriptions.removeAll()
        
        pipLayers.values.forEach { $0.removeFromSuperlayer() }
        pipLayers.removeAll()
        
        for (_, layer) in pipVideoLayers {
            layer.player = nil
            layer.removeFromSuperlayer()
        }
        pipVideoLayers.removeAll()
        
        pipVideoPlayers.values.forEach { player in
            player.pause()
            player.removeAllItems()
        }
        pipVideoPlayers.removeAll()
        pipVideoLoopers.removeAll()

        self.layerManagerRef = manager

        if let manager, let productionManager {
            self.cancellables.insert(
                manager.$layers
                    .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in
                        autoreleasepool {
                            self?.refreshPipLayers(manager: manager, pm: productionManager)
                        }
                    }
            )
            refreshPipLayers(manager: manager, pm: productionManager)
        }
    }

    private func refreshPipLayers(manager: LayerStackManager, pm: UnifiedProductionManager) {
        print("🔄 Refreshing PiP layers")
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