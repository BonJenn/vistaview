import Foundation

@MainActor
class RecordingManager: ObservableObject {
    func startRecording() {
        print("⏺️ Recording started")
    }
    
    func stopRecording() {
        print("⏹️ Recording stopped")
    }
}
