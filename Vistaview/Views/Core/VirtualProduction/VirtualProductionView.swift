import SwiftUI
import SceneKit
import AVFoundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct VirtualProductionView: View {
    @StateObject private var studioManager = VirtualStudioManager()
    @State private var selectedTool: StudioTool = .select
    @State private var selectedObject: StudioObject?
    @State private var showingAssetLibrary = false
    @State private var cameraMode: CameraMode = .overview
    
    var body: some View {
        HSplitView {
            // Left Panel - Tools & Assets
            VStack(spacing: 0) {
                // Tool Palette
                VStack(spacing: 0) {
                    Text("Studio Tools")
                        .font(.headline)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.1))
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        ForEach(StudioTool.allCases, id: \.self) { tool in
                            ToolButton(
                                tool: tool,
                                isSelected: selectedTool == tool,
                                action: { selectedTool = tool }
                            )
                        }
                    }
                    .padding()
                }
                
                Divider()
                
                // Asset Library
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        AssetCategoryView(
                            title: "LED Walls",
                            assets: LEDWallAsset.predefinedWalls,
                            onAdd: { asset in
                                studioManager.addLEDWall(from: asset)
                            }
                        )
                        
                        AssetCategoryView(
                            title: "Cameras",
                            assets: CameraAsset.predefinedCameras,
                            onAdd: { asset in
                                studioManager.addCamera(from: asset)
                            }
                        )
                        
                        AssetCategoryView(
                            title: "Set Pieces",
                            assets: SetPieceAsset.predefinedPieces,
                            onAdd: { asset in
                                studioManager.addSetPiece(from: asset)
                            }
                        )
                    }
                    .padding()
                }
            }
            .frame(minWidth: 300, maxWidth: 350)
            .background(Color.gray.opacity(0.05))
            
            // Center Panel - 3D Scene
            VStack(spacing: 0) {
                // Scene Controls
                HStack {
                    Text("Virtual Studio")
                        .font(.headline)
                    
                    Spacer()
                    
                    // Camera Mode Selector
                    Picker("View", selection: $cameraMode) {
                        Text("Overview").tag(CameraMode.overview)
                        Text("Camera 1").tag(CameraMode.camera1)
                        Text("Camera 2").tag(CameraMode.camera2)
                        Text("Camera 3").tag(CameraMode.camera3)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 200)
                    
                    Button(action: { studioManager.resetView() }) {
                        Image(systemName: "arrow.clockwise")
                        Text("Reset View")
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                
                // Main 3D Scene
                VirtualStudioSceneView(
                    studioManager: studioManager,
                    selectedTool: $selectedTool,
                    selectedObject: $selectedObject,
                    cameraMode: $cameraMode
                )
                .background(Color.black)
                
                // Timeline & Playback Controls
                TimelineControlView(studioManager: studioManager)
            }
            
            // Right Panel - Properties & Camera Feeds
            VStack(spacing: 0) {
                // Object Properties
                VStack(spacing: 0) {
                    HStack {
                        Text("Properties")
                            .font(.headline)
                        Spacer()
                        if selectedObject != nil {
                            Button("Delete") {
                                if let obj = selectedObject {
                                    studioManager.deleteObject(obj)
                                    selectedObject = nil
                                }
                            }
                            .foregroundColor(.red)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    
                    ScrollView {
                        if let object = selectedObject {
                            ObjectPropertiesView(object: object, studioManager: studioManager)
                        } else {
                            Text("Select an object to edit properties")
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                }
                .frame(maxHeight: 300)
                
                Divider()
                
                // Camera Feeds
                VStack(spacing: 0) {
                    HStack {
                        Text("Camera Feeds")
                            .font(.headline)
                        Spacer()
                        Button(action: { studioManager.addCamera() }) {
                            Image(systemName: "plus.circle")
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(studioManager.virtualCameras) { camera in
                                CameraFeedView(camera: camera, studioManager: studioManager)
                            }
                        }
                        .padding()
                    }
                }
            }
            .frame(minWidth: 300, maxWidth: 400)
            .background(Color.gray.opacity(0.05))
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Export Scene") {
                    studioManager.exportScene()
                }
                
                Button("Import Scene") {
                    studioManager.importScene()
                }
                
                Button("Render Preview") {
                    studioManager.renderPreview()
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct ToolButton: View {
    let tool: StudioTool
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tool.icon)
                    .font(.title2)
                Text(tool.name)
                    .font(.caption)
            }
            .foregroundColor(isSelected ? .white : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct AssetCategoryView<T: StudioAsset>: View {
    let title: String
    let assets: [T]
    let onAdd: (T) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 6) {
                ForEach(assets, id: \.id) { asset in
                    Button(action: { onAdd(asset) }) {
                        VStack(spacing: 4) {
                            Rectangle()
                                .fill(asset.color.opacity(0.3))
                                .frame(height: 40)
                                .overlay(
                                    Image(systemName: asset.icon)
                                        .foregroundColor(asset.color)
                                )
                                .cornerRadius(6)
                            
                            Text(asset.name)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
}

struct VirtualStudioSceneView: NSViewRepresentable {
    let studioManager: VirtualStudioManager
    @Binding var selectedTool: StudioTool
    @Binding var selectedObject: StudioObject?
    @Binding var cameraMode: CameraMode
    
    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = studioManager.scene
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        #if os(macOS)
        scnView.backgroundColor = NSColor.black
        #endif
        
        // Add gesture recognizers for object manipulation
        let clickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        scnView.addGestureRecognizer(clickGesture)
        
        return scnView
    }
    
    func updateNSView(_ nsView: SCNView, context: Context) {
        // Update camera based on mode
        switch cameraMode {
        case .overview:
            nsView.allowsCameraControl = true
        case .camera1, .camera2, .camera3:
            nsView.allowsCameraControl = false
            // Set to specific camera view
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: VirtualStudioSceneView
        
        init(_ parent: VirtualStudioSceneView) {
            self.parent = parent
        }
        
        @MainActor
        @objc func handleClick(_ gestureRecognizer: NSClickGestureRecognizer) {
            let scnView = gestureRecognizer.view as! SCNView
            let location = gestureRecognizer.location(in: scnView)
            
            let hitResults = scnView.hitTest(location, options: [:])
            
            Task { @MainActor in
                if let hitResult = hitResults.first {
                    // Handle object selection
                    if let studioObject = parent.studioManager.getObject(from: hitResult.node) {
                        parent.selectedObject = studioObject
                    }
                } else if parent.selectedTool != .select {
                    // Add new object at clicked location
                    parent.studioManager.addObject(
                        type: parent.selectedTool,
                        at: parent.studioManager.worldPosition(from: location, in: scnView)
                    )
                }
            }
        }
    }
}

struct ObjectPropertiesView: View {
    let object: StudioObject
    let studioManager: VirtualStudioManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Basic Properties
            Group {
                Text("Transform")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                VStack(spacing: 8) {
                    HStack {
                        Text("Position")
                        Spacer()
                        VStack(spacing: 2) {
                            HStack {
                                Text("X:"); TextField("0", value: .constant(object.position.x), format: .number)
                                Text("Y:"); TextField("0", value: .constant(object.position.y), format: .number)
                                Text("Z:"); TextField("0", value: .constant(object.position.z), format: .number)
                            }
                        }
                    }
                    
                    HStack {
                        Text("Rotation")
                        Spacer()
                        VStack(spacing: 2) {
                            HStack {
                                Text("X:"); TextField("0", value: .constant(object.rotation.x), format: .number)
                                Text("Y:"); TextField("0", value: .constant(object.rotation.y), format: .number)
                                Text("Z:"); TextField("0", value: .constant(object.rotation.z), format: .number)
                            }
                        }
                    }
                    
                    HStack {
                        Text("Scale")
                        Spacer()
                        VStack(spacing: 2) {
                            HStack {
                                Text("X:"); TextField("1", value: .constant(object.scale.x), format: .number)
                                Text("Y:"); TextField("1", value: .constant(object.scale.y), format: .number)
                                Text("Z:"); TextField("1", value: .constant(object.scale.z), format: .number)
                            }
                        }
                    }
                }
                .font(.caption)
            }
            
            Divider()
            
            // Object-specific properties
            switch object.type {
            case .ledWall:
                LEDWallPropertiesView(object: object, studioManager: studioManager)
            case .camera:
                CameraPropertiesView(object: object, studioManager: studioManager)
            case .setPiece:
                SetPiecePropertiesView(object: object, studioManager: studioManager)
            case .light:
                LightPropertiesView(object: object, studioManager: studioManager)
            }
        }
        .padding()
    }
}

struct CameraFeedView: View {
    let camera: VirtualCamera
    let studioManager: VirtualStudioManager
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(camera.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { studioManager.selectCamera(camera) }) {
                    Image(systemName: "viewfinder")
                }
            }
            
            Rectangle()
                .fill(Color.black)
                .aspectRatio(16/9, contentMode: .fit)
                .overlay(
                    Text("Camera \(camera.id)")
                        .foregroundColor(.white)
                        .font(.caption)
                )
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(camera.isActive ? Color.red : Color.gray, lineWidth: 2)
                )
        }
    }
}

struct TimelineControlView: View {
    let studioManager: VirtualStudioManager
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    
    var body: some View {
        HStack {
            Button(action: { isPlaying.toggle() }) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            }
            
            Button(action: { currentTime = 0 }) {
                Image(systemName: "backward.end.fill")
            }
            
            Slider(value: $currentTime, in: 0...100)
            
            Text("00:00 / 05:00")
                .font(.caption)
                .monospaced()
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }
}

struct LightPropertiesView: View {
    let object: StudioObject
    let studioManager: VirtualStudioManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Light Settings")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            HStack {
                Text("Type:")
                Spacer()
                Picker("Type", selection: .constant("Spot")) {
                    Text("Directional").tag("Directional")
                    Text("Spot").tag("Spot")
                    Text("Point").tag("Point")
                }
                .frame(width: 100)
            }
            
            HStack {
                Text("Intensity:")
                Spacer()
                Slider(value: .constant(1.0), in: 0...2)
                    .frame(width: 100)
            }
            
            HStack {
                Text("Color:")
                Spacer()
                ColorPicker("", selection: .constant(Color.white))
                    .frame(width: 50)
            }
        }
        .font(.caption)
    }
}

