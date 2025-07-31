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
        guard let productionManager = productionManager else { 
            print("❌ No production manager available")
            return 
        }
        
        guard availableDisplays.contains(where: { $0.id == display.id }) else {
            print("❌ Display \(display.name) is no longer available")
            return
        }
        
        print("🖥️ Starting external output on \(display.name)...")
        
        stopFullScreenOutput()
        setupCameraFeedSubscriptions()
        
        Task { @MainActor in
            await createExternalWindow(for: display, productionManager: productionManager)
        }
    }
    
    private func createExternalWindow(for display: DisplayInfo, productionManager: UnifiedProductionManager) async {
        guard let targetScreen = NSScreen.screens.first(where: { screen in
            let screenFrame = screen.frame
            return abs(screenFrame.origin.x - display.bounds.origin.x) < 1.0 &&
                   abs(screenFrame.origin.y - display.bounds.origin.y) < 1.0
        }) else {
            print("❌ Could not find NSScreen for display \(display.name)")
            return
        }
        
        print("🖥️ Found target screen: \(targetScreen.localizedName)")
        
        let windowSize = CGSize(width: 800, height: 600)
        let windowOrigin = CGPoint(
            x: targetScreen.frame.midX - windowSize.width / 2,
            y: targetScreen.frame.midY - windowSize.height / 2
        )
        
        let windowRect = CGRect(origin: windowOrigin, size: windowSize)
        
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false,
            screen: targetScreen
        )
        
        window.title = "Vistaview External Output - \(display.name)"
        window.backgroundColor = .black
        window.hasShadow = true
        window.level = .normal
        
        let contentView = ExternalDisplayContentView(
            productionManager: productionManager,
            displayInfo: display,
            displaySize: windowSize
        )
        
        let hostingView = NSHostingView(rootView: contentView)
        window.contentView = hostingView
        
        window.makeKeyAndOrderFront(nil)
        
        self.externalWindow = window
        self.selectedDisplay = display
        self.isFullScreenActive = true
        
        print("🖥️ Created external output window on \(display.name)")
        
        window.delegate = ExternalWindowDelegate(manager: self)
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
}

// MARK: - External Display Content View

