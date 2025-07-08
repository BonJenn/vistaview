//
//  ContentView.swift
//  Vistaview
//

import SwiftUI

struct ContentView: View {
    @StateObject private var streamer = Streamer()
    @State private var rtmpURL: String = "rtmp://127.0.0.1:1935/stream"
    @State private var streamKey: String = "test"
    @State private var showSettings = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Placeholder for your video renderer
                Rectangle()
                    .fill(Color.black)
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay(Text("Video Preview").foregroundColor(.white))

                // MARK: –– Streaming Controls ––
                VStack(spacing: 10) {
                    HStack {
                        TextField("RTMP URL", text: $rtmpURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button("Settings") {
                            showSettings.toggle()
                        }
                        .sheet(isPresented: $showSettings) {
                            SettingsView(rtmpURL: $rtmpURL, streamKey: $streamKey)
                        }
                    }

                    TextField("Stream Key", text: $streamKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    HStack(spacing: 30) {
                        Button {
                            streamer.startStreaming(to: rtmpURL.trimmingCharacters(in: .whitespacesAndNewlines),
                                                   streamName: streamKey.trimmingCharacters(in: .whitespacesAndNewlines))
                        } label: {
                            Label("Go Live", systemImage: "antenna.radiowaves.left.and.right")
                                .frame(minWidth: 100)
                        }
                        .disabled(streamer.isStreaming)

                        Button {
                            streamer.stopStreaming()
                        } label: {
                            Label("Stop", systemImage: "stop.circle")
                                .frame(minWidth: 100)
                        }
                        .disabled(!streamer.isStreaming)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)

                Spacer()
            }
            .navigationTitle("Vistaview")
        }
    }
}

struct SettingsView: View {
    @Binding var rtmpURL: String
    @Binding var streamKey: String

    var body: some View {
        Form {
            Section(header: Text("Streaming Endpoint")) {
                TextField("RTMP URL", text: $rtmpURL)
                TextField("Stream Key", text: $streamKey)
            }
        }
        .frame(width: 400, height: 200)
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