// MARK: - Placeholder Property Views

struct LEDWallPropertiesView: View {
    let object: StudioObject
    let studioManager: VirtualStudioManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LED Wall Settings")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            HStack {
                Text("Resolution:")
                Spacer()
                Text("1920x1080")
            }
            
            HStack {
                Text("Pixel Pitch:")
                Spacer()
                TextField("2.6", value: .constant(2.6), format: .number)
                    .frame(width: 60)
                Text("mm")
            }
            
            HStack {
                Text("Brightness:")
                Spacer()
                Slider(value: .constant(0.8), in: 0...1)
                    .frame(width: 100)
            }
        }
        .font(.caption)
    }
}

struct CameraPropertiesView: View {
    let object: StudioObject
    let studioManager: VirtualStudioManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Camera Settings")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            HStack {
                Text("Lens:")
                Spacer()
                TextField("24", value: .constant(24), format: .number)
                    .frame(width: 60)
                Text("mm")
            }
            
            HStack {
                Text("Active:")
                Spacer()
                Toggle("", isOn: .constant(true))
            }
        }
        .font(.caption)
    }
}

struct SetPiecePropertiesView: View {
    let object: StudioObject
    let studioManager: VirtualStudioManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set Piece Settings")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            HStack {
                Text("Material:")
                Spacer()
                Picker("Material", selection: .constant("Wood")) {
                    Text("Wood").tag("Wood")
                    Text("Metal").tag("Metal")
                    Text("Fabric").tag("Fabric")
                }
                .frame(width: 100)
            }
        }
        .font(.caption)
    }
}

// MARK: - Data Models & Enums

enum StudioTool: CaseIterable {
    case select, ledWall, camera, setPiece, light
    
    var name: String {
        switch self {
        case .select: return "Select"
        case .ledWall: return "LED Wall"
        case .camera: return "Camera"
        case .setPiece: return "Set Piece"
        case .light: return "Light"
        }
    }
    
    var icon: String {
        switch self {
        case .select: return "cursorarrow"
        case .ledWall: return "tv"
        case .camera: return "video"
        case .setPiece: return "cube.box"
        case .light: return "lightbulb"
        }
    }
}

enum CameraMode {
    case overview, camera1, camera2, camera3
}

protocol StudioAsset {
    var id: UUID { get }
    var name: String { get }
    var icon: String { get }
    var color: Color { get }
}