struct ExternalDisplayContentView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    let displayInfo: ExternalDisplayManager.DisplayInfo
    let displaySize: CGSize
    @State private var frameUpdateTrigger = 0
    @State private var performanceStats = PerformanceStats()
    @State private var showControls = true
    
    struct PerformanceStats {
        var fps: Double = 0.0
        var lastFrameTime: Date = Date()
        var frameCount: Int = 0
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let selectedFeed = productionManager.cameraFeedManager.selectedFeedForLiveProduction,
               selectedFeed.connectionStatus == .connected,
               let image = selectedFeed.previewImage {
                
                Image(decorative: processImageForExternalDisplay(image), scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .id("external-display-\(selectedFeed.id)-\(frameUpdateTrigger)")
                    .onReceive(Timer.publish(every: 1.0/30.0, on: .main, in: .common).autoconnect()) { _ in
                        frameUpdateTrigger += 1
                        updatePerformanceStats()
                    }
                    .onTapGesture {
                        showControls.toggle()
                    }
                    
            } else {
                statusView
                    .onTapGesture {
                        showControls.toggle()
                    }
            }
            
            if showControls {
                controlOverlay
                    .opacity(0.9)
                    .animation(.easeInOut(duration: 0.3), value: showControls)
            }
        }
        .onReceive(Timer.publish(every: 5.0, on: .main, in: .common).autoconnect()) { _ in
            if showControls {
                showControls = false
            }
        }
        .onAppear {
            print("🖥️ External Display: Content view appeared for \(displayInfo.name)")
        }
        .onDisappear {
            print("🖥️ External Display: Content view disappeared")
        }
    }
    
    @ViewBuilder
    private var statusView: some View {
        VStack(spacing: 20) {
            Image(systemName: "tv")
                .font(.system(size: 100))
                .foregroundColor(.white.opacity(0.3))
            
            Text("Vistaview External Output")
                .font(.largeTitle)
                .foregroundColor(.white.opacity(0.7))
            
            VStack(spacing: 12) {
                VStack(alignment: .center, spacing: 4) {
                    Text("Connected to:")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                    Text(displayInfo.name)
                        .font(.title2)
                        .foregroundColor(.blue.opacity(0.8))
                    Text(displayInfo.displayDescription)
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.6))
                    Text("Color Space: \(displayInfo.colorSpace)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Divider()
                    .background(Color.white.opacity(0.3))
                
                VStack(alignment: .center, spacing: 4) {
                    Text("Camera Status")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                    
                    if let selectedFeed = productionManager.cameraFeedManager.selectedFeedForLiveProduction {
                        Text(selectedFeed.device.displayName)
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.6))
                        
                        Text("Status: \(selectedFeed.connectionStatus.displayText)")
                            .font(.title3)
                            .foregroundColor(selectedFeed.connectionStatus.color.opacity(0.8))
                        
                        if selectedFeed.connectionStatus == .connected {
                            Text("Frame Count: \(selectedFeed.frameCount)")
                                .font(.caption)
                                .foregroundColor(.green.opacity(0.7))
                        }
                    } else {
                        Text("No camera selected")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.5))
                        
                        Text("Select a camera in the main window")
                            .font(.callout)
                            .foregroundColor(.blue.opacity(0.7))
                    }
                }
            }
            
            Text("Tap to show/hide controls")
                .font(.caption)
                .foregroundColor(.gray.opacity(0.7))
        }
        .padding()
    }
    
    @ViewBuilder
    private var controlOverlay: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("External Output")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(displayInfo.name)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                if performanceStats.fps > 0 {
                    Text("\(performanceStats.fps, specifier: "%.1f") FPS")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.3))
                        .cornerRadius(4)
                }
                
                Button("×") {
                    showControls = false
                }
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(Color.red.opacity(0.3))
                .cornerRadius(15)
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.8), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            Spacer()
            
            if productionManager.outputMappingManager.isEnabled {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Image(systemName: "rectangle.resize")
                                .foregroundColor(.blue)
                            Text("Output Mapping Active")
                                .foregroundColor(.white)
                                .fontWeight(.semibold)
                        }
                        Text(productionManager.outputMappingManager.mappingDescription)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer()
                }
                .padding()
                .background(
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }
    
    private func updatePerformanceStats() {
        let now = Date()
        performanceStats.frameCount += 1
        
        let timeDiff = now.timeIntervalSince(performanceStats.lastFrameTime)
        if timeDiff >= 1.0 {
            performanceStats.fps = Double(performanceStats.frameCount) / timeDiff
            performanceStats.frameCount = 0
            performanceStats.lastFrameTime = now
        }
    }
    
    private func processImageForExternalDisplay(_ image: CGImage) -> CGImage {
        var processedImage = image
        
        let programSource = productionManager.previewProgramManager.programSource
        if case .camera(let feed) = programSource,
           feed.id == productionManager.cameraFeedManager.selectedFeedForLiveProduction?.id {
            if let chain = productionManager.previewProgramManager.getProgramEffectChain(),
               !chain.effects.isEmpty {
                if let effectsProcessedImage = processImageWithEffectsAsync(
                    image, 
                    using: productionManager.effectManager, 
                    sourceID: EffectManager.programSourceID
                ) {
                    processedImage = effectsProcessedImage
                }
            }
        }
        
        if productionManager.outputMappingManager.isEnabled {
            if let mappingProcessedImage = applyOutputMappingToImage(processedImage) {
                processedImage = mappingProcessedImage
            }
        }
        
        return processedImage
    }
    
    private func applyOutputMappingToImage(_ image: CGImage) -> CGImage? {
        let textureLoader = MTKTextureLoader(device: productionManager.outputMappingManager.metalDevice)
        
        do {
            let inputTexture = try textureLoader.newTexture(cgImage: image, options: [
                MTKTextureLoader.Option.textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                MTKTextureLoader.Option.textureStorageMode: NSNumber(value: MTLStorageMode.shared.rawValue)
            ])
            
            let mappedTexture = productionManager.outputMappingManager.applyOutputMapping(to: inputTexture)
            
            if let outputTexture = mappedTexture {
                return createCGImageFromTexture(outputTexture, device: productionManager.outputMappingManager.metalDevice)
            }
            
            return image
        } catch {
            print("Error applying output mapping: \(error)")
            return image
        }
    }
}

// MARK: - Helper Functions

@MainActor
func processImageWithEffectsAsync(_ image: CGImage, using effectManager: EffectManager, sourceID: String) -> CGImage? {
    let textureLoader = MTKTextureLoader(device: effectManager.metalDevice)
    
    do {
        let inputTexture = try textureLoader.newTexture(cgImage: image, options: [
            MTKTextureLoader.Option.textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            MTKTextureLoader.Option.textureStorageMode: NSNumber(value: MTLStorageMode.shared.rawValue)
        ])
        
        let processedTexture = effectManager.applyEffects(to: inputTexture, for: sourceID)
        
        if let outputTexture = processedTexture {
            return createCGImageFromTexture(outputTexture, device: effectManager.metalDevice)
        }
        
        return image
    } catch {
        print("Error processing image with effects: \(error)")
        return image
    }
}

@MainActor
func createCGImageFromTexture(_ texture: MTLTexture, device: MTLDevice) -> CGImage? {
    let ciImage = CIImage(mtlTexture: texture, options: [
        .colorSpace: CGColorSpaceCreateDeviceRGB()
    ])
    
    guard let image = ciImage else { return nil }
    
    let flippedImage = image.transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -image.extent.height))
    
    let context = CIContext(mtlDevice: device, options: [
        .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
        .outputColorSpace: CGColorSpaceCreateDeviceRGB()
    ])
    
    return context.createCGImage(flippedImage, from: flippedImage.extent)
}