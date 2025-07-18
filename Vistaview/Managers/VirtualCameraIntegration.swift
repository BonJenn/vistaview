import Foundation
import AVFoundation
import Metal
import SceneKit
import Combine

// MARK: - Virtual Camera Source Manager

@MainActor
class VirtualCameraSourceManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isVirtualCameraActive = false
    @Published var activeVirtualCamera: VirtualCamera?
    @Published var renderingFPS: Double = 0
    @Published var renderingQuality: VirtualRenderQuality = .high
    
    // MARK: - Core Components
    
    private let metalRenderer: VirtualCameraRenderer
    private var renderTimer: Timer?
    private var studioScene: SCNScene?
    
    // Streaming integration
    private var pixelBufferOutput: ((CVPixelBuffer) -> Void)?
    private var isRendering = false
    
    // Performance tracking
    private var frameCounter = 0
    private var lastFPSUpdate = CFAbsoluteTimeGetCurrent()
    
    // MARK: - Initialization
    
    init() {
        guard let renderer = VirtualCameraRenderer(renderSize: CGSize(width: 1920, height: 1080)) else {
            fatalError("❌ Failed to initialize Metal renderer")
        }
        self.metalRenderer = renderer
        print("✅ VirtualCameraSourceManager initialized")
    }
    
    deinit {
        renderTimer?.invalidate()
        renderTimer = nil
    }
    
    // MARK: - Virtual Camera Control
    
    func startVirtualCamera(_ camera: VirtualCamera, scene: SCNScene, outputHandler: @escaping (CVPixelBuffer) -> Void) {
        guard !isRendering else {
            print("⚠️ Virtual camera already rendering")
            return
        }
        
        activeVirtualCamera = camera
        studioScene = scene
        pixelBufferOutput = outputHandler
        isRendering = true
        isVirtualCameraActive = true
        
        startRenderingTimer()
        print("🎥 Virtual camera started - Camera: \(camera.name)")
    }
    
    func stopVirtualCamera() {
        guard isRendering else { return }
        
        isRendering = false
        isVirtualCameraActive = false
        stopRenderingTimer()
        
        activeVirtualCamera = nil
        studioScene = nil
        pixelBufferOutput = nil
        
        print("🛑 Virtual camera stopped")
    }
    
    func switchVirtualCamera(to camera: VirtualCamera) {
        guard isRendering else {
            print("⚠️ Cannot switch camera - not currently rendering")
            return
        }
        
        activeVirtualCamera = camera
        print("🔄 Switched to virtual camera: \(camera.name)")
    }
    
    // MARK: - Rendering Timer (macOS Compatible)
    
    private func startRenderingTimer() {
        stopRenderingTimer()
        renderTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.renderFrame()
        }
    }
    
    private func stopRenderingTimer() {
        renderTimer?.invalidate()
        renderTimer = nil
    }
    
    // MARK: - Rendering Loop
    
    private func renderFrame() {
        guard isRendering,
              let camera = activeVirtualCamera,
              let scene = studioScene,
              let outputHandler = pixelBufferOutput else {
            return
        }
        
        autoreleasepool {
            if let pixelBuffer = metalRenderer.renderFrame(from: camera, scene: scene) {
                outputHandler(pixelBuffer)
                updateFPSTracking()
            }
        }
    }
    
    private func updateFPSTracking() {
        frameCounter += 1
        let now = CFAbsoluteTimeGetCurrent()
        
        if now - lastFPSUpdate >= 1.0 {
            renderingFPS = Double(frameCounter)
            frameCounter = 0
            lastFPSUpdate = now
        }
    }
    
    // MARK: - Quality Control
    
    func setRenderingQuality(_ quality: VirtualRenderQuality) {
        renderingQuality = quality
        
        let newSize: CGSize
        switch quality {
        case .low:
            newSize = CGSize(width: 1280, height: 720)
        case .medium:
            newSize = CGSize(width: 1600, height: 900)
        case .high:
            newSize = CGSize(width: 1920, height: 1080)
        case .ultra:
            newSize = CGSize(width: 2560, height: 1440)
        }
        
        metalRenderer.updateRenderSize(newSize)
        print("🎨 Rendering quality set to \(quality) - \(newSize)")
    }
    
    // MARK: - Diagnostics
    
    func getDiagnostics() -> VirtualCameraDiagnostics {
        return VirtualCameraDiagnostics(
            isActive: isVirtualCameraActive,
            currentFPS: renderingFPS,
            quality: renderingQuality,
            activeCameraName: activeVirtualCamera?.name ?? "None",
            metalDeviceInfo: metalRenderer.getDeviceInfo(),
            renderingLatency: renderingFPS > 0 ? 1.0 / renderingFPS : 0
        )
    }
}

