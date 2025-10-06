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
    private var stopInProgress = false
    private var startInProgress = false
    
    func sink() -> RecordingSink { tap }
    
    func setProductionManager(_ manager: UnifiedProductionManager) {
        self.productionManager = manager
    }
    
    func startOrStop(container: ProgramRecorder.Container = .mov) {
        print("🎬 RecordingService: startOrStop() called")
        print("🎬 RecordingService: Current state - isRecording: \(isRecording)")
        
        if isRecording {
            guard !stopInProgress else {
                print("🎬 RecordingService: Stop already in progress; ignoring tap")
                return
            }
            stopInProgress = true
            print("🎬 RecordingService: Stopping recording...")
            Task {
                defer { self.stopInProgress = false }
                _ = await stopRecording()
            }
        } else {
            guard !startInProgress else {
                print("🎬 RecordingService: Start already in progress; ignoring tap")
                return
            }
            startInProgress = true
            print("🎬 RecordingService: Starting recording...")
            Task {
                defer { self.startInProgress = false }
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
            
            let hasAccess = saveURL.startAccessingSecurityScopedResource()
            print("🎬 RecordingService: Security-scoped resource access: \(hasAccess)")
        } catch {
            print("🎬 RecordingService: User cancelled file selection or error: \(error)")
            throw CancellationError()
        }
        #else
        saveURL = FileManager.default.temporaryDirectory.appendingPathComponent(defaultName)
        print("🎬 RecordingService: Using temp URL: \(saveURL.path)")
        #endif
        
        // Store the URL immediately so ProgramRecorder can create the writer
        self.outputURL = saveURL
        
        // IMPORTANT: Start the ProgramRecorder BEFORE connecting the sink.
        // Otherwise the ProgramRecorder has no outputURL when the program pipeline begins pushing frames,
        // leading to missingURL/startSession failures and zero-frame files.
        print("🎬 RecordingService: Starting ProgramRecorder FIRST (before connecting sink)")
        do {
            try await recorder.start(url: saveURL, container: container)
            print("🎬 RecordingService: ProgramRecorder started successfully")
        } catch {
            print("🎬 RecordingService: FAILED to start ProgramRecorder: \(error)")
            if needsSecurityScope {
                saveURL.stopAccessingSecurityScopedResource()
            }
            throw error
        }
        
        // Now connect the sink and start feeding frames (or mark media-segment begin)
        if let productionManager = productionManager {
            print("🎬 RecordingService: Connecting recording sink to production manager…")
            await productionManager.connectRecordingSink(self.sink())
            print("🎬 RecordingService: Recording sink connected successfully")
        } else {
            print("🎬 RecordingService: CRITICAL ERROR - No production manager available")
            if needsSecurityScope {
                saveURL.stopAccessingSecurityScopedResource()
            }
            throw NSError(domain: "RecordingService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No production manager available"])
        }
        
        self.isRecording = true
        self.startedAt = Date()
        startTickers()
        
        print("🎬 RecordingService: ====== RECORDING PIPELINE FULLY STARTED ======")
        print("🎬 RecordingService: Output file will be: \(saveURL.path)")
        
        // Optional 5s health check
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            let frameCount = await self.recorder.totalVideoFramesReceived
            let writtenCount = await self.recorder.totalVideoFramesWritten
            print("🎬 RecordingService: 5s check - Frames received: \(frameCount), written: \(writtenCount)")
            if frameCount == 0 { print("🎬 RecordingService: WARNING - No frames received after 5 seconds!") }
            if writtenCount == 0 { print("🎬 RecordingService: WARNING - No frames written after 5 seconds!") }
        }
    }
    
    func stopRecording() async -> URL? {
        guard isRecording else { return outputURL }
        
        print("🎬 RecordingService: ====== STOPPING RECORDING PIPELINE ======")
        stopTickers()

        // For media program, pause player and export exact segment [start..now] before disconnect/finalize
        if let pm = productionManager {
            print("🎬 RecordingService: Asking production manager to pause media (if any) and export segment…")
            await pm.pauseProgramMediaIfAny()
            await pm.exportCurrentMediaSegmentIfNeeded(to: recorder)
            print("🎬 RecordingService: Media segment export complete (if any)")
        }
        
        // Now cut producers to avoid new frames while we finalize
        if let pm = productionManager {
            print("🎬 RecordingService: Requesting production manager to disconnect recording sink…")
            await pm.disconnectRecordingSink()
            print("🎬 RecordingService: Production manager disconnected recording sink")
        }
        
        do {
            let url = try await recorder.stopAndFinalize()
            self.isRecording = false
            self.outputURL = url
            
            print("🎬 RecordingService: Recording completed - reported file: \(url.path)")
            
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
            
            #if os(macOS)
            print("🎬 RecordingService: Stopping security-scoped resource access")
            url.stopAccessingSecurityScopedResource()
            #endif
            
            return url
        } catch {
            lastError = error.localizedDescription
            print("🎬 RecordingService: Recording failed: \(error)")
            self.isRecording = false
            
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