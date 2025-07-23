//
//  VirtualCameraIntegration.swift
//  Vistaview
//
//  Created by You, rescued by ChatGPT.
//

import Foundation
import SceneKit
import AVFoundation
import Combine
import CoreVideo
import simd

/// Handles rendering a virtual camera POV to a CVPixelBuffer and piping it into your streaming stack.
@MainActor
final class VirtualCameraSourceManager: ObservableObject {
    
    // MARK: - Published state
    @Published private(set) var isStreamingVirtualFeed = false
    @Published private(set) var currentCamera: VirtualCamera?
    @Published private(set) var fps: Double = 0
    @Published private(set) var lastFrameTime: CFTimeInterval = 0
    
    // MARK: - Dependencies
    let studioManager: VirtualStudioManager
    let streamingViewModel: StreamingViewModel
    
    // MARK: - Rendering
    private var renderTimer: Timer?
    private var lastTimestamp: CFTimeInterval = 0
    private var renderer: VirtualCameraFrameRenderer
    
    // MARK: - Init
    init(studioManager: VirtualStudioManager,
         streamingViewModel: StreamingViewModel,
         renderer: VirtualCameraFrameRenderer = StubVirtualCameraFrameRenderer()) {
        self.studioManager = studioManager
        self.streamingViewModel = streamingViewModel
        self.renderer = renderer
    }
    
    // MARK: - API mirrors old names you referenced elsewhere
    
    /// What you previously called `availableVirtualCameras`
    var availableVirtualCameras: [VirtualCamera] {
        studioManager.virtualCameras
    }
    
    /// What you previously called `selectVirtualCamera`
    func selectVirtualCamera(_ camera: VirtualCamera) {
        studioManager.selectCamera(camera)
        currentCamera = camera
        renderer.pointOfView = camera.node
    }
    
    func startVirtualStream(targetFPS: Double = 60) {
        guard !isStreamingVirtualFeed else { return }
        isStreamingVirtualFeed = true
        
        let interval = 1.0 / targetFPS
        lastTimestamp = CFAbsoluteTimeGetCurrent()
        
        // Timer fires on run loop (nonisolated). Hop back to MainActor before touching state.
        renderTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.tick() }
        }
        RunLoop.main.add(renderTimer!, forMode: .common)
    }
    
    func stopVirtualStream() {
        guard isStreamingVirtualFeed else { return }
        isStreamingVirtualFeed = false
        renderTimer?.invalidate()
        renderTimer = nil
    }
    
    deinit { renderTimer?.invalidate() }
    
    // MARK: - Frame loop
    @MainActor
    private func tick() {
        let now = CFAbsoluteTimeGetCurrent()
        let delta = now - lastTimestamp
        lastTimestamp = now
        if delta > 0 { fps = 1.0 / delta }
        lastFrameTime = now
        
        guard let pov = currentCamera?.node else { return }
        
        if let pixelBuffer = renderer.renderFrame(pointOfView: pov, scene: studioManager.scene) {
            streamingViewModel.injectVirtualFrame(pixelBuffer)
        }
    }
}

// MARK: - Renderer Protocol

protocol VirtualCameraFrameRenderer {
    var pointOfView: SCNNode? { get set }
    func renderFrame(pointOfView: SCNNode, scene: SCNScene) -> CVPixelBuffer?
}

// Stub so you compile until the Metal renderer is wired
final class StubVirtualCameraFrameRenderer: VirtualCameraFrameRenderer {
    var pointOfView: SCNNode?
    func renderFrame(pointOfView: SCNNode, scene: SCNScene) -> CVPixelBuffer? { nil }
}

// MARK: - Streaming pipeline hook
extension StreamingViewModel {
    /// Implement me: push a CVPixelBuffer into HaishinKit / AVFoundation encoder
    func injectVirtualFrame(_ pixelBuffer: CVPixelBuffer) {
        // TODO: Your actual integration here
    }
}
