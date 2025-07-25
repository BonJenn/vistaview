import SwiftUI
import SceneKit

struct VirtualProductionView: View {
    @EnvironmentObject var studioManager: VirtualStudioManager
    
    // Core States
    @State private var selectedTool: StudioTool = .select
    @State private var selectedObject: StudioObject?
    @State private var cameraMode: CameraMode = .orbit
    @State private var lastWorldPos: SCNVector3 = SCNVector3(0,0,0)
    
    // Raycast-inspired UI States
    @State private var showingCommandPalette = false
    @State private var showingLeftPanel = true
    @State private var showingRightPanel = true
    @State private var searchText = ""
    @State private var selectedObjects: Set<UUID> = []
    
    // Transform Controller for Blender-style interactions
    @StateObject private var transformController = TransformController()
    
    // Layout constants (8px grid system)
    private let spacing1: CGFloat = 4   // Tight spacing
    private let spacing2: CGFloat = 8   // Standard spacing
    private let spacing3: CGFloat = 16  // Section spacing
    private let spacing4: CGFloat = 24  // Panel spacing
    private let spacing5: CGFloat = 32  // Major section spacing
    
    var body: some View {
        ZStack {
            // Background Layer: 3D viewport (darkest)
            backgroundViewport
            
            // Panel Layer: Side panels with material blur
            panelLayer
            
            // Floating Layer: Command palette, modals with heavy shadows
            if showingCommandPalette {
                commandPalette
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .scale(scale: 0.95).combined(with: .opacity)
                    ))
            }
            
