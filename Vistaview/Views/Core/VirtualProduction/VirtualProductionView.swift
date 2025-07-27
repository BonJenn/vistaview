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
    @State private var showingAddMenu = false
    @State private var showingDraggableMenu = true // Make it visible by default
    @State private var showingObjectBrowser = true // Control visibility of draggable object browser
    
    // Transform Controller for Blender-style interactions
    @StateObject private var transformController = TransformController()
    
    // Camera Feed Management
    @StateObject private var cameraDeviceManager = CameraDeviceManager()
    @StateObject private var cameraFeedManager: CameraFeedManager
    
    // Modal states
    @State private var showingCameraFeedModal = false
    @State private var selectedLEDWallForFeed: StudioObject?
    
    // Debug frame counter
    @State private var feedUpdateFrameCount = 0
    
    // Viewport 3D states
    @State private var transformMode: TransformController.TransformMode = .move
    @State private var viewMode: Viewport3DView.ViewportViewMode = .solid
    @State private var snapToGrid = true
    @State private var gridSize: Float = 1.0
    @State private var cameraAzimuth: Float = 0.0
    @State private var cameraElevation: Float = 0.3
    @State private var cameraRoll: Float = 0.0
    
    // Layout constants (8px grid system)
    private let spacing1: CGFloat = 4   // Tight spacing
    private let spacing2: CGFloat = 8   // Standard spacing
    private let spacing3: CGFloat = 16  // Section spacing
    private let spacing4: CGFloat = 24  // Panel spacing
    private let spacing5: CGFloat = 32  // Major section spacing
    
    init() {
        let deviceManager = CameraDeviceManager()
        let feedManager = CameraFeedManager(cameraDeviceManager: deviceManager)
        
        self._cameraDeviceManager = StateObject(wrappedValue: deviceManager)
        self._cameraFeedManager = StateObject(wrappedValue: feedManager)
    }
    
    var body: some View {
        mainContent
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
            // Object placement shortcuts (Blender-style)
            .onKeyPress("v") {
                self.selectedTool = .select
                return .handled
            }
            .onKeyPress("l") {
                self.selectedTool = .ledWall
                return .handled
            }
            .onKeyPress("c") {
                self.selectedTool = .camera
                return .handled
            }
            // Toggle draggable menu with 'D' key
            .onKeyPress("d") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.showingDraggableMenu.toggle()
                }
                return .handled
            }
            // Toggle object browser window with 'B' key
            .onKeyPress("b") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.showingObjectBrowser.toggle()
                }
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
            .onAppear {
                setupInitialCameras()
            }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            // Background Layer: 3D viewport (darkest)
            backgroundViewport
            
            // Blender-style toolbar overlay
            BlenderStyleToolbar(
                selectedTool: $selectedTool,
                showingAddMenu: $showingAddMenu,
                onAddObject: handleAddObject
            )
            
            // Panel Layer: Side panels with material blur
            panelLayer
            
            // Draggable Object Browser Window
            if showingObjectBrowser {
                DraggableResizableWindow(title: "Studio Objects") {
                    VisibleObjectBrowser()
                        .environmentObject(studioManager) // Pass the studio manager
                }
            }
            
            // Floating overlays (highest layer)
            floatingOverlays
            
            // Transform overlay when in transform mode
            TransformOverlay(
                controller: transformController,
                selectedObjects: getSelectedStudioObjects()
            )
            .zIndex(20) // Ensure transform overlay is always on top
        }
    }
    
    @ViewBuilder
    private var floatingOverlays: some View {
        Group {
            // Command palette
            if showingCommandPalette {
                commandPalette
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .scale(scale: 0.95).combined(with: .opacity)
                    ))
            }
            
            // Camera Feed Modal
            if showingCameraFeedModal, let ledWall = selectedLEDWallForFeed {
                LEDWallCameraFeedModal(
                    ledWall: ledWall,
                    cameraFeedManager: cameraFeedManager,
                    isPresented: $showingCameraFeedModal
                ) { feedID in
                    handleCameraFeedConnection(feedID: feedID, ledWall: ledWall)
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95).combined(with: .opacity),
                    removal: .scale(scale: 0.95).combined(with: .opacity)
                ))
            }
        }
    }
    
    private func setupInitialCameras() {
        Task {
            print("🎬 Starting camera discovery...")
            let devices = await cameraFeedManager.getAvailableDevices()
            print("📹 Found \(devices.count) camera devices")
            
            // Debug: Print all found devices
            for device in devices {
                print("  📱 Device: \(device.displayName)")
                print("    - Type: \(device.deviceType.rawValue)")
                print("    - Available: \(device.isAvailable)")
                print("    - Has capture device: \(device.captureDevice != nil)")
            }
            
            // Auto-start feeds for available devices (optional)
            for device in devices.prefix(2) { // Limit to first 2 cameras
                if device.isAvailable {
                    print("🎥 Auto-starting feed for: \(device.displayName)")
                    await cameraFeedManager.startFeed(for: device)
                }
            }
            
            // Debug: Check if we have any active feeds
            print("📺 Active feeds after startup: \(cameraFeedManager.activeFeeds.count)")
        }
    }
    
    // MARK: - Camera Feed Management
    
    private func showCameraFeedModal(for ledWall: StudioObject) {
        selectedLEDWallForFeed = ledWall
        showingCameraFeedModal = true
        print("📹 Showing camera feed modal for LED wall: \(ledWall.name)")
    }
    
    private func handleCameraFeedConnection(feedID: UUID?, ledWall: StudioObject) {
        Task { @MainActor in
            if let feedID = feedID {
                // Connect the camera feed
                ledWall.connectCameraFeed(feedID)
                print("✅ Connected camera feed \(feedID) to LED wall: \(ledWall.name)")
                
                // Start live feed updates
                startLiveFeedUpdates(for: ledWall, feedID: feedID)
            } else {
                // Disconnect the camera feed
                ledWall.disconnectCameraFeed()
                print("🔌 Disconnected camera feed from LED wall: \(ledWall.name)")
                
                // Stop live feed updates
                stopLiveFeedUpdates(for: ledWall)
            }
        }
    }
    
    private func startLiveFeedUpdates(for ledWall: StudioObject, feedID: UUID) {
        guard let cameraFeed = cameraFeedManager.activeFeeds.first(where: { $0.id == feedID }) else {
            print("❌ Camera feed not found: \(feedID)")
            return
        }
        
        print("🎬 Starting live feed updates for LED wall: \(ledWall.name)")
        print("   - Feed device: \(cameraFeed.device.displayName)")
        print("   - Feed status: \(cameraFeed.connectionStatus.displayText)")
        
        // Create a timer to update the LED wall with live camera feed content
        Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { timer in
            Task { @MainActor in
                // Check if connection is still valid
                guard ledWall.connectedCameraFeedID == feedID,
                      ledWall.isDisplayingCameraFeed else {
                    print("🛑 Stopping timer - connection no longer valid")
                    timer.invalidate()
                    return
                }
                
                // Check if feed is still active
                guard let activeFeed = self.cameraFeedManager.activeFeeds.first(where: { $0.id == feedID }),
                      activeFeed.connectionStatus == .connected else {
                    print("⚠️ Feed no longer active, stopping updates")
                    timer.invalidate()
                    return
                }
                
                // Update LED wall with latest frame
                var updated = false
                
                if let previewImage = activeFeed.previewImage {
                    ledWall.updateCameraFeedContent(cgImage: previewImage)
                    updated = true
                } else if let pixelBuffer = activeFeed.currentFrame {
                    ledWall.updateCameraFeedContent(pixelBuffer: pixelBuffer)
                    updated = true
                }
                
                // Debug logging every few seconds
                self.feedUpdateFrameCount += 1
                if self.feedUpdateFrameCount % 150 == 1 { // Every ~5 seconds at 30fps
                    print("📺 LED Wall '\(ledWall.name)' feed update #\(self.feedUpdateFrameCount)")
                    print("   - Has preview image: \(activeFeed.previewImage != nil)")
                    print("   - Has pixel buffer: \(activeFeed.currentFrame != nil)")
                    print("   - Updated this frame: \(updated)")
                    print("   - Feed connection status: \(activeFeed.connectionStatus.displayText)")
                }
            }
        }
        
        print("✅ Started live feed timer for LED wall: \(ledWall.name)")
    }
    
    private func stopLiveFeedUpdates(for ledWall: StudioObject) {
        // Timer will auto-invalidate when the connection check fails
        print("🛑 Stopped live feed updates for LED wall: \(ledWall.name)")
    }
    
    // MARK: - Background Viewport
    
    private var backgroundViewport: some View {
        ZStack {
            // Main 3D Viewport
            Viewport3DView(
                studioManager: studioManager,
                selectedTool: $selectedTool,
                transformMode: $transformMode,
                viewMode: $viewMode,
                selectedObjects: $selectedObjects,
                snapToGrid: $snapToGrid,
                gridSize: $gridSize,
                transformController: transformController,
                cameraAzimuth: $cameraAzimuth,
                cameraElevation: $cameraElevation,
                cameraRoll: $cameraRoll
            )
            .background(.black)
            .ignoresSafeArea(.all)
            .onAppear {
                // Initialize camera orientation tracking if needed
            }
            
            // 3D Compass overlay
            Viewport3DCompass(
                cameraAzimuth: $cameraAzimuth,
                cameraElevation: $cameraElevation,
                cameraRoll: $cameraRoll
            )
        }
    }
    
    // MARK: - Transform Actions
    
    private func startGrabMode() {
        let objects = getSelectedStudioObjects()
        guard !objects.isEmpty else { return }
        
        selectedTool = .select
        transformController.startTransform(.move, objects: objects, startPoint: .zero, scene: studioManager.scene)
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
            if let selectedObj = selectedObject {
                startGrabMode()
                transformController.setAxis(axis)
            }
            return 
        }
        
        if !transformController.isActive {
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
    
    private func handleObjectDrop(_ asset: any StudioAsset, at dropPoint: CGPoint) {
        // This is called when an object is dropped from the draggable menu
        // The actual drop handling is done in Viewport3DView's performDragOperation
        print("🎯 Object drop initiated: \(asset.name)")
    }
    
    private func handleAddObject(_ toolType: StudioTool, _ asset: any StudioAsset) {
        // Generate a random position for demo - in real implementation,
        // this would use the 3D cursor or mouse position
        let randomPos = SCNVector3(
            Float.random(in: -5...5),
            Float.random(in: 0...3),
            Float.random(in: -5...5)
        )
        
        switch asset {
        case let ledWallAsset as LEDWallAsset:
            studioManager.addLEDWall(from: ledWallAsset, at: randomPos)
        case let cameraAsset as CameraAsset:
            addCameraFromAsset(cameraAsset, at: randomPos)
        case let lightAsset as LightAsset:
            studioManager.addLight(from: lightAsset, at: randomPos)
        case let setPieceAsset as SetPieceAsset:
            studioManager.addSetPiece(from: setPieceAsset, at: randomPos)
        default:
            print("⚠️ Unknown asset type: \(type(of: asset))")
        }
        
        selectedTool = .select // Return to select mode after adding
    }
    
    private func addCameraFromAsset(_ asset: CameraAsset, at position: SCNVector3) {
        let camera = VirtualCamera(name: asset.name, position: position)
        camera.focalLength = Float(asset.focalLength)
        studioManager.virtualCameras.append(camera)
        studioManager.scene.rootNode.addChildNode(camera.node)
    }
    
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
    
    // MARK: - Camera Management
    
    private func refreshCameras() {
        Task {
            print("🔄 Manually refreshing cameras...")
            await cameraFeedManager.forceRefreshDevices()
            
            let devices = cameraFeedManager.availableDevices
            print("📹 After refresh - found \(devices.count) devices:")
            for device in devices {
                print("  - \(device.displayName) (\(device.deviceType.rawValue)) - Available: \(device.isAvailable)")
            }
        }
    }
    
    private func debugCameras() {
        Task {
            print("🧪 Running camera debug session...")
            await cameraFeedManager.debugCameraDetection()
        }
    }
    
    private func colorForObjectType(_ type: StudioTool) -> Color {
        switch type {
        case .ledWall: return .blue
        case .camera: return .orange
        case .light: return .yellow
        case .setPiece: return .green
        case .select: return .purple
        }
    }

    // MARK: - Panel Views (simplified for space)
    
    private var panelLayer: some View {
        HStack(spacing: 0) {
            if showingLeftPanel {
                leftPanel
                    .frame(width: 280)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            
            Spacer()
            
            if showingRightPanel {
                rightPanel
                    .frame(width: 320)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showingLeftPanel)
        .animation(.easeInOut(duration: 0.25), value: showingRightPanel)
    }
    
    private var leftPanel: some View {
        VStack(spacing: 0) {
            Text("Studio Tools")
                .font(.headline)
                .padding()
            
            // Quick stats
            VStack(alignment: .leading, spacing: 4) {
                Text("Selected Tool: \(selectedTool.name)")
                    .font(.caption)
                
                Text("Objects: \(studioManager.studioObjects.count)")
                    .font(.caption)
                
                Text("Cameras: \(studioManager.virtualCameras.count)")
                    .font(.caption)
                
                Text("Camera Feeds: \(cameraFeedManager.activeFeeds.count)")
                    .font(.caption)
            }
            .padding(.horizontal)
            
            Divider()
                .padding(.vertical, 8)
            
            // Keyboard shortcuts info
            VStack(alignment: .leading, spacing: 2) {
                Text("Shortcuts:")
                    .font(.caption.weight(.semibold))
                
                Group {
                    Text("V - Select")
                    Text("L - LED Wall")
                    Text("C - Camera")
                    Text("B - Object Browser")
                    Text("D - Drag Menu")
                    Text("Shift+L - Light")
                    Text("Shift+A - Add Menu")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            Divider()
                .padding(.vertical, 8)
            
            // Selection info
            if !selectedObjects.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected Objects:")
                        .font(.caption.weight(.semibold))
                    
                    ForEach(Array(selectedObjects.prefix(3)), id: \.self) { objectID in
                        if let object = studioManager.studioObjects.first(where: { $0.id == objectID }) {
                            HStack {
                                Circle()
                                    .fill(colorForObjectType(object.type))
                                    .frame(width: 8, height: 8)
                                
                                Text(object.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                                
                                Spacer()
                            }
                        }
                    }
                    
                    if selectedObjects.count > 3 {
                        Text("... and \(selectedObjects.count - 3) more")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
            }
            
            Spacer()
            
            Button("Refresh Cameras") {
                refreshCameras()
            }
            .padding()
        }
        .background(.regularMaterial)
    }
    
    private var rightPanel: some View {
        VStack(spacing: 0) {
            Text("Properties")
                .font(.headline)
                .padding()
            
            if let obj = selectedObject {
                Text("Selected: \(obj.name)")
                    .font(.caption)
                    .padding()
            }
            
            Spacer()
        }
        .background(.regularMaterial)
    }
    
    private var commandPalette: some View {
        VStack {
            Text("Command Palette")
                .font(.title2)
                .padding()
            
            TextField("Search...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding()
            
            Spacer()
        }
        .frame(width: 400, height: 300)
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Scene View (Simplified)

enum CameraMode: String, CaseIterable, Hashable {
    case orbit, pan, fly}