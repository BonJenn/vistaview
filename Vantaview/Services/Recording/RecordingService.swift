import Foundation
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

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
        if isRecording {
            Task {
                _ = await stopRecording()
            }
        } else {
            Task {
                do {
                    try await startRecording(container: container)
                } catch {
                    lastError = error.localizedDescription
                }
            }
        }
    }
    
    func startRecording(container: ProgramRecorder.Container = .mov) async throws {
        guard isEnabledByLicense else {
            lastError = "Recording requires a higher license tier."
            return
        }
        guard isRecordActionAvailable else {
            lastError = "Program output is not active."
            return
        }
        
        print("🎬 RecordingService: Starting recording...")
        
        if let productionManager = productionManager {
            print("🎬 RecordingService: Reconnecting recording sink to production manager")
            await productionManager.connectRecordingSink(self.sink())
        } else {
            print("🎬 RecordingService: ERROR - No production manager available")
            throw NSError(domain: "RecordingService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No production manager available"])
        }
        
        let defaultName = defaultFileName(container: container)
        #if os(macOS)
        let saveURL = try await chooseOutputURL(defaultName: defaultName, allowedTypes: [container.utType])
        #else
        let saveURL = FileManager.default.temporaryDirectory.appendingPathComponent(defaultName)
        #endif
        
        print("🎬 RecordingService: Recording to URL: \(saveURL)")
        
        try await recorder.start(url: saveURL, container: container)
        self.outputURL = saveURL
        self.isRecording = true
        self.startedAt = Date()
        startTickers()
        
        print("🎬 RecordingService: Recording started successfully")
    }
    
    func stopRecording() async -> URL? {
        guard isRecording else { return outputURL }
        stopTickers()
        
        if let productionManager = productionManager {
            print("🎬 RecordingService: Disconnecting recording sink")
            await productionManager.disconnectRecordingSink()
        }
        
        do {
            let url = try await recorder.stopAndFinalize()
            self.isRecording = false
            self.outputURL = url
            return url
        } catch {
            lastError = error.localizedDescription
            self.isRecording = false
            return outputURL
        }
    }
    
    func updateAvailability(isProgramActive: Bool) {
        isRecordActionAvailable = isProgramActive
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