            // Transform overlay when in transform mode
            TransformOverlay(
                controller: transformController,
                selectedObjects: getSelectedStudioObjects()
            )
        }
        .background(.black)
        .focusable()
        .onReceive(NotificationCenter.default.publisher(for: .toggleCommandPalette)) { _ in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                showingCommandPalette.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleLeftPanel)) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                showingLeftPanel.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleRightPanel)) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                showingRightPanel.toggle()
            }
        }
        // Blender-style keyboard shortcuts
        .onKeyPress("g") { 
            startGrabMode()
            return .handled
        }
        .onKeyPress("r") { 
            startRotateMode()
            return .handled
        }
        .onKeyPress("s") { 
            startScaleMode()
            return .handled
        }
        .onKeyPress("x") { 
            setTransformAxis(.x)
            return .handled
        }
        .onKeyPress("y") { 
            setTransformAxis(.y)
            return .handled
        }
        .onKeyPress("z") { 
            setTransformAxis(.z)
            return .handled
        }
        .onKeyPress(.return) { 
            confirmTransform()
            return .handled
        }
        .onKeyPress(.escape) { 
            cancelTransform()
            return .handled
        }
        .onKeyPress("t") {
            // Test key - manually select the debug cube
            if let testCube = studioManager.studioObjects.first(where: { $0.name == "DEBUG_CUBE" }) {
                print("🧪 Manually selecting DEBUG_CUBE via 't' key")
                
                // Clear other selections
                for obj in studioManager.studioObjects {
                    obj.setSelected(false)
                }
                
                // Select test cube
                selectedObject = testCube
                testCube.setSelected(true)
                selectedObjects = [testCube.id]
                
                print("✅ Test cube selected: \(testCube.isSelected)")
            } else {
                print("❌ No DEBUG_CUBE found")
            }
            return .handled
        }
        .onChange(of: selectedTool) { _, newValue in
            if newValue == .select { selectedObject = nil }
        }
    }
    
    // MARK: - Background Viewport
    
    private var backgroundViewport: some View {
        VirtualStudioSceneView(
            studioManager: studioManager,
            selectedTool: $selectedTool,
            selectedObject: $selectedObject,
            cameraMode: $cameraMode,
            lastWorldPos: $lastWorldPos,
            transformController: transformController,
            selectedObjects: $selectedObjects
        )
        .background(.black)
        .ignoresSafeArea(.all)
    }
    
    // MARK: - Panel Layer
    
    private var panelLayer: some View {
        HStack(spacing: 0) {
            // Left Panel
            if showingLeftPanel {
                leftPanel
                    .frame(width: 280)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            
            Spacer()
            
            // Right Panel
            if showingRightPanel {
                rightPanel
                    .frame(width: 320)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showingLeftPanel)
        .animation(.easeInOut(duration: 0.25), value: showingRightPanel)
    }
    
    // MARK: - Left Panel (Tools & Assets)
    
    private var leftPanel: some View {
        VStack(spacing: 0) {
            // Panel Header
            panelHeader(
                title: "Studio Tools",
                icon: "hammer.fill",
                shortcut: "⌘1"
            )
            
            // Tools Section
            ScrollView {
                VStack(spacing: spacing3) {
                    // Primary Tools
                    raycastToolSection
                    
                    Divider()
                        .padding(.horizontal, spacing3)
                    
                    // Asset Library
                    raycastAssetLibrary
                    
                    Divider()
                        .padding(.horizontal, spacing3)
                    
                    // Virtual Cameras
                    raycastCameraSection
                }
                .padding(.vertical, spacing3)
            }
        }
        .background(.regularMaterial)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Right Panel (Properties & Outliner)
    
    private var rightPanel: some View {
        VStack(spacing: 0) {
            // Panel Header
            panelHeader(
                title: selectedObject?.name ?? "Properties",
                icon: "slider.horizontal.3",
                shortcut: "⌘2"
            )
            
            // Content
            ScrollView {
                VStack(spacing: spacing4) {
                    if let obj = selectedObject {
                        // Object Properties
                        raycastObjectProperties(obj)
                    } else {
                        // Scene Outliner when nothing selected
                        raycastSceneOutliner
                    }
                }
                .padding(.vertical, spacing3)
            }
        }
        .background(.regularMaterial)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Command Palette (Raycast's Crown Jewel)
    
    private var commandPalette: some View {
        VStack(spacing: 0) {
            // Search Field
            HStack(spacing: spacing2) {
                Image(systemName: "magnifyingglass")
                    .font(.system(.callout, design: .default, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextField("Search tools, objects, templates...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .default, weight: .regular))
                
                if !searchText.isEmpty {
                    Button("Clear") {
                        searchText = ""
                    }
                    .font(.system(.caption, design: .default, weight: .medium))
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, spacing3)
            .padding(.vertical, spacing2)
            .background(Color.gray.opacity(0.3))
            .cornerRadius(8)
            .padding(.all, spacing3)
            
            Divider()
            
            // Command Results - Simplified for now
            ScrollView {
                VStack(spacing: spacing2) {
                    Text("Command palette content")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, spacing2)
            }
            .frame(maxHeight: 400)
        }
        .frame(width: 600)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - UI Components (Simplified)
    
    private func panelHeader(title: String, icon: String, shortcut: String) -> some View {
        HStack(spacing: spacing2) {
            Image(systemName: icon)
                .font(.system(.callout, design: .default, weight: .semibold))
                .foregroundColor(.blue)
            
            Text(title)
                .font(.system(.title3, design: .default, weight: .semibold))
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(shortcut)
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.3))
                .cornerRadius(4)
        }
        .padding(.horizontal, spacing3)
        .padding(.vertical, spacing2)
        .background(.black.opacity(0.1))
    }
    
    private var raycastToolSection: some View {
        VStack(alignment: .leading, spacing: spacing2) {
            sectionHeader("Tools", icon: "hammer")
            
            VStack(spacing: spacing1) {
                ForEach(StudioTool.allCases, id: \.self) { tool in
                    raycastToolButton(tool: tool)
                }
            }
        }
        .padding(.horizontal, spacing3)
    }
    
    private func raycastToolButton(tool: StudioTool) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTool = tool
            }
        }) {
            HStack(spacing: spacing2) {
                Image(systemName: tool.icon)
                    .font(.system(.callout, design: .default, weight: .medium))
                    .foregroundColor(selectedTool == tool ? .white : .secondary)
                    .frame(width: 20, height: 20)
                
                Text(tool.name)
                    .font(.system(.body, design: .default, weight: .regular))
                    .foregroundColor(selectedTool == tool ? .white : .primary)
                
                Spacer()
                
                // Show keyboard shortcut for transform mode
                if transformController.isActive && tool == .select {
                    Text("Transform Mode")
                        .font(.system(.caption2, design: .default, weight: .medium))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, spacing2)
            .padding(.vertical, spacing2)
            .background(selectedTool == tool ? .blue : .clear)
            .cornerRadius(6)
            .animation(.easeInOut(duration: 0.2), value: selectedTool == tool)
        }
        .buttonStyle(.plain)
    }
    
    private var raycastAssetLibrary: some View {
        VStack(alignment: .leading, spacing: spacing2) {
            sectionHeader("Asset Library", icon: "cube.box")
            
            VStack(spacing: spacing1) {
                quickAddButton(icon: "tv", title: "LED Wall", action: { addLEDWall() })
                quickAddButton(icon: "chair", title: "News Desk", action: { addNewsDesk() })
                quickAddButton(icon: "lightbulb", title: "Key Light", action: { addKeyLight() })
            }
        }
        .padding(.horizontal, spacing3)
    }
    
    private var raycastCameraSection: some View {
        VStack(alignment: .leading, spacing: spacing2) {
            sectionHeader("Virtual Cameras", icon: "video")
            
            if studioManager.virtualCameras.isEmpty {
                Text("No cameras in scene")
                    .font(.system(.caption, design: .default, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, spacing2)
            } else {
                ForEach(studioManager.virtualCameras, id: \.id) { camera in
                    raycastCameraRow(camera: camera)
                }
            }
            
            Button("Add Camera") {
                addCamera()
            }
            .padding(.horizontal, spacing2)
            .padding(.vertical, spacing1)
            .background(Color.gray.opacity(0.3))
            .cornerRadius(4)
        }
        .padding(.horizontal, spacing3)
    }
    
    private var raycastSceneOutliner: some View {
        VStack(alignment: .leading, spacing: spacing3) {
            sectionHeader("Scene Outliner", icon: "list.bullet.rectangle")
            
            if studioManager.studioObjects.isEmpty {
                VStack(spacing: spacing2) {
                    Image(systemName: "cube.transparent")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    
                    Text("Empty Scene")
                        .font(.system(.headline, design: .default, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text("Add objects using the tools panel or press G to grab selected objects")
                        .font(.system(.caption, design: .default, weight: .regular))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, spacing5)
            } else {
                LazyVStack(spacing: spacing1) {
                    ForEach(studioManager.studioObjects, id: \.id) { object in
                        raycastOutlinerRow(object: object)
                    }
                }
            }
        }
        .padding(.horizontal, spacing3)
    }
    
    private func raycastObjectProperties(_ obj: StudioObject) -> some View {
        VStack(alignment: .leading, spacing: spacing3) {
            // Transform mode indicator
            if transformController.isActive {
                HStack(spacing: spacing2) {
                    Image(systemName: "move.3d")
                        .font(.system(.callout, design: .default, weight: .semibold))
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transform Mode: \(transformController.mode.rawValue.capitalized)")
                            .font(.system(.caption, design: .default, weight: .semibold))
                            .foregroundColor(.blue)
                        
                        Text("Axis: \(transformController.axis.label)")
                            .font(.system(.caption2, design: .default, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, spacing3)
                .padding(.vertical, spacing2)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, spacing3)
            }
            
            // Basic object info
            HStack(spacing: spacing2) {
                Image(systemName: obj.type.icon)
                    .font(.system(.title2, design: .default, weight: .semibold))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(obj.name)
                        .font(.system(.headline, design: .default, weight: .medium))
                    
                    Text(obj.type.name)
                        .font(.system(.caption, design: .default, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, spacing3)
            
            // Keyboard shortcuts hint
            if !transformController.isActive {
                VStack(alignment: .leading, spacing: spacing1) {
                    sectionHeader("Keyboard Shortcuts", icon: "keyboard")
                    
                    VStack(spacing: 4) {
                        shortcutRow("G", "Grab/Move")
                        shortcutRow("R", "Rotate") 
                        shortcutRow("S", "Scale")
                        shortcutRow("X/Y/Z", "Constrain to axis")
                        shortcutRow("Enter", "Confirm")
                        shortcutRow("Esc", "Cancel")
                    }
                }
                .padding(.horizontal, spacing3)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: spacing1) {
            Image(systemName: icon)
                .font(.system(.callout, design: .default, weight: .medium))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.system(.callout, design: .default, weight: .medium))
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
    
    private func quickAddButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: spacing2) {
                Image(systemName: icon)
                    .font(.system(.callout, design: .default, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                
                Text(title)
                    .font(.system(.body, design: .default, weight: .regular))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "plus.circle")
                    .font(.system(.caption, design: .default, weight: .medium))
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, spacing2)
            .padding(.vertical, spacing1)
            .background(Color.gray.opacity(0.3))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
    
    private func raycastCameraRow(camera: VirtualCamera) -> some View {
        HStack(spacing: spacing2) {
            Image(systemName: "video.circle.fill")
                .font(.system(.callout, design: .default, weight: .medium))
                .foregroundColor(camera.isActive ? .green : .secondary)
            
            Text(camera.name)
                .font(.system(.body, design: .default, weight: .regular))
                .foregroundColor(.primary)
            
            Spacer()
            
            if camera.isActive {
                Text("Active")
                    .font(.system(.caption2, design: .default, weight: .medium))
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.2))
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, spacing2)
        .padding(.vertical, spacing1)
        .background(camera.isActive ? .green.opacity(0.1) : .clear)
        .cornerRadius(4)
        .onTapGesture {
            studioManager.selectCamera(camera)
        }
    }
    
    private func raycastOutlinerRow(object: StudioObject) -> some View {
        HStack(spacing: spacing2) {
            Image(systemName: object.type.icon)
                .font(.system(.callout, design: .default, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 16)
            
            Text(object.name)
                .font(.system(.body, design: .default, weight: .regular))
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(action: {
                object.isVisible.toggle()
                object.updateNodeTransform()
            }) {
                Image(systemName: object.isVisible ? "eye" : "eye.slash")
                    .font(.system(.caption, design: .default, weight: .medium))
                    .foregroundColor(object.isVisible ? .secondary : .red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, spacing2)
        .padding(.vertical, spacing1)
        .background(selectedObject?.id == object.id ? .blue.opacity(0.2) : .clear)
        .cornerRadius(4)
        .onTapGesture {
            selectedObject = object
        }
    }
    
    private func shortcutRow(_ key: String, _ description: String) -> some View {
        HStack(spacing: spacing2) {
            Text(key)
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .foregroundColor(.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(4)
                .frame(width: 40)
            
            Text(description)
                .font(.system(.caption, design: .default, weight: .regular))
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
    
    // MARK: - Transform Actions
    
    private func startGrabMode() {
        let objects = getSelectedStudioObjects()
        guard !objects.isEmpty else { return }
        
        selectedTool = .select // Ensure we're in select mode
        // Start in free mode, user can then press X/Y/Z to constrain
        transformController.startTransform(.move, objects: objects, startPoint: .zero, scene: studioManager.scene)
        
        // Set initial axis to free so user sees no constraint line initially
        transformController.setAxis(.free)
    }
    
    private func startRotateMode() {
        let objects = getSelectedStudioObjects()
        guard !objects.isEmpty else { return }
        
        selectedTool = .select
        transformController.startTransform(.rotate, objects: objects, startPoint: .zero, scene: studioManager.scene)
        transformController.setAxis(.free)
    }
    
    private func startScaleMode() {
        let objects = getSelectedStudioObjects()
        guard !objects.isEmpty else { return }
        
        selectedTool = .select
        transformController.startTransform(.scale, objects: objects, startPoint: .zero, scene: studioManager.scene)
        transformController.setAxis(.free)
    }
    
    private func setTransformAxis(_ axis: TransformController.TransformAxis) {
        let objects = getSelectedStudioObjects()
        guard !objects.isEmpty else { 
            // No objects selected, but user pressed axis key - start grab mode on any selected object
            if let selectedObj = selectedObject {
                startGrabMode()
                transformController.setAxis(axis)
            }
            return 
        }
        
        if !transformController.isActive {
            // Start grab mode if not already active
            startGrabMode()
        }
        
        transformController.setAxis(axis)
    }
    
    private func confirmTransform() {
        transformController.confirmTransform()
    }
    
    private func cancelTransform() {
        transformController.cancelTransform()
    }
    
    private func getSelectedStudioObjects() -> [StudioObject] {
        if let selectedObject = selectedObject {
            return [selectedObject]
        }
        return studioManager.studioObjects.filter { 
            selectedObjects.contains($0.id) 
        }
    }
    
    // MARK: - Actions
    
    private func addLEDWall() {
        if let wall = LEDWallAsset.predefinedWalls.first {
            studioManager.addLEDWall(from: wall, at: SCNVector3(0, 2, 0))
        }
    }
    
    private func addCamera() {
        let camera = VirtualCamera(name: "Camera \(studioManager.virtualCameras.count + 1)", position: SCNVector3(0, 1.5, 5))
        studioManager.virtualCameras.append(camera)
        studioManager.scene.rootNode.addChildNode(camera.node)
    }
    
    private func addNewsDesk() {
        if let desk = SetPieceAsset.predefinedPieces.first(where: { $0.name.contains("Desk") }) {
            studioManager.addSetPiece(from: desk, at: SCNVector3(0, 0, 0))
        }
    }
    
    private func addKeyLight() {
        if let light = LightAsset.predefinedLights.first {
            studioManager.addLight(from: light, at: SCNVector3(2, 3, 2))
        }
    }
}

// MARK: - Scene View Implementation

struct VirtualStudioSceneView: NSViewRepresentable {
    let studioManager: VirtualStudioManager
    @Binding var selectedTool: StudioTool
    @Binding var selectedObject: StudioObject?
    @Binding var cameraMode: CameraMode
    @Binding var lastWorldPos: SCNVector3
    @ObservedObject var transformController: TransformController
    @Binding var selectedObjects: Set<UUID>
    
    func makeNSView(context: Context) -> CustomSCNView {
        let scnView = CustomSCNView()
        scnView.scene = studioManager.scene
        
        // Disable built-in camera controls so we can implement Y-axis rotation
        scnView.allowsCameraControl = false
        scnView.backgroundColor = .black
        scnView.autoenablesDefaultLighting = true
        scnView.showsStatistics = false
        
        // Enable first responder to receive scroll events
        scnView.wantsLayer = true
        DispatchQueue.main.async {
            _ = scnView.becomeFirstResponder()
        }
        
        // Setup camera controller
        context.coordinator.setupCamera(in: scnView)
        context.coordinator.setupGestures(for: scnView)
        
        // Set the coordinator as the custom view's gesture handler
        scnView.gestureHandler = context.coordinator
        
        return scnView
    }
    
    func updateNSView(_ nsView: CustomSCNView, context: Context) {
        // Keep camera controls disabled since we're handling it ourselves
        nsView.allowsCameraControl = false
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self, studioManager: studioManager)
    }
    
    // Custom SCNView that handles trackpad scroll events
    class CustomSCNView: SCNView {
        weak var gestureHandler: Coordinator?
        
        override var acceptsFirstResponder: Bool {
            return true
        }
        
        override func becomeFirstResponder() -> Bool {
            return true
        }
        
        override func awakeFromNib() {
            super.awakeFromNib()
            // Ensure we can receive scroll events
            self.wantsLayer = true
        }
        
        override func scrollWheel(with event: NSEvent) {
            // Always handle trackpad gestures, regardless of phase
            let deltaX = Float(event.scrollingDeltaX)
            let deltaY = Float(event.scrollingDeltaY)
            
            // Check if there's actual movement
            if abs(deltaX) > 0.1 || abs(deltaY) > 0.1 {
                gestureHandler?.handleTrackpadScroll(deltaX: deltaX, deltaY: deltaY)
            } else {
                // Pass through if no movement
                super.scrollWheel(with: event)
            }
        }
    }
    
    @MainActor
    final class Coordinator: NSObject, NSGestureRecognizerDelegate {
        let parent: VirtualStudioSceneView
        let studioManager: VirtualStudioManager
        
        // Camera control properties
        private var cameraNode: SCNNode!
        private var cameraDistance: Float = 15.0
        private var cameraAzimuth: Float = 0.0      // Y-axis rotation (horizontal)
        private var cameraElevation: Float = 0.3    // X-axis rotation (vertical)
        private var focusPoint = SCNVector3(0, 1, 0)
        
        init(_ parent: VirtualStudioSceneView, studioManager: VirtualStudioManager) {
            self.parent = parent
            self.studioManager = studioManager
        }
        
        func setupCamera(in scnView: SCNView) {
            // Remove any existing camera
            studioManager.scene.rootNode.childNode(withName: "viewport_camera", recursively: true)?.removeFromParentNode()
            
            let camera = SCNCamera()
            camera.fieldOfView = 60
            camera.zNear = 0.1
            camera.zFar = 1000
            camera.automaticallyAdjustsZRange = true
            
            cameraNode = SCNNode()
            cameraNode.camera = camera
            cameraNode.name = "viewport_camera"
            
            studioManager.scene.rootNode.addChildNode(cameraNode)
            scnView.pointOfView = cameraNode
            
            updateCameraPosition()
        }
        
        func setupGestures(for view: SCNView) {
            print("🎮 Setting up gestures for SCNView...")
            
            // Magnify gesture for zooming (this already works)
            let magnifyGesture = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
            magnifyGesture.delegate = self
            view.addGestureRecognizer(magnifyGesture)
            print("   ✅ Added magnify gesture")
            
            // Click gesture for selection - MAKE SURE THIS IS ADDED
            let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
            clickGesture.delegate = self
            clickGesture.numberOfClicksRequired = 1
            clickGesture.buttonMask = 0x1 // Left mouse button only
            view.addGestureRecognizer(clickGesture)
            print("   ✅ Added click gesture")
            
            // Pan gesture for when user drags (shift to pan focus point)
            let panGesture = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            panGesture.delegate = self
            view.addGestureRecognizer(panGesture)
            print("   ✅ Added pan gesture")
            
            print("   🎮 Total gestures on view: \(view.gestureRecognizers.count)")
        }
        
        func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer) -> Bool {
            print("🤝 Gesture recognition: \(type(of: gestureRecognizer)) with \(type(of: otherGestureRecognizer))")
            return true
        }
        
        // Handle trackpad scroll for orbiting
        func handleTrackpadScroll(deltaX: Float, deltaY: Float) {
            let sensitivity: Float = 0.01
            let deltaAzimuth = deltaX * sensitivity     // Horizontal = Y-axis rotation
            let deltaElevation = deltaY * sensitivity   // Vertical = X-axis rotation
            
            cameraAzimuth += deltaAzimuth
            cameraElevation += deltaElevation
            
            // Clamp elevation to prevent flipping
            let maxElevation: Float = Float.pi / 2 - 0.1
            cameraElevation = max(-maxElevation, min(maxElevation, cameraElevation))
            
            updateCameraPosition()
        }
        
        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { 
                print("❌ No SCNView in click gesture")
                return 
            }
            let point = gesture.location(in: view)
            
            print("🖱️ Click detected at: \(point)")
            print("🎮 Current tool: \(parent.selectedTool)")
            print("🏠 Scene has \(studioManager.studioObjects.count) objects")
            
            Task { @MainActor in
                // Always do hit testing regardless of tool
                let hits = view.hitTest(point, options: [
                    SCNHitTestOption.boundingBoxOnly: false,
                    SCNHitTestOption.firstFoundOnly: false,
                    SCNHitTestOption.ignoreHiddenNodes: true
                ])
                print("🎯 Hit test results: \(hits.count) hits")
                
                for (index, hit) in hits.enumerated() {
                    print("  Hit \(index): node=\(hit.node.name ?? "unnamed"), geometry=\(hit.node.geometry != nil)")
                }
                
                // Check if we're confirming a transform
                if self.parent.transformController.isActive {
                    print("✅ Confirming active transform")
                    self.parent.transformController.confirmTransform()
                    return
                }
                
                switch self.parent.selectedTool {
                case .select:
                    if let hit = hits.first {
                        print("🔍 Processing hit on node: \(hit.node.name ?? "unnamed")")
                        
                        // Try to find the studio object
                        if let obj = self.studioManager.getObject(from: hit.node) {
                            print("✅ Found studio object: \(obj.name) (ID: \(obj.id))")
                            
                            // Check if transform controller wants to handle this click
                            if self.parent.transformController.handleMouseDown(at: point, on: obj) {
                                print("🎮 Transform controller handling click")
                                return
                            }
                            
                            // Clear all previous selections
                            for otherObj in self.studioManager.studioObjects {
                                if otherObj.id != obj.id {
                                    otherObj.setSelected(false)
                                    print("🔄 Cleared selection for: \(otherObj.name)")
                                }
                            }
                            
                            // Select the clicked object
                            self.parent.selectedObject = obj
                            obj.setSelected(true)
                            print("🎯 Selected object: \(obj.name)")
                            
                            // Focus camera on selected object
                            self.focusPoint = obj.position
                            self.updateCameraPosition()
                            
                            // Update selection set
                            if NSEvent.modifierFlags.contains(.command) {
                                if self.parent.selectedObjects.contains(obj.id) {
                                    self.parent.selectedObjects.remove(obj.id)
                                    obj.setSelected(false)
                                    print("➖ Removed from selection: \(obj.name)")
                                } else {
                                    self.parent.selectedObjects.insert(obj.id)
                                    obj.setSelected(true)
                                    print("➕ Added to selection: \(obj.name)")
                                }
                            } else {
                                self.parent.selectedObjects = [obj.id]
                                print("🔄 Set single selection: \(obj.name)")
                            }
                        } else {
                            print("❌ Hit node but no studio object found")
                            print("   Node name: \(hit.node.name ?? "unnamed")")
                            print("   Node has geometry: \(hit.node.geometry != nil)")
                            print("   Node parent: \(hit.node.parent?.name ?? "no parent")")
                        }
                    } else {
                        print("❌ No hits - clearing selection")
                        // Clicked on empty space - clear selection
                        self.parent.selectedObject = nil
                        self.parent.selectedObjects.removeAll()
                        
                        // Clear all object selections
                        for obj in self.studioManager.studioObjects {
                            obj.setSelected(false)
                        }
                    }
                    
                case .ledWall, .camera, .setPiece, .light:
                    let worldPos = self.studioManager.worldPosition(from: point, in: view)
                    self.parent.lastWorldPos = worldPos
                    self.studioManager.addObject(type: self.parent.selectedTool, at: worldPos)
                    print("➕ Added object of type: \(self.parent.selectedTool) at \(worldPos)")
                }
            }
        }
        
        @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            
            let translation = gesture.translation(in: view)
            let velocity = gesture.velocity(in: view)
            let currentPoint = gesture.location(in: view)
            
            // Handle transform controller drag first
            if gesture.state == .began {
                // Check if starting a drag on a selected object
                let hits = view.hitTest(currentPoint, options: nil)
                if let hit = hits.first, let obj = studioManager.getObject(from: hit.node) {
                    if parent.transformController.handleMouseDown(at: currentPoint, on: obj) {
                        return // Transform controller is handling this
                    }
                }
            }
            
            if gesture.state == .changed {
                // Check if transform controller is handling drag
                if parent.transformController.axis != .free {
                    parent.transformController.handleMouseDrag(to: currentPoint)
                    if parent.transformController.isDragging {
                        return // Transform controller is handling this
                    }
                }
            }
            
            if gesture.state == .ended || gesture.state == .cancelled {
                parent.transformController.handleMouseUp()
                if parent.transformController.isDragging {
                    return // Transform controller handled this
                }
            }
            
            // Check if we're in transform mode (keyboard initiated)
            if parent.transformController.isActive && !parent.transformController.isDragging {
                // Update transform with mouse movement (keyboard-initiated transform)
                parent.transformController.updateTransformWithMouse(mousePos: currentPoint)
                gesture.setTranslation(.zero, in: view)
                return
            }
            
            // Regular camera controls
            if abs(velocity.x) > 50 || abs(velocity.y) > 50 {
                // This looks like a scroll gesture - use for orbiting
                let sensitivity: Float = 0.005
                let deltaAzimuth = Float(translation.x) * sensitivity     // Horizontal = Y-axis rotation
                let deltaElevation = -Float(translation.y) * sensitivity  // Vertical = X-axis rotation
                
                cameraAzimuth += deltaAzimuth
                cameraElevation += deltaElevation
                
                // Clamp elevation
                let maxElevation: Float = Float.pi / 2 - 0.1
                cameraElevation = max(-maxElevation, min(maxElevation, cameraElevation))
                
                updateCameraPosition()
                gesture.setTranslation(.zero, in: view)
            } else if NSEvent.modifierFlags.contains(.shift) {
                // Slow movement with Shift = pan focus point
                handleCameraPan(deltaX: Float(translation.x), deltaY: Float(translation.y))
                gesture.setTranslation(.zero, in: view)
            }
        }
        
        @objc func handleMagnify(_ gesture: NSMagnificationGestureRecognizer) {
            let zoomFactor = 1.0 + gesture.magnification
            let newDistance = cameraDistance / Float(zoomFactor)
            
            cameraDistance = max(1.0, min(100.0, newDistance))
            updateCameraPosition()
            gesture.magnification = 0
        }
        
        private func handleCameraPan(deltaX: Float, deltaY: Float) {
            // Calculate right and up vectors from camera transform
            let cameraTransform = cameraNode.worldTransform
            let rightVector = SCNVector3(cameraTransform.m11, cameraTransform.m12, cameraTransform.m13)
            let upVector = SCNVector3(cameraTransform.m21, cameraTransform.m22, cameraTransform.m23)
            
            let panScale = cameraDistance * 0.001
            let panX = deltaX * panScale
            let panY = deltaY * panScale
            
            // Break up the complex expression with proper type conversion
            let rightMovement = SCNVector3(
                -Float(rightVector.x) * panX,
                -Float(rightVector.y) * panX,
                -Float(rightVector.z) * panX
            )
            let upMovement = SCNVector3(
                -Float(upVector.x) * panY,
                -Float(upVector.y) * panY,
                -Float(upVector.z) * panY
            )
            
            focusPoint = SCNVector3(
                focusPoint.x + CGFloat(rightMovement.x + upMovement.x),
                focusPoint.y + CGFloat(rightMovement.y + upMovement.y),
                focusPoint.z + CGFloat(rightMovement.z + upMovement.z)
            )
            
            updateCameraPosition()
        }
        
        private func updateCameraPosition() {
            // Spherical to Cartesian conversion
            // Azimuth rotates around Y-axis (horizontal movement)
            // Elevation rotates around X-axis (vertical movement)
            let x = cameraDistance * cos(cameraElevation) * sin(cameraAzimuth)
            let y = cameraDistance * sin(cameraElevation)
            let z = cameraDistance * cos(cameraElevation) * cos(cameraAzimuth)
            
            cameraNode.position = SCNVector3(
                focusPoint.x + CGFloat(x),
                focusPoint.y + CGFloat(y),
                focusPoint.z + CGFloat(z)
            )
            
            cameraNode.look(at: focusPoint, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        }
    }
}

enum CameraMode: String, CaseIterable, Hashable {
    case orbit, pan, fly
}
