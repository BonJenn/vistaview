// File: Views/Core/SettingsView.swift
import SwiftUI

/// Preferences for configuring RTMP URL and stream key.
struct SettingsView: View {
    @AppStorage("rtmpURL") private var rtmpURL: String = "rtmp://127.0.0.1:1935/live"
    @AppStorage("streamKey") private var streamKey: String = ""

    var body: some View {
        Form {
            Section(header: Text("RTMP Configuration")) {
                TextField("RTMP URL", text: $rtmpURL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: rtmpURL) { new in
                        rtmpURL = new.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                TextField("Stream Key", text: $streamKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: streamKey) { new in
                        streamKey = new.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
            }

            Section(header: Text("Connection Info")) {
                Text("Full Endpoint: \(rtmpURL)/\(streamKey)")
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

