import Foundation
import Combine

@MainActor
class RecordingManager: ObservableObject {
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var outputURL: URL?
    @Published private(set) var lastError: String?
    @Published private(set) var isEnabledByLicense: Bool = true
    @Published private(set) var isRecordActionAvailable: Bool = false

    private let service: RecordingService
    private var cancellables = Set<AnyCancellable>()

    init(service: RecordingService = AppServices.shared.recordingService) {
        self.service = service

        service.$isRecording
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRecording)

        service.$elapsed
            .receive(on: DispatchQueue.main)
            .assign(to: &$elapsed)

        service.$outputURL
            .receive(on: DispatchQueue.main)
            .assign(to: &$outputURL)

        service.$lastError
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastError)

        service.$isEnabledByLicense
            .receive(on: DispatchQueue.main)
            .assign(to: &$isEnabledByLicense)

        service.$isRecordActionAvailable
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRecordActionAvailable)
    }

    func startRecording() {
        service.startOrStop()
    }
    
    func stopRecording() {
        service.startOrStop()
    }
    
    func updateAvailability(isProgramActive: Bool) {
        service.updateAvailability(isProgramActive: isProgramActive)
    }
}