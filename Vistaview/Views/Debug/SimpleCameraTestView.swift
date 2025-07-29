//
//  SimpleCameraTestView.swift
//  Vistaview
//
//  Created by AI Assistant
//

import SwiftUI
import AVFoundation

struct SimpleCameraTestView: View {
    @State private var captureSession: AVCaptureSession?
    @State private var currentImage: NSImage?
    @State private var statusMessage = "Ready to test"
    @State private var frameCount = 0
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Simple Camera Test")
                .font(.title)
            
            Text(statusMessage)
                .font(.callout)
                .foregroundColor(.secondary)
            
            // Preview area
            Group {
                if let image = currentImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 400, maxHeight: 300)
                        .border(Color.green, width: 2)
                } else {
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: 400, height: 300)
                        .overlay(
                            VStack {
                                Image(systemName: "camera")
                                    .font(.largeTitle)
                                    .foregroundColor(.white)
                                Text("No camera preview")
                                    .foregroundColor(.white)
                                Text("Frames received: \(frameCount)")
                                    .foregroundColor(.green)
                                    .font(.monospaced(.caption)())
                            }
                        )
                }
            }
            
            HStack(spacing: 20) {
                Button("Start Camera") {
                    startCamera()
                }
                .disabled(captureSession?.isRunning == true)
                
                Button("Stop Camera") {
                    stopCamera()
                }
                .disabled(captureSession?.isRunning != true)
            }
        }
        .padding()
        .frame(width: 500, height: 500)
    }
    
    private func startCamera() {
        statusMessage = "Starting camera..."
        
        guard let camera = AVCaptureDevice.default(for: .video) else {
            statusMessage = "No camera found"
            return
        }
        
        print("🎥 Simple test: Starting camera \(camera.localizedName)")
        
        let session = AVCaptureSession()
        
        do {
            // Add input
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
                print("✅ Simple test: Added input")
            } else {
                statusMessage = "Cannot add camera input"
                return
            }
            
            // Add output
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            let delegate = SimpleVideoDelegate { image in
                Task { @MainActor in
                    self.currentImage = image
                    self.frameCount += 1
                    self.statusMessage = "Receiving frames (\(self.frameCount))"
                }
            }
            
            let queue = DispatchQueue(label: "simple.camera.queue")
            output.setSampleBufferDelegate(delegate, queue: queue)
            
            if session.canAddOutput(output) {
                session.addOutput(output)
                print("✅ Simple test: Added output")
            } else {
                statusMessage = "Cannot add camera output"
                return
            }
            
            captureSession = session
            session.startRunning()
            
            if session.isRunning {
                statusMessage = "Camera running - waiting for frames..."
                print("✅ Simple test: Session started successfully")
            } else {
                statusMessage = "Failed to start camera session"
                print("❌ Simple test: Session failed to start")
            }
            
        } catch {
            statusMessage = "Camera error: \(error.localizedDescription)"
            print("❌ Simple test error: \(error)")
        }
    }
    
    private func stopCamera() {
        captureSession?.stopRunning()
        captureSession = nil
        currentImage = nil
        frameCount = 0
        statusMessage = "Camera stopped"
        print("🛑 Simple test: Camera stopped")
    }
}

class SimpleVideoDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let onFrame: (NSImage) -> Void
    
    init(onFrame: @escaping (NSImage) -> Void) {
        self.onFrame = onFrame
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("❌ Simple test: No pixel buffer")
            return
        }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("❌ Simple test: Failed to create CGImage")
            return
        }
        
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        onFrame(nsImage)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("⚠️ Simple test: Dropped frame")
    }
}

#Preview {
    SimpleCameraTestView()
}