import Foundation
import SwiftUI
import AppKit
import Combine
import Metal
import MetalKit

@MainActor
class ExternalDisplayManager: ObservableObject {
    @Published var availableDisplays: [DisplayInfo] = []
    @Published var selectedDisplay: DisplayInfo?
    @Published var isFullScreenActive: Bool = false
    @Published var externalWindow: NSWindow?
    
    private var productionManager: UnifiedProductionManager?
    private var cancellables = Set<AnyCancellable>()
    
    struct DisplayInfo: Identifiable, Equatable {
        let id: CGDirectDisplayID
        let name: String
        let bounds: CGRect
        let isMain: Bool
        
        static func == (lhs: DisplayInfo, rhs: DisplayInfo) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    init() {
        scanForDisplays()
        setupDisplayChangeNotification()
    }
    
    func setProductionManager(_ manager: UnifiedProductionManager) {
        self.productionManager = manager
        
        // Don't set up subscriptions immediately - only when external display is active
        // This prevents interference with main UI camera feed updates
        print("🖥️ External Display Manager: Production manager set, subscriptions will be activated when external display starts")
    }
    
    private func setupCameraFeedSubscriptions() {
        guard let productionManager = productionManager else { return }
        
        // Clear any existing subscriptions first
        cancellables.removeAll()
        
        // Only subscribe when external display is actually active
        if isFullScreenActive {
            print("🖥️ External Display: Setting up camera feed subscriptions")
            
            // Subscribe to changes in the selected camera feed
            productionManager.cameraFeedManager.$selectedFeedForLiveProduction
                .sink { [weak self] selectedFeed in
                    Task { @MainActor in
                        self?.handleSelectedFeedChange(selectedFeed)
                    }
                }
                .store(in: &cancellables)
            
            // Subscribe to changes in active feeds
            productionManager.cameraFeedManager.$activeFeeds
                .sink { [weak self] activeFeeds in
                    Task { @MainActor in
                        self?.handleActiveFeedsChange(activeFeeds)
                    }
                }
                .store(in: &cancellables)
        }
    }
    
    private func handleSelectedFeedChange(_ selectedFeed: CameraFeed?) {
        print("🔄 External Display: Selected feed changed to \(selectedFeed?.device.displayName ?? "none")")
        // The external display content view will automatically pick up this change
        if isFullScreenActive {
            print("   - External display is active, feed change will be reflected automatically")
        }
    }
    
    private func handleActiveFeedsChange(_ activeFeeds: [CameraFeed]) {
        print("🔄 External Display: Active feeds changed - count: \(activeFeeds.count)")
        for feed in activeFeeds {
            print("   - \(feed.device.displayName): \(feed.connectionStatus.displayText)")
        }
    }
    
    private func scanForDisplays() {
        var displayCount: UInt32 = 0
        var result = CGGetActiveDisplayList(0, nil, &displayCount)
        guard result == CGError.success else { return }
        
        let displays = UnsafeMutablePointer<CGDirectDisplayID>.allocate(capacity: Int(displayCount))
        defer { displays.deallocate() }
        
        result = CGGetActiveDisplayList(displayCount, displays, &displayCount)
        guard result == CGError.success else { return }
        
        availableDisplays = (0..<displayCount).compactMap { index in
            let displayID = displays[Int(index)]
            let bounds = CGDisplayBounds(displayID)
            let isMain = CGDisplayIsMain(displayID) != 0
            
            return DisplayInfo(
                id: displayID,
                name: isMain ? "Main Display" : "External Display \(displayID)",
                bounds: bounds,
                isMain: isMain
            )
        }
    }
    
    private func setupDisplayChangeNotification() {
        // Monitor for display configuration changes
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.scanForDisplays()
            }
            .store(in: &cancellables)
    }
    
    func startFullScreenOutput(on display: DisplayInfo) {
        guard let productionManager = productionManager else { return }
        
        // Close existing window if any
        stopFullScreenOutput()
        
        // Set up camera feed subscriptions now that external display is starting
        setupCameraFeedSubscriptions()
        
        // Create full-screen window on the selected display
        let screen = NSScreen.screens.first { screen in
            let screenFrame = screen.frame
            return abs(screenFrame.origin.x - display.bounds.origin.x) < 1.0 &&
                   abs(screenFrame.origin.y - display.bounds.origin.y) < 1.0
        }
        
        guard let targetScreen = screen else {
            print("❌ Could not find NSScreen for display")
            return
        }
        
        // Create window that fills the entire screen
        let window = NSWindow(
            contentRect: targetScreen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: targetScreen
        )
        
        window.level = .floating
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = false
        
        // Create the content view with proper bindings
        let contentView = ExternalDisplayContentView(
            productionManager: productionManager,
            displaySize: targetScreen.frame.size
        )
        
        let hostingView = NSHostingView(rootView: contentView)
        window.contentView = hostingView
        
        // Show window
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)
        
        self.externalWindow = window
        self.selectedDisplay = display
        self.isFullScreenActive = true
        
        print("🖥️ Started full-screen output on \(display.name)")
    }
    
    func stopFullScreenOutput() {
        if let window = externalWindow {
            if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
            window.close()
        }
        
        // Clear camera feed subscriptions when external display stops
        cancellables.removeAll()
        
        externalWindow = nil
        selectedDisplay = nil
        isFullScreenActive = false
        
        print("🖥️ Stopped full-screen output and cleared camera subscriptions")
    }
}

// MARK: - External Display Content View

