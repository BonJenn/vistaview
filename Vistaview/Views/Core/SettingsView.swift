// =========================
// File: Views/Core/SettingsView.swift
// =========================
import SwiftUI

/// Preferences for configuring RTMP URL and stream key.
struct SettingsView: View {
    @AppStorage("rtmpURL") private var rtmpURL: String = "rtmp://127.0.0.1:1935/stream"
    @AppStorage("streamKey") private var streamKey: String = "test"

    var body: some View {
        Form {
            Section(header: Text("RTMP Configuration")) {
                TextField("RTMP URL", text: $rtmpURL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                TextField("Stream Key", text: $streamKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            Section(header: Text("Connection Info")) {
                Text("Endpoint: \(rtmpURL)/\(streamKey)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 400)
        .navigationTitle("Preferences")
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