// MARK: - StreamingViewModel Extension

extension StreamingViewModel {
    
    private static var virtualCameraManager: VirtualCameraSourceManager?
    
    func enableVirtualCamera() {
        if Self.virtualCameraManager == nil {
            Self.virtualCameraManager = VirtualCameraSourceManager()
        }
    }
    
    func startVirtualCameraStream(camera: VirtualCamera, scene: SCNScene) {
        enableVirtualCamera()
        
        guard let manager = Self.virtualCameraManager else {
            print("❌ Virtual camera manager not available")
            return
        }
        
        manager.startVirtualCamera(camera, scene: scene) { [weak self] pixelBuffer in
            self?.injectVirtualFrame(pixelBuffer)
        }
        
        print("🚀 Virtual camera stream started")
    }
    
    func stopVirtualCameraStream() {
        Self.virtualCameraManager?.stopVirtualCamera()
        print("🛑 Virtual camera stream stopped")
    }
    
    func switchVirtualCamera(to camera: VirtualCamera) {
        Self.virtualCameraManager?.switchVirtualCamera(to: camera)
    }
    
    private func injectVirtualFrame(_ pixelBuffer: CVPixelBuffer) {
        // TODO: Integration with HaishinKit pipeline
        // print("📽️ Virtual frame injected")
    }
    
    var isVirtualCameraActive: Bool {
        return Self.virtualCameraManager?.isVirtualCameraActive ?? false
    }
    
    func getVirtualCameraInfo() -> VirtualCameraDiagnostics? {
        return Self.virtualCameraManager?.getDiagnostics()
    }
}

// MARK: - UnifiedProductionManager Extension

extension UnifiedProductionManager {
    
    func startVirtualCameraStreaming() {
        guard let activeCamera = availableVirtualCameras.first(where: { $0.isActive }) else {
            print("⚠️ No active virtual camera selected")
            return
        }
        
        streamingViewModel.startVirtualCameraStream(
            camera: activeCamera,
            scene: studioManager.scene
        )
        
        print("🎬 Virtual camera streaming started - Camera: \(activeCamera.name)")
    }
    
    func stopVirtualCameraStreaming() {
        streamingViewModel.stopVirtualCameraStream()
        print("🛑 Virtual camera streaming stopped")
    }
    
    func switchToVirtualCamera(_ camera: VirtualCamera) {
        // Use existing selectVirtualCamera method
        selectVirtualCamera(camera)
        
        // If already streaming, switch cameras
        if streamingViewModel.isVirtualCameraActive {
            streamingViewModel.switchVirtualCamera(to: camera)
            print("🔄 Switched virtual camera while streaming")
        }
    }
}

// MARK: - Supporting Types

enum VirtualRenderQuality: String, CaseIterable {
    case low = "720p"
    case medium = "900p"
    case high = "1080p"
    case ultra = "1440p"
    
    var displayName: String {
        switch self {
        case .low: return "Low (720p)"
        case .medium: return "Medium (900p)"
        case .high: return "High (1080p)"
        case .ultra: return "Ultra (1440p)"
        }
    }
}

struct VirtualCameraDiagnostics {
    let isActive: Bool
    let currentFPS: Double
    let quality: VirtualRenderQuality
    let activeCameraName: String
    let metalDeviceInfo: String
    let renderingLatency: Double
    
    var summary: String {
        return """
        🎥 Virtual Camera Status:
        Active: \(isActive ? "✅" : "❌")
        Camera: \(activeCameraName)
        FPS: \(String(format: "%.1f", currentFPS))
        Quality: \(quality.displayName)
        Latency: \(String(format: "%.1f", renderingLatency * 1000))ms
        """
    }
}

// MARK: - Performance Monitoring

class VirtualCameraPerformanceMonitor: ObservableObject {
    
    @Published var averageFPS: Double = 0
    @Published var frameDrops: Int = 0
    @Published var memoryUsage: Double = 0
    @Published var renderingLatency: Double = 0
    
    private var fpsHistory: [Double] = []
    private let maxHistorySize = 60
    
    func updateMetrics(fps: Double, latency: Double, memoryMB: Double) {
        fpsHistory.append(fps)
        
        if fpsHistory.count > maxHistorySize {
            fpsHistory.removeFirst()
        }
        
        averageFPS = fpsHistory.reduce(0, +) / Double(fpsHistory.count)
        renderingLatency = latency
        memoryUsage = memoryMB
        
        if fps < 55 {
            frameDrops += 1
        }
    }
    
    func reset() {
        fpsHistory.removeAll()
        frameDrops = 0
        averageFPS = 0
        renderingLatency = 0
        memoryUsage = 0
    }
}
