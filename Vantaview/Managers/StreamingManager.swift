import Foundation

@MainActor
class StreamingManager: ObservableObject {
    func startStreaming() {
        print("🎬 Streaming started")
    }
    
    func stopStreaming() {
        print("🛑 Streaming stopped")
    }
}
