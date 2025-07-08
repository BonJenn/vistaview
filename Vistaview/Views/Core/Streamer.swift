//
//  Streamer.swift
//  Vistaview
//

import SwiftUI
import HaishinKit
import AVFoundation

@MainActor
class Streamer: ObservableObject {
    @Published var isStreaming = false

    private let connection = RTMPConnection()
    private let stream: RTMPStream

    init() {
        // Create the stream bound to our connection
        stream = RTMPStream(connection: connection)
    }

    /// Starts the RTMP handshake and begins publishing.
    /// - Parameters:
    ///   - rtmpURL: Full RTMP URL (e.g. "rtmp://127.0.0.1:1935/stream")
    ///   - streamName: Your stream key or name (e.g. "test")
    func startStreaming(to rtmpURL: String, streamName: String) {
        do {
            // Synchronous API calls (HaishinKit 2.x)
            try connection.connect(rtmpURL)
            try stream.publish(streamName)

            isStreaming = true
            print("✅ Streaming started to \(rtmpURL)/\(streamName)")
        } catch {
            print("❌ Failed to start streaming:", error)
        }
    }

    /// Stops publishing and tears down the RTMP connection.
    func stopStreaming() {
        // Close the stream
        stream.close()
        // Close the connection
        connection.close()

        isStreaming = false
        print("🛑 Streaming stopped")
    }
}
