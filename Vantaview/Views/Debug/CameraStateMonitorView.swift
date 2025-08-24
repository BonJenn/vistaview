//
//  CameraStateMonitorView.swift
//  Vantaview
//
//  Created by AI Assistant
//

import SwiftUI

struct CameraStateMonitorView: View {
    @ObservedObject var cameraFeedManager: CameraFeedManager
    @State private var isMonitoring = false
    @State private var stateHistory: [String] = []
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Camera State Monitor")
                .font(.title2)
                .padding()
            
            HStack(spacing: 16) {
                Button(isMonitoring ? "Stop Monitor" : "Start Monitor") {
                    isMonitoring.toggle()
                }
                .foregroundColor(isMonitoring ? .red : .green)
                
                Button("Clear History") {
                    stateHistory.removeAll()
                }
                
                Button("Export Log") {
                    exportLog()
                }
            }
            
            // Current state
            GroupBox("Current State") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Available Devices: \(cameraFeedManager.availableDevices.count)")
                    Text("Active Feeds: \(cameraFeedManager.activeFeeds.count)")
                    
                    if let selected = cameraFeedManager.selectedFeedForLiveProduction {
                        Text("Selected: \(selected.device.displayName)")
                            .foregroundColor(.green)
                        Text("Status: \(selected.connectionStatus.displayText)")
                            .foregroundColor(selected.connectionStatus.color)
                        Text("Frame Count: \(selected.frameCount)")
                        Text("Has Preview: \(selected.previewImage != nil ? "Yes" : "No")")
                    } else {
                        Text("No feed selected")
                            .foregroundColor(.orange)
                    }
                }
            }
            
            // State history
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(stateHistory.enumerated()), id: \.offset) { index, entry in
                        Text(entry)
                            .font(.caption)
                            .foregroundColor(colorForEntry(entry))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .background(Color.black.opacity(0.8))
            .cornerRadius(8)
        }
        .padding()
        .frame(width: 600, height: 500)
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            if isMonitoring {
                logCurrentState()
            }
        }
    }
    
    private func logCurrentState() {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        
        // Log overall state
        var entry = "[\(timestamp)] Devices: \(cameraFeedManager.availableDevices.count), Active: \(cameraFeedManager.activeFeeds.count)"
        
        if let selected = cameraFeedManager.selectedFeedForLiveProduction {
            entry += ", Selected: \(selected.device.displayName) (\(selected.connectionStatus.displayText), frames: \(selected.frameCount), preview: \(selected.previewImage != nil))"
        }
        
        stateHistory.append(entry)
        
        // Log changes for each feed
        for feed in cameraFeedManager.activeFeeds {
            if feed.frameCount > 0 || feed.connectionStatus != .connected {
                let feedEntry = "[\(timestamp)] \(feed.device.displayName): \(feed.connectionStatus.displayText), frames: \(feed.frameCount)"
                stateHistory.append(feedEntry)
            }
        }
        
        // Keep only last 100 entries
        if stateHistory.count > 100 {
            stateHistory.removeFirst(stateHistory.count - 100)
        }
    }
    
    private func colorForEntry(_ entry: String) -> Color {
        if entry.contains("Error") || entry.contains("Failed") {
            return .red
        } else if entry.contains("Connected") || entry.contains("frames:") {
            return .green
        } else if entry.contains("Connecting") {
            return .orange
        } else {
            return .primary
        }
    }
    
    private func exportLog() {
        let logContent = stateHistory.joined(separator: "\n")
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "camera_state_log.txt"
        panel.allowedContentTypes = [.plainText]
        
        panel.begin { result in
            if result == .OK, let url = panel.url {
                try? logContent.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

#Preview {
    let deviceManager = CameraDeviceManager()
    let feedManager = CameraFeedManager(cameraDeviceManager: deviceManager)
    
    return CameraStateMonitorView(cameraFeedManager: feedManager)
}