import Foundation
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import CoreVideo
import CoreMedia

@MainActor
final class RecordingService: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var lastError: String?
    @Published private(set) var outputURL: URL?
    @Published private(set) var diagnostics: Diagnostics = .init()
    @Published var isEnabledByLicense: Bool = true
    @Published var isRecordActionAvailable: Bool = false
    
    struct Diagnostics: Sendable {
        var droppedVideo: Int = 0
        var droppedAudio: Int = 0
        var avgLatencyMs: Double = 0
        var bitrateBps: Double = 0
    }
    
    private let recorder = ProgramRecorder()
    private lazy var tap = ProgramFrameTap(recorder: recorder)
    private var tickerTask: Task<Void, Never>?
    private var diagTask: Task<Void, Never>?
    private var startedAt: Date?
    private var productionManager: UnifiedProductionManager?
    
    func sink() -> RecordingSink { tap }
    
    func setProductionManager(_ manager: UnifiedProductionManager) {
        self.productionManager = manager
    }
    
    func startOrStop(container: ProgramRecorder.Container = .mov) {
        print("🎬 RecordingService: startOrStop() called")
        print("🎬 RecordingService: Current state - isRecording: \(isRecording)")
        
        if isRecording {
            print("🎬 RecordingService: Stopping recording...")
            Task {
                _ = await stopRecording()
            }
        } else {
            print("🎬 RecordingService: Starting recording...")
            Task {
                do {
                    try await startRecording(container: container)
                } catch {
                    print("🎬 RecordingService: Start recording failed: \(error)")
                    lastError = error.localizedDescription
                }
            }
        }
    }
    
    func startRecording(container: ProgramRecorder.Container = .mov) async throws {
        guard isEnabledByLicense else {
            lastError = "Recording requires a higher license tier."
            print("🎬 RecordingService: ERROR - Recording not enabled by license")
            return
        }
        guard isRecordActionAvailable else {
            lastError = "Program output is not active."
            print("🎬 RecordingService: ERROR - Program output not active")
            print("🎬 RecordingService: Debug - isRecordActionAvailable: \(isRecordActionAvailable)")
            return
        }
        
        print("🎬 RecordingService: ====== STARTING RECORDING PIPELINE ======")
        print("🎬 RecordingService: Current state - isRecording: \(isRecording), isEnabledByLicense: \(isEnabledByLicense), isRecordActionAvailable: \(isRecordActionAvailable)")
        
        let defaultName = defaultFileName(container: container)
        print("🎬 RecordingService: Generated default name: \(defaultName)")
        
        var saveURL: URL
        var needsSecurityScope = false
        
        #if os(macOS)
        do {
            saveURL = try await chooseOutputURL(defaultName: defaultName, allowedTypes: [container.utType])
            needsSecurityScope = true
            print("🎬 RecordingService: User selected URL: \(saveURL.path)")
            
            // Try to access the security-scoped resource
            let hasAccess = saveURL.startAccessingSecurityScopedResource()
            print("🎬 RecordingService: Security-scoped resource access: \(hasAccess)")
            
            // Test access by trying to write to the location
            do {
                print("🎬 RecordingService: Testing write access to user-selected location...")
                let testData = Data("test".utf8)
                try testData.write(to: saveURL)
                try FileManager.default.removeItem(at: saveURL)
                print("🎬 RecordingService: ✅ User-selected location is writable")
            } catch {
                print("🎬 RecordingService: ❌ Cannot write to user-selected location: \(error)")
                print("🎬 RecordingService: Falling back to Movies directory...")
                
                // Stop accessing the failed location
                if hasAccess {
                    saveURL.stopAccessingSecurityScopedResource()
                }
                needsSecurityScope = false
                
                // Fallback to Movies directory (typically accessible)
                let moviesURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
                saveURL = moviesURL.appendingPathComponent(defaultName)
                
                // Test fallback location
                do {
                    let testData = Data("test".utf8)
                    try testData.write(to: saveURL)
                    try FileManager.default.removeItem(at: saveURL)
                    print("🎬 RecordingService: ✅ Movies directory is writable")
                } catch {
                    print("🎬 RecordingService: ❌ Even Movies directory is not writable: \(error)")
                    
                    // Last resort: Documents directory
                    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    saveURL = documentsURL.appendingPathComponent(defaultName)
                    print("🎬 RecordingService: Final fallback to Documents: \(saveURL.path)")
                }
            }
        } catch {
            print("🎬 RecordingService: User cancelled file selection or error: \(error)")
            throw CancellationError()
        }
        
        #else
        saveURL = FileManager.default.temporaryDirectory.appendingPathComponent(defaultName)
        print("🎬 RecordingService: Using temp URL: \(saveURL.path)")
        #endif
        
        // Final verification that we can write to the chosen location
        do {
            print("🎬 RecordingService: Final write test for location: \(saveURL.path)")
            let testData = Data("test".utf8)
            try testData.write(to: saveURL)
            try FileManager.default.removeItem(at: saveURL)
            print("🎬 RecordingService: ✅ Final location verified writable")
        } catch {
            print("🎬 RecordingService: ❌ FATAL: Cannot write to any location: \(error)")
            if needsSecurityScope {
                saveURL.stopAccessingSecurityScopedResource()
            }
            throw NSError(domain: "RecordingService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Cannot write to any accessible location: \(error.localizedDescription)"])
        }
        
        // Store the URL and security scope flag
        self.outputURL = saveURL
        
        // Connect recording sink
        if let productionManager = productionManager {
            print("🎬 RecordingService: Production manager available, connecting recording sink...")
            await productionManager.connectRecordingSink(self.sink())
            print("🎬 RecordingService: Recording sink connected successfully")
        } else {
            print("🎬 RecordingService: CRITICAL ERROR - No production manager available")
            if needsSecurityScope {
                saveURL.stopAccessingSecurityScopedResource()
            }
            throw NSError(domain: "RecordingService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No production manager available"])
        }
        
        print("🎬 RecordingService: Starting ProgramRecorder with URL: \(saveURL.path)")
        print("🎬 RecordingService: Container: \(container)")
        
        do {
            try await recorder.start(url: saveURL, container: container)
            print("🎬 RecordingService: ProgramRecorder started successfully")
            
            self.isRecording = true
            self.startedAt = Date()
            startTickers()
            
            print("🎬 RecordingService: ====== RECORDING PIPELINE FULLY STARTED ======")
            print("🎬 RecordingService: Output file will be: \(saveURL.path)")
            print("🎬 RecordingService: Waiting for frames to be captured and processed...")
            
            // Schedule a check to verify frames are being received
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                let frameCount = await self.recorder.totalVideoFramesReceived
                let writtenCount = await self.recorder.totalVideoFramesWritten
                print("🎬 RecordingService: 5s check - Frames received: \(frameCount), written: \(writtenCount)")
                if frameCount == 0 {
                    print("🎬 RecordingService: WARNING - No frames received after 5 seconds!")
                }
                if writtenCount == 0 {
                    print("🎬 RecordingService: WARNING - No frames written after 5 seconds!")
                }
            }
            
        } catch {
            print("🎬 RecordingService: FAILED to start ProgramRecorder: \(error)")
            if needsSecurityScope {
                saveURL.stopAccessingSecurityScopedResource()
            }
            throw error
        }
    }
    
    func stopRecording() async -> URL? {
        guard isRecording else { return outputURL }
        
        print("🎬 RecordingService: ====== STOPPING RECORDING PIPELINE ======")
        stopTickers()
        
        do {
            let url = try await recorder.stopAndFinalize()
            self.isRecording = false
            self.outputURL = url
            
            print("🎬 RecordingService: Recording completed - reported file: \(url.path)")
            
            // Verify final file with detailed checks
            let fileManager = FileManager.default
            print("🎬 RecordingService: Checking file existence...")
            
            if fileManager.fileExists(atPath: url.path) {
                print("🎬 RecordingService: ✅ FILE EXISTS!")
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: url.path)
                    let fileSize = attributes[.size] as? Int64 ?? 0
                    let modificationDate = attributes[.modificationDate] as? Date
                    print("🎬 RecordingService: File size: \(fileSize) bytes")
                    print("🎬 RecordingService: Modified: \(modificationDate?.description ?? "unknown")")
                    
                    if fileSize == 0 {
                        print("🎬 RecordingService: ⚠️  WARNING - File is empty (0 bytes)")
                    }
                } catch {
                    print("🎬 RecordingService: ERROR getting file attributes: \(error)")
                }
            } else {
                print("🎬 RecordingService: ❌ FILE DOES NOT EXIST!")
                print("🎬 RecordingService: Checking parent directory...")
                let parentDir = url.deletingLastPathComponent()
                if fileManager.fileExists(atPath: parentDir.path) {
                    print("🎬 RecordingService: Parent directory exists: \(parentDir.path)")
                    do {
                        let contents = try fileManager.contentsOfDirectory(atPath: parentDir.path)
                        print("🎬 RecordingService: Directory contents: \(contents)")
                    } catch {
                        print("🎬 RecordingService: Cannot list directory contents: \(error)")
                    }
                } else {
                    print("🎬 RecordingService: Parent directory does not exist: \(parentDir.path)")
                }
            }
            
            // CRITICAL: Stop accessing security-scoped resource
            #if os(macOS)
            print("🎬 RecordingService: Stopping security-scoped resource access")
            url.stopAccessingSecurityScopedResource()
            #endif
            
            return url
        } catch {
            lastError = error.localizedDescription
            print("🎬 RecordingService: Recording failed: \(error)")
            self.isRecording = false
            
            // Still need to stop accessing the resource on error
            if let url = outputURL {
                #if os(macOS)
                url.stopAccessingSecurityScopedResource()
                #endif
            }
            
            return outputURL
        }
    }
    
    func updateAvailability(isProgramActive: Bool) {
        print("🎬 RecordingService: updateAvailability called with isProgramActive: \(isProgramActive)")
        print("🎬 RecordingService: Previous isRecordActionAvailable: \(isRecordActionAvailable)")
        isRecordActionAvailable = isProgramActive
        print("🎬 RecordingService: New isRecordActionAvailable: \(isRecordActionAvailable)")
    }
    
    func teardown() async {
        stopTickers()
        tap.stop()
        _ = try? await recorder.stopAndFinalize()
    }
    
    private func startTickers() {
        tickerTask?.cancel()
        diagTask?.cancel()
        
        tickerTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if let startedAt {
                    elapsed = Date().timeIntervalSince(startedAt)
                }
            }
        }
        
        diagTask = Task.detached(priority: .utility) { [recorder, weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let diag = await Diagnostics(
                    droppedVideo: recorder.droppedVideoFrames,
                    droppedAudio: recorder.droppedAudioFrames,
                    avgLatencyMs: recorder.averageWriteLatencyMs,
                    bitrateBps: recorder.estimatedBitrateBps
                )
                await MainActor.run {
                    self?.diagnostics = diag
                }
            }
        }
    }
    
    private func stopTickers() {
        tickerTask?.cancel()
        tickerTask = nil
        diagTask?.cancel()
        diagTask = nil
    }
    
    private func defaultFileName(container: ProgramRecorder.Container) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stamp = fmt.string(from: Date())
        return "Recording_\(stamp).\(container.fileExtension)"
    }
    
    private func primeFirstFrameIfNeeded() async {
        guard isRecording else { return }
        
        // Obtain current program texture size (MainActor-only UI object)
        let tuple: (Int, Int, Double) = await MainActor.run { [weak productionManager] () -> (Int, Int, Double) in
            guard let pm = productionManager else {
                return (1920, 1080, 30.0)
            }
            let tex = pm.previewProgramManager.programMetalTexture ?? pm.programCurrentTexture
            let width = tex?.width ?? 1920
            let height = tex?.height ?? 1080
            let fps = pm.previewProgramManager.targetFPS
            return (width, height, fps)
        }
        let (w, h, fps) = tuple
        
        let width = max(2, w)
        let height = max(2, h)
        let timescale = max(1, Int32(fps.rounded()))
        let pts = CMTime(value: 0, timescale: timescale)
        
        do {
            if let pb = createBlackBGRA(pixelWidth: width, pixelHeight: height) {
                print("🎬 RecordingService: Priming writer with black frame \(width)x\(height) @\(fps)fps")
                await recorder.appendVideoPixelBuffer(pb, presentationTime: pts)
            } else {
                print("🎬 RecordingService: Failed to create prime pixel buffer")
            }
        }
    }
    
    private func createBlackBGRA(pixelWidth: Int, pixelHeight: Int) -> CVPixelBuffer? {
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: pixelWidth,
            kCVPixelBufferHeightKey: pixelHeight,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: true
        ]
        var pb: CVPixelBuffer?
        let r = CVPixelBufferCreate(kCFAllocatorDefault, pixelWidth, pixelHeight, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
        guard r == kCVReturnSuccess, let buffer = pb else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            memset(base, 0, bytesPerRow * pixelHeight)
        }
        return buffer
    }
}

#if os(macOS)
import AppKit

@MainActor
func chooseOutputURL(defaultName: String, allowedTypes: [UTType]) async throws -> URL {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
        let panel = NSSavePanel()
        panel.title = "Save Recording"
        panel.prompt = "Start"
        panel.nameFieldStringValue = defaultName
        panel.canCreateDirectories = true
        panel.allowedContentTypes = allowedTypes
        panel.begin { response in
            if response == .OK, let url = panel.url {
                cont.resume(returning: url)
            } else {
                cont.resume(throwing: CancellationError())
            }
        }
    }
}
#endif