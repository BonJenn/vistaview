// File: Views/Core/Streamer.swift
import Foundation
import AVFoundation
import AppKit
import HaishinKit

/// A minimal async RTMP handshake tester using HaishinKit.
/// Connects, publishes, and closes the RTMP stream without media attachments.
final class Streamer: ObservableObject {
    @Published var isStreaming: Bool = false

    private var streamURL: String
    private var streamName: String
    private let rtmpConnection: RTMPConnection
    private let rtmpStream: RTMPStream

    /// Initialize with an RTMP endpoint and stream key.
    init(streamURL: String = "", streamName: String = "") {
        self.streamURL = streamURL
        self.streamName = streamName
        self.rtmpConnection = RTMPConnection()
        self.rtmpStream = RTMPStream(connection: rtmpConnection)
    }

    /// Reconfigure the RTMP endpoint and key.
    func configure(streamURL: String, streamName: String) {
        self.streamURL = streamURL
        self.streamName = streamName
    }

    /// Performs the RTMP handshake asynchronously.
    func startStreaming(playerItem: AVPlayerItem, on view: NSView) {
        guard !isStreaming else { return }
        isStreaming = true
        Task { @MainActor in
            do {
                try await rtmpConnection.connect(streamURL)
                try await rtmpStream.publish(streamName)
                print("[Streamer] Handshake success: connected to \(streamURL)/\(streamName)")
            } catch {
                print("[Streamer] startStreaming error: \(error)")
                isStreaming = false
            }
        }
    }

    /// Closes the RTMP connection asynchronously.
    func stopStreaming() {
        guard isStreaming else { return }
        isStreaming = false
        Task { @MainActor in
            do {
                try await rtmpStream.close()
                try await rtmpConnection.close()
                print("[Streamer] Connection closed")
            } catch {
                print("[Streamer] stopStreaming error: \(error)")
            }
        }
    }
}

