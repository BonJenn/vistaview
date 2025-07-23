import SwiftUI
import SceneKit

struct VirtualCameraDemoView: View {
    @StateObject private var studioManager = VirtualStudioManager()
    @State private var selectedCameraID: UUID?
    
    private let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.maximumFractionDigits = 2
        return f
    }()
    
    private var selectedCamera: VirtualCamera? {
        studioManager.virtualCameras.first { $0.id == selectedCameraID }
    }
    
    var body: some View {
        HStack {
            // Camera list
            VStack(alignment: .leading, spacing: 8) {
                Text("Virtual Cameras").font(.headline)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(studioManager.virtualCameras) { cam in
                            Button {
                                selectedCameraID = cam.id
                            } label: {
                                HStack {
                                    Text(cam.name)
                                    Spacer()
                                    if cam.isActive {
                                        Image(systemName: "dot.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                }
                                .padding(6)
                                .frame(maxWidth: .infinity)
                                .background(cam.id == selectedCameraID ? Color.blue.opacity(0.2) : Color.clear)
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .frame(width: 220, height: 280)
                
                Button("Add Test Camera") {
                    let index = studioManager.virtualCameras.count
                    let new = VirtualCamera(
                        name: "Camera \(index + 1)",
                        position: SCNVector3(0, 2, 6 + CGFloat(index) * 2)
                    )
                    studioManager.virtualCameras.append(new)
                    studioManager.scene.rootNode.addChildNode(new.node)
                }
                
                Spacer()
            }
            .padding()
            
            Divider()
            
            // Camera transform controls
            VStack(alignment: .leading, spacing: 16) {
                if let cam = selectedCamera {
                    Text("Selected: \(cam.name)").font(.headline)
                    
                    HStack(spacing: 12) {
                        coordField(label: "X", value: cam.node.position.x) { cam.node.position.x = $0 }
                        coordField(label: "Y", value: cam.node.position.y) { cam.node.position.y = $0 }
                        coordField(label: "Z", value: cam.node.position.z) { cam.node.position.z = $0 }
                    }
                    
                    Button("Set Active") {
                        studioManager.virtualCameras.forEach { $0.isActive = false }
                        cam.isActive = true
                    }
                } else {
                    Text("Select a camera from the list.")
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 400)
    }
    
    // Helper for numeric textfields (CGFloat-aware)
    private func coordField(label: String, value: CGFloat, onChange: @escaping (CGFloat)->Void) -> some View {
        HStack {
            Text(label)
            TextField(label,
                      value: Binding(
                        get: { Double(value) },
                        set: { onChange(CGFloat($0)) }),
                      formatter: numberFormatter)
                .frame(width: 70)
        }
    }
}