struct ExternalDisplayContentView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    let displaySize: CGSize
    @State private var frameUpdateTrigger = 0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Directly observe the selected camera feed and show its current image
            if let selectedFeed = productionManager.cameraFeedManager.selectedFeedForLiveProduction,
               selectedFeed.connectionStatus == .connected,
               let image = selectedFeed.previewImage {
                
                Image(decorative: processImageForExternalDisplay(image), scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: displaySize.width, height: displaySize.height)
                    .clipped()
                    .id("external-display-\(selectedFeed.id)-\(frameUpdateTrigger)")
                    .onReceive(Timer.publish(every: 1.0/30.0, on: .main, in: .common).autoconnect()) { _ in
                        frameUpdateTrigger += 1
                    }
                    
            } else {
                // No video source or camera not connected - show status
                VStack(spacing: 20) {
                    Image(systemName: "tv")
                        .font(.system(size: 100))
                        .foregroundColor(.white.opacity(0.3))
                    
                    Text("Vistaview External Output")
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.7))
                    
                    VStack(spacing: 8) {
                        if let selectedFeed = productionManager.cameraFeedManager.selectedFeedForLiveProduction {
                            Text("Camera: \(selectedFeed.device.displayName)")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.6))
                            
                            Text("Status: \(selectedFeed.connectionStatus.displayText)")
                                .font(.title3)
                                .foregroundColor(selectedFeed.connectionStatus.color.opacity(0.8))
                            
                            if selectedFeed.connectionStatus == .connected {
                                Text("Frame Count: \(selectedFeed.frameCount)")
                                    .font(.caption)
                                    .foregroundColor(.green.opacity(0.7))
                                
                                Text("Has Preview: \(selectedFeed.previewImage != nil ? "Yes" : "No")")
                                    .font(.caption)
                                    .foregroundColor(selectedFeed.previewImage != nil ? .green.opacity(0.7) : .red.opacity(0.7))
                                
                                Text("Last frame update: \(Date().formatted(.dateTime.hour().minute().second()))")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                        } else {
                            Text("No camera selected")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.5))
                            
                            if !productionManager.cameraFeedManager.availableDevices.isEmpty {
                                Text("Available: \(productionManager.cameraFeedManager.availableDevices.count) camera(s)")
                                    .font(.callout)
                                    .foregroundColor(.blue.opacity(0.7))
                                
                                Text("Active feeds: \(productionManager.cameraFeedManager.activeFeeds.count)")
                                    .font(.callout)
                                    .foregroundColor(.green.opacity(0.7))
                            }
                        }
                    }
                }
            }
            
            // Output mapping status overlay (only show briefly)
            if productionManager.outputMappingManager.isEnabled {
                VStack {
                    HStack {
                        VStack(alignment: .leading) {
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
                    Spacer()
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .opacity(frameUpdateTrigger % 300 < 60 ? 1.0 : 0.0) // Show for 2 seconds every 10 seconds
                .animation(.easeInOut(duration: 0.5), value: frameUpdateTrigger % 300 < 60)
            }
        }
        .onAppear {
            print("🖥️ External Display: Content view appeared")
            logCurrentCameraState()
        }
        .onDisappear {
            print("🖥️ External Display: Content view disappeared")
        }
    }
    
    private func logCurrentCameraState() {
        print("📊 External Display: Current camera state:")
        print("   - Available devices: \(productionManager.cameraFeedManager.availableDevices.count)")
        print("   - Active feeds: \(productionManager.cameraFeedManager.activeFeeds.count)")
        
        if let selectedFeed = productionManager.cameraFeedManager.selectedFeedForLiveProduction {
            print("   - Selected feed: \(selectedFeed.device.displayName)")
            print("   - Feed status: \(selectedFeed.connectionStatus.displayText)")
            print("   - Frame count: \(selectedFeed.frameCount)")
            print("   - Has preview: \(selectedFeed.previewImage != nil)")
        } else {
            print("   - No selected feed")
        }
        
        for feed in productionManager.cameraFeedManager.activeFeeds {
            print("   - Active feed: \(feed.device.displayName) - \(feed.connectionStatus.displayText) - frames: \(feed.frameCount)")
        }
    }
    
    private func processImageForExternalDisplay(_ image: CGImage) -> CGImage {
        var processedImage = image
        
        // Apply effects if any from the program source
        let programSource = productionManager.previewProgramManager.programSource
        if case .camera(let feed) = programSource,
           feed.id == productionManager.cameraFeedManager.selectedFeedForLiveProduction?.id {
            // Apply program effects
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
        
        // Apply output mapping if enabled
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
    // Convert CGImage to MTLTexture
    let textureLoader = MTKTextureLoader(device: effectManager.metalDevice)
    
    do {
        let inputTexture = try textureLoader.newTexture(cgImage: image, options: [
            MTKTextureLoader.Option.textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            MTKTextureLoader.Option.textureStorageMode: NSNumber(value: MTLStorageMode.shared.rawValue)
        ])
        
        // Apply effects
        let processedTexture = effectManager.applyEffects(to: inputTexture, for: sourceID)
        
        // Convert back to CGImage with proper coordinate handling
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
    // Create a CIImage from the Metal texture with proper coordinate handling
    let ciImage = CIImage(mtlTexture: texture, options: [
        .colorSpace: CGColorSpaceCreateDeviceRGB()
    ])
    
    guard let image = ciImage else { return nil }
    
    // Apply a transform to correct the coordinate system (flip vertically)
    let flippedImage = image.transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -image.extent.height))
    
    // Create a CIContext and render to CGImage
    let context = CIContext(mtlDevice: device, options: [
        .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
        .outputColorSpace: CGColorSpaceCreateDeviceRGB()
    ])
    
    // Render with proper bounds
    return context.createCGImage(flippedImage, from: flippedImage.extent)
}