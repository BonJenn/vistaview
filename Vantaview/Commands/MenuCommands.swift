import SwiftUI

struct RecordingMenuCommands: Commands {
    @ObservedObject var recordingService: RecordingService

    init(recordingService: RecordingService = AppServices.shared.recordingService) {
        self._recordingService = ObservedObject(wrappedValue: recordingService)
    }

    var body: some Commands {
        CommandMenu("Recording") {
            Button(recordingService.isRecording ? "Stop Recording" : "Start Recording") {
                recordingService.startOrStop()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(!(recordingService.isEnabledByLicense && recordingService.isRecordActionAvailable))
        }
    }
}