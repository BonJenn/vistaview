import SwiftUI

struct SettingsView: View {
    @AppStorage("rtmpURL") private var rtmpURL = "rtmp://127.0.0.1:1935/stream"
    @AppStorage("streamKey") private var streamKey = "test"

    var body: some View {
        Form {
            Section("Streaming Configuration") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("RTMP URL:")
                            .frame(width: 80, alignment: .trailing)
                        TextField("rtmp://…", text: $rtmpURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    HStack {
                        Text("Stream Key:")
                            .frame(width: 80, alignment: .trailing)
                        SecureField("yourStreamName", text: $streamKey)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 200)
    }
}
