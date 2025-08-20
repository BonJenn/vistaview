//
//  AdvancedCameraDebugView.swift
//  Vistaview
//
//  Created by AI Assistant
//

import SwiftUI
import AVFoundation

struct AdvancedCameraDebugView: View {
    @State private var debugOutput: [String] = []
    @State private var isRunningDiagnostic = false
    @State private var testSession: AVCaptureSession?
    @State private var frameCount = 0
    @State private var lastFrameTime: Date?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Advanced Camera Diagnostic")
                .font(.title)
                .padding()
            
            HStack(spacing: 15) {
                Button("Run Full Diagnostic") {
                    runFullDiagnostic()
                }
                .disabled(isRunningDiagnostic)
                
                Button("Test Frame Reception") {
                    testFrameReception()
                }
                .disabled(isRunningDiagnostic || testSession != nil)
                
                Button("Stop Test") {
                    stopFrameTest()
                }
                .disabled(testSession == nil)
                
                Button("Clear Log") {
                    debugOutput.removeAll()
                    frameCount = 0
                    lastFrameTime = nil
                }
            }
            
            // Live frame counter
            if testSession != nil {
                VStack {
                    Text("Live Frame Test Running")
                        .font(.headline)
                        .foregroundColor(.green)
                    
                    Text("Frames received: \(frameCount)")
                        .font(.monospaced(.title2)())
                        .foregroundColor(.blue)
                    
                    if let lastTime = lastFrameTime {
                        Text("Last frame: \(lastTime.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Debug output
            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(debugOutput.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(colorForLogLine(line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(8)
                    .onChange(of: debugOutput.count) { _, _ in
                        if let lastIndex = debugOutput.indices.last {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxHeight: 400)
            .background(Color.black.opacity(0.9))
            .cornerRadius(8)
        }
        .padding()
        .frame(width: 800, height: 600)
    }
    
    private func runFullDiagnostic() {
        isRunningDiagnostic = true
        debugOutput.removeAll()
        
        Task {
            await CameraSessionDiagnostic.runFullDiagnostic()
            await MainActor.run {
                isRunningDiagnostic = false
            }
        }
    }
    
    private func testFrameReception() {
        debugOutput.removeAll()
        frameCount = 0
        lastFrameTime = nil
        
        addLog("🧪 Starting frame reception test...")
        
        guard let camera = AVCaptureDevice.default(for: .video) else {
            addLog("❌ No camera device found")
            return
        }
        
        addLog("📹 Using camera: \(camera.localizedName)")
        
        do {
            let session = AVCaptureSession()
            session.beginConfiguration()
            
            // Minimal configuration
            session.sessionPreset = .low
            addLog("   Set session preset to: low")
            
            // Add input
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
                addLog("✅ Added camera input")
            } else {
                addLog("❌ Cannot add camera input")
                return
            }
            
            // Add output with delegate
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            
            let delegate = FrameTestDelegate {
                Task { @MainActor in
                    self.frameCount += 1
                    self.lastFrameTime = Date()
                    
                    if self.frameCount == 1 {
                        self.addLog("🎉 FIRST FRAME RECEIVED!")
                    }
                    
                    if self.frameCount % 30 == 0 {
                        self.addLog("📊 Received \(self.frameCount) frames")
                    }
                }
            }
            
            let queue = DispatchQueue(label: "frame.test.queue", qos: .userInitiated)
            output.setSampleBufferDelegate(delegate, queue: queue)
            
            if session.canAddOutput(output) {
                session.addOutput(output)
                addLog("✅ Added video output with delegate")
            } else {
                addLog("❌ Cannot add video output")
                return
            }
            
            session.commitConfiguration()
            addLog("✅ Session configuration committed")
            
            // Start session
            addLog("🎬 Starting capture session...")
            session.startRunning()
            
            // Verify session started
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if session.isRunning {
                    self.addLog("✅ Session is running")
                    self.addLog("   - Inputs: \(session.inputs.count)")
                    self.addLog("   - Outputs: \(session.outputs.count)")
                    
                    if let connection = output.connection(with: .video) {
                        self.addLog("   - Video connection active: \(connection.isActive)")
                        self.addLog("   - Video connection enabled: \(connection.isEnabled)")
                    }
                    
                    // Check for frames after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        if self.frameCount == 0 {
                            self.addLog("⚠️ WARNING: No frames received after 3 seconds")
                            self.addLog("   This indicates the delegate is not being called")
                        }
                    }
                } else {
                    self.addLog("❌ Session failed to start")
                }
            }
            
            testSession = session
            
        } catch {
            addLog("❌ Error setting up test: \(error)")
        }
    }
    
    private func stopFrameTest() {
        testSession?.stopRunning()
        testSession = nil
        addLog("🛑 Frame test stopped")
        addLog("📊 Total frames received: \(frameCount)")
    }
    
    private func addLog(_ message: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        debugOutput.append("[\(timestamp)] \(message)")
        
        // Also print to console
        print(message)
        
        // Keep only last 200 entries
        if debugOutput.count > 200 {
            debugOutput.removeFirst()
        }
    }
    
    private func colorForLogLine(_ line: String) -> Color {
        if line.contains("❌") || line.contains("Error") {
            return .red
        } else if line.contains("⚠️") || line.contains("WARNING") {
            return .orange
        } else if line.contains("✅") || line.contains("🎉") {
            return .green
        } else if line.contains("🧪") || line.contains("📹") {
            return .blue
        } else {
            return .white
        }
    }
}

class FrameTestDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let onFrame: () -> Void
    
    init(onFrame: @escaping () -> Void) {
        self.onFrame = onFrame
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onFrame()
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("⚠️ Frame test: Dropped frame")
    }
}

#Preview {
    AdvancedCameraDebugView()
}