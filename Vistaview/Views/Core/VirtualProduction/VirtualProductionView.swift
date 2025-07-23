//
//  VirtualProductionView.swift
//  Vistaview
//

import SwiftUI
import SceneKit

struct VirtualProductionView: View {
    @EnvironmentObject var studioManager: VirtualStudioManager
    
    @State private var selectedTool: StudioTool = .select
    @State private var selectedObject: StudioObject?
    @State private var cameraMode: CameraMode = .orbit
    @State private var lastWorldPos: SCNVector3 = SCNVector3(0,0,0)
    
    var body: some View {
        HStack(spacing: 0) {
            leftSidebar
            centerScene
            rightSidebar
        }
        .onChange(of: selectedTool) { _, newValue in
            // handle tool change if needed
            if newValue == .select { selectedObject = nil }
        }
    }
    
    // MARK: - Left
    private var leftSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tools").font(.headline)
            ToolButton(icon: "cursorarrow", label: "Select", tool: .select, current: $selectedTool)
            ToolButton(icon: "display", label: "LED Wall", tool: .ledWall, current: $selectedTool)
            ToolButton(icon: "video", label: "Camera", tool: .camera, current: $selectedTool)
            ToolButton(icon: "cube", label: "Set Piece", tool: .setPiece, current: $selectedTool)
            ToolButton(icon: "lightbulb", label: "Light", tool: .light, current: $selectedTool)
            
            Divider().padding(.vertical, 8)
            
            Text("Cameras").font(.headline)
            List(studioManager.virtualCameras, id: \.id, selection: selectedCameraBinding) { cam in
                Text(cam.name)
                    .onTapGesture {
                        studioManager.selectCamera(cam)
                    }
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 220)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Camera Binding
    private var selectedCameraBinding: Binding<VirtualCamera.ID?> {
        Binding<VirtualCamera.ID?>(
            get: { studioManager.selectedCamera?.id },
            set: { id in
                guard let id,
                      let cam = studioManager.virtualCameras.first(where: { $0.id == id }) else { return }
                studioManager.selectCamera(cam)
            }
        )
    }
    
    // MARK: - Center
    private var centerScene: some View {
        VirtualStudioSceneView(
            studioManager: studioManager,
            selectedTool: $selectedTool,
            selectedObject: $selectedObject,
            cameraMode: $cameraMode,
            lastWorldPos: $lastWorldPos
        )
        .background(Color.black)
    }
    
    // MARK: - Right
    private var rightSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Properties").font(.headline)
            if let obj = selectedObject {
                ObjectPropertiesView(object: obj)
            } else {
                Text("No selection").foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .frame(width: 260)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - SceneKit Representable

#if os(macOS)
typealias PlatformViewRepresentable = NSViewRepresentable
#else
typealias PlatformViewRepresentable = UIViewRepresentable
#endif

struct VirtualStudioSceneView: PlatformViewRepresentable {
    let studioManager: VirtualStudioManager
    @Binding var selectedTool: StudioTool
    @Binding var selectedObject: StudioObject?
    @Binding var cameraMode: CameraMode
    @Binding var lastWorldPos: SCNVector3
    
    func makeNSView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = studioManager.scene
        v.allowsCameraControl = (cameraMode == .orbit)
        v.backgroundColor = .black
        v.delegate = context.coordinator
        
        let clickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        v.addGestureRecognizer(clickGesture)
        
        return v
    }
    
    func updateNSView(_ nsView: SCNView, context: Context) {
        nsView.allowsCameraControl = (cameraMode == .orbit)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self, studioManager: studioManager)
    }
    
    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        let parent: VirtualStudioSceneView
        let studioManager: VirtualStudioManager
        
        init(_ parent: VirtualStudioSceneView, studioManager: VirtualStudioManager) {
            self.parent = parent
            self.studioManager = studioManager
        }
        
        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let pt = gesture.location(in: view)
            
            Task { @MainActor in
                switch self.parent.selectedTool {
                case .select:
                    let hits = view.hitTest(pt, options: nil)
                    if let hit = hits.first {
                        let node = hit.node
                        if let obj = self.studioManager.getObject(from: node) {
                            self.parent.selectedObject = obj
                            return
                        }
                    }
                    self.parent.selectedObject = nil
                default:
                    // Place object
                    let world = self.studioManager.worldPosition(from: pt, in: view)
                    self.parent.lastWorldPos = world
                    self.studioManager.addObject(type: self.parent.selectedTool, at: world)
                }
            }
        }
    }
}

#if !os(macOS)
// iOS version would go here if needed
struct VirtualStudioSceneView: UIViewRepresentable {
    // iOS implementation would be similar but using UIViewRepresentable
    func makeUIView(context: Context) -> SCNView { SCNView() }
    func updateUIView(_ uiView: SCNView, context: Context) {}
}
#endif

// MARK: - Supporting Views

struct ToolButton: View {
    let icon: String
    let label: String
    let tool: StudioTool
    @Binding var current: StudioTool
    
    var body: some View {
        Button {
            current = tool
        } label: {
            HStack {
                Image(systemName: icon)
                Text(label)
            }
        }
        .buttonStyle(.bordered)
        .tint(current == tool ? .accentColor : .gray)
    }
}

// Placeholder detail views – keep whatever you already had.
struct LEDWallProperties: View {
    @ObservedObject var object: StudioObject
    let studioManager: VirtualStudioManager
    var body: some View { Text("LED Wall Props for \(object.name)") }
}
struct CameraProperties: View {
    @ObservedObject var object: StudioObject
    let studioManager: VirtualStudioManager
    var body: some View { Text("Camera Props for \(object.name)") }
}
struct SetPieceProperties: View {
    @ObservedObject var object: StudioObject
    let studioManager: VirtualStudioManager
    var body: some View { Text("Set Piece Props for \(object.name)") }
}
struct LightProperties: View {
    @ObservedObject var object: StudioObject
    let studioManager: VirtualStudioManager
    var body: some View { Text("Light Props for \(object.name)") }
}

// MARK: - Simple enums you already have
enum CameraMode: String, CaseIterable, Hashable {
    case orbit, pan, fly
}