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
    
    // Keyboard Feedback Controller
    @StateObject private var keyboardFeedback = KeyboardFeedbackController()
    
    // Camera Feed Management - USE SHARED MANAGER
    @EnvironmentObject var productionManager: UnifiedProductionManager
    
    // Computed property to access shared camera feed manager
    private var cameraFeedManager: CameraFeedManager {
        return productionManager.cameraFeedManager
    }
    
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
    
    // Cursor tracking for distance-based scaling
    @State private var currentMousePosition: CGPoint = .zero
    @State private var isTrackingCursor = false

    // Layout constants (8px grid system)
    private let spacing1: CGFloat = 4   // Tight spacing
    private let spacing2: CGFloat = 8   // Standard spacing
    private let spacing3: CGFloat = 16  // Section spacing
    private let spacing4: CGFloat = 24  // Panel spacing
    private let spacing5: CGFloat = 32  // Major section spacing
    
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
            // NEW: Handle LED Wall camera feed modal notifications
            .onReceive(NotificationCenter.default.publisher(for: .showLEDWallCameraFeedModal)) { notification in
                if let ledWall = notification.object as? StudioObject {
                    print("📹 Received request to show camera feed modal for: \(ledWall.name)")
                    selectedLEDWallForFeed = ledWall
                    showingCameraFeedModal = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .ledWallCameraFeedDisconnected)) { notification in
                if let ledWall = notification.object as? StudioObject {
                    print("🔌 LED Wall camera feed disconnected: \(ledWall.name)")
                    // Force view update
                    studioManager.objectWillChange.send()
                }
            }
            // Blender-style keyboard shortcuts with visual feedback
            .onKeyPress("g") { 
                startGrabMode()
                keyboardFeedback.showFeedback("G - Grab/Move (press X/Y/Z to constrain axis)", color: .green)
                return .handled
            }
            .onKeyPress("r") { 
                startRotateMode()
                keyboardFeedback.showFeedback("R - Rotate (press X/Y/Z to constrain axis, Shift to snap to 15°)", color: .orange)
                return .handled
            }
            .onKeyPress("s") { 
                startDistanceBasedScaleMode()
                keyboardFeedback.showFeedback("S - Distance Scale (move cursor closer/farther, Enter to confirm)", color: .purple)
                return .handled
            }
            .onKeyPress("x") { 
                setTransformAxis(.x)
                keyboardFeedback.showFeedback("X - Constrained to X-axis (Red)", color: .red)
                return .handled
            }
            .onKeyPress("y") { 
                setTransformAxis(.y)
                keyboardFeedback.showFeedback("Y - Constrained to Y-axis (Green)", color: .green)
                return .handled
            }
            .onKeyPress("z") { 
                setTransformAxis(.z)
                keyboardFeedback.showFeedback("Z - Constrained to Z-axis (Blue)", color: .blue)
                return .handled
            }
            .onKeyPress(.return) { 
                if transformController.isDistanceScaling {
                    transformController.confirmDistanceScaling()
                    keyboardFeedback.showFeedback("✓ Scale Locked", color: .green)
                    isTrackingCursor = false
                } else {
                    confirmTransform()
                    keyboardFeedback.showFeedback("✓ Transform Confirmed", color: .green)
                }
                return .handled
            }
            .onKeyPress(.escape) { 
                if transformController.isDistanceScaling {
                    transformController.cancelDistanceScaling()
                    keyboardFeedback.showFeedback("✗ Scale Cancelled", color: .red)
                    isTrackingCursor = false
                } else {
                    cancelTransform()
                    keyboardFeedback.showFeedback("✗ Transform Cancelled", color: .red)
                }
                return .handled
            }
            // Object placement shortcuts (Blender-style)
            .onKeyPress("v") {
                self.selectedTool = .select
                keyboardFeedback.showFeedback("V - Select Tool", color: .white)
                return .handled
            }
            .onKeyPress("l") {
                self.selectedTool = .ledWall
                keyboardFeedback.showFeedback("L - LED Wall Tool", color: .blue)
                return .handled
            }
            .onKeyPress("c") {
                self.selectedTool = .camera
                keyboardFeedback.showFeedback("C - Camera Tool", color: .orange)
                return .handled
            }
            // Toggle draggable menu with 'D' key
            .onKeyPress("d") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.showingDraggableMenu.toggle()
                }
                keyboardFeedback.showFeedback("D - Toggle Drag Menu", color: .cyan)
                return .handled
            }
            // Toggle object browser window with 'B' key
            .onKeyPress("b") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.showingObjectBrowser.toggle()
                }
                keyboardFeedback.showFeedback("B - Toggle Object Browser", color: .purple)
                return .handled
            }
            .onKeyPress("t") {
                // Test key - debug selection system
                studioManager.testSelectionSystem()
                keyboardFeedback.showFeedback("T - Testing Selection System", color: .yellow)
                return .handled
            }
            .onKeyPress("h") {
                // Reset highlights if they're misaligned
                studioManager.resetObjectHighlights()
                keyboardFeedback.showFeedback("H - Reset Highlights", color: .cyan)
                return .handled
            }
            .onChange(of: selectedTool) { _, newValue in
                if newValue == .select { selectedObject = nil }
            }
            .onAppear {
                print("🎬 Virtual Production: Ready - cameras available for user selection")
            }
            // Arrow key support for fine object positioning
            .onKeyPress(.upArrow) {
                if transformController.isActive {
                    transformController.nudgeObjects(.up)
                    
                    // Show appropriate feedback based on current axis constraint
                    switch transformController.axis {
                    case .z:
                        keyboardFeedback.showFeedback("↑ Nudge Forward (Z+)", color: .blue)
                    case .y, .free:
                        keyboardFeedback.showFeedback("↑ Nudge Up (Y+)", color: .green)
                    case .x:
                        keyboardFeedback.showFeedback("↑ No movement (X-axis only)", color: .orange)
                    }
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.downArrow) {
                if transformController.isActive {
                    transformController.nudgeObjects(.down)
                    
                    // Show appropriate feedback based on current axis constraint
                    switch transformController.axis {
                    case .z:
                        keyboardFeedback.showFeedback("↓ Nudge Backward (Z-)", color: .blue)
                    case .y, .free:
                        keyboardFeedback.showFeedback("↓ Nudge Down (Y-)", color: .green)
                    case .x:
                        keyboardFeedback.showFeedback("↓ No movement (X-axis only)", color: .orange)
                    }
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.leftArrow) {
                if transformController.isActive {
                    transformController.nudgeObjects(.left)
                    
                    switch transformController.axis {
                    case .x, .free:
                        keyboardFeedback.showFeedback("← Nudge Left (X-)", color: .red)
                    default:
                        keyboardFeedback.showFeedback("← No movement (axis constrained)", color: .orange)
                    }
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.rightArrow) {
                if transformController.isActive {
                    transformController.nudgeObjects(.right)
                    
                    switch transformController.axis {
                    case .x, .free:
                        keyboardFeedback.showFeedback("→ Nudge Right (X+)", color: .red)
                    default:
                        keyboardFeedback.showFeedback("→ No movement (axis constrained)", color: .orange)
                    }
                    return .handled
                }
                return .ignored
            }
            // Add support for forward/backward with Shift+Up/Down
            .onKeyPress(.upArrow) {
                if NSEvent.modifierFlags.contains(.shift) && transformController.isActive {
                    transformController.nudgeObjects(.forward)
                    keyboardFeedback.showFeedback("⬆ Nudge Forward", color: .blue)
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.downArrow) {
                if NSEvent.modifierFlags.contains(.shift) && transformController.isActive {
                    transformController.nudgeObjects(.backward)
                    keyboardFeedback.showFeedback("⬇ Nudge Backward", color: .blue)
                    return .handled
                }
                return .ignored
            }
            // Delete key support - ENHANCED VERSION
            .onKeyPress(.delete) {
                let selectedObjs = getSelectedStudioObjects()
                if !selectedObjs.isEmpty {
                    // Check if any selected objects are locked
                    let lockedObjects = selectedObjs.filter { $0.isLocked }
                    let unlocked = selectedObjs.filter { !$0.isLocked }
                    
                    if !lockedObjects.isEmpty {
                        keyboardFeedback.showFeedback("⚠️ Cannot delete \(lockedObjects.count) locked object(s)", color: .orange)
                        print("🔒 Blocked deletion of locked objects: \(lockedObjects.map { $0.name })")
                    }
                    
                    if !unlocked.isEmpty {
                        // Delete immediately - keep it simple
                        for obj in unlocked {
                            studioManager.deleteObject(obj)
                            selectedObjects.remove(obj.id)
                        }
                        keyboardFeedback.showFeedback("🗑️ Deleted \(unlocked.count) object(s)", color: .red)
                    }
                } else {
                    keyboardFeedback.showFeedback("⚠️ No objects selected to delete", color: .orange)
                }
                return .handled
            }
            .onChange(of: selectedTool) { _, newValue in
                if newValue == .select { selectedObject = nil }
            }
            // Cursor tracking when in distance scaling mode
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    currentMousePosition = location
                    if transformController.isDistanceScaling {
                        transformController.updateDistanceBasedScaling(currentMousePos: location)
                    }
                case .ended:
                    break
                }
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
            
            // Keyboard Feedback Overlay - HIGH PRIORITY
            KeyboardFeedbackOverlay(controller: keyboardFeedback)
                .zIndex(100) // Ensure it's always on top
            
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
    
    // MARK: - Command Palette
    
    private var commandPalette: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "command")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Command Palette")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button("✕") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                        showingCommandPalette = false
                    }
                }
                .foregroundColor(.white.opacity(0.7))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            // Search field
            TextField("Search commands...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
            
            // Command list
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    CommandPaletteItem(title: "Add LED Wall", shortcut: "L", icon: "tv") {
                        selectedTool = .ledWall
                        showingCommandPalette = false
                    }
                    
                    CommandPaletteItem(title: "Add Camera", shortcut: "C", icon: "video") {
                        selectedTool = .camera
                        showingCommandPalette = false
                    }
                    
                    CommandPaletteItem(title: "Add Light", shortcut: "Shift+L", icon: "lightbulb") {
                        selectedTool = .light
                        showingCommandPalette = false
                    }
                    
                    CommandPaletteItem(title: "Toggle Object Browser", shortcut: "B", icon: "cube.box") {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showingObjectBrowser.toggle()
                        }
                        showingCommandPalette = false
                    }
                    
                    CommandPaletteItem(title: "Select Tool", shortcut: "V", icon: "cursorarrow") {
                        selectedTool = .select
                        showingCommandPalette = false
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(maxHeight: 300)
            
            Spacer()
        }
        .frame(width: 400, height: 450)
        .background(.regularMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20)
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
        
        Task { @MainActor in
            ledWall.optimizeLEDWallForVideo()
            
            // Test with a color first to ensure the material system works
            ledWall.testLEDWallWithColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1)) // Green test
            
            // Wait a moment, then start actual feed
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.startActualFeedUpdates(for: ledWall, feedID: feedID, cameraFeed: cameraFeed)
            }
        }
    }
    
    private func startActualFeedUpdates(for ledWall: StudioObject, feedID: UUID, cameraFeed: CameraFeed) {
        let updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { timer in
            Task { @MainActor in
                guard ledWall.connectedCameraFeedID == feedID,
                      ledWall.isDisplayingCameraFeed else {
                    print("🛑 Stopping timer - connection no longer valid for: \(ledWall.name)")
                    timer.invalidate()
                    return
                }
                
                guard let activeFeed = self.cameraFeedManager.activeFeeds.first(where: { $0.id == feedID }),
                      activeFeed.connectionStatus == .connected else {
                    print("⚠️ Feed no longer active, stopping updates for: \(ledWall.name)")
                    timer.invalidate()
                    return
                }
                
                var updated = false
                
                if let nsImage = activeFeed.previewNSImage {
                    ledWall.updateCameraFeedContent(nsImage: nsImage)
                    updated = true
                } else if let previewImage = activeFeed.previewImage {
                    ledWall.updateCameraFeedContent(cgImage: previewImage)
                    updated = true
                } else if let pixelBuffer = activeFeed.currentFrame {
                    ledWall.updateCameraFeedContent(pixelBuffer: pixelBuffer)
                    updated = true
                }
                
                self.feedUpdateFrameCount += 1
                if self.feedUpdateFrameCount % 150 == 1 { // Every ~5 seconds at 30fps
                    print("📺 LED Wall '\(ledWall.name)' feed update #\(self.feedUpdateFrameCount)")
                    print("   - Has NSImage: \(activeFeed.previewNSImage != nil)")
                    print("   - Has CGImage: \(activeFeed.previewImage != nil)")
                    print("   - Has pixel buffer: \(activeFeed.currentFrame != nil)")
                    print("   - Updated this frame: \(updated)")
                    print("   - Feed connection status: \(activeFeed.connectionStatus.displayText)")
                    print("   - Feed frame count: \(activeFeed.frameCount)")
                    
                    print("   - Material debug: \(ledWall.debugLEDWallMaterial())")
                }
                
                if !updated && self.feedUpdateFrameCount % 150 == 1 {
                    print("⚠️ No feed update for LED wall '\(ledWall.name)':")
                    print("   - Feed has current frame: \(activeFeed.currentFrame != nil)")
                    print("   - Feed has preview image: \(activeFeed.previewImage != nil)")
                    print("   - Feed has NSImage: \(activeFeed.previewNSImage != nil)")
                    print("   - LED wall is displaying camera feed: \(ledWall.isDisplayingCameraFeed)")
                    print("   - Connected feed ID matches: \(ledWall.connectedCameraFeedID == feedID)")
                }
            }
        }
        
        print("✅ Started live feed timer for LED wall: \(ledWall.name)")
    }
    
    private func stopLiveFeedUpdates(for ledWall: StudioObject) {
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
            .mouseTracking(
                position: $currentMousePosition,
                onMouseDown: { position in
                    handleMouseDown(at: position)
                },
                onMouseUp: { position in
                    handleMouseUp(at: position)
                },
                onMouseDrag: { position in
                    handleMouseDrag(to: position)
                }
            )
            .onAppear {
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
        let selectedObjs = getSelectedStudioObjects()
        guard !selectedObjs.isEmpty else { 
            print("⚠️ No objects selected for grab mode")
            keyboardFeedback.showFeedback("⚠️ No objects selected", color: .orange)
            return 
        }
        
        print("🎯 Starting grab mode for \(selectedObjs.count) objects")
        selectedTool = .select
        transformController.startTransform(.move, objects: selectedObjs, startPoint: .zero, scene: studioManager.scene)
        transformController.setAxis(.free)
        
        print("💡 Grab mode active - press X/Y/Z to constrain axis, then click and drag")
    }
    
    private func startRotateMode() {
        let selectedObjs = getSelectedStudioObjects()
        guard !selectedObjs.isEmpty else { 
            print("⚠️ No objects selected for rotate mode")
            keyboardFeedback.showFeedback("⚠️ No objects selected", color: .orange)
            return 
        }
        
        print("🔄 Starting rotate mode for \(selectedObjs.count) objects")
        selectedTool = .select
        transformController.startTransform(.rotate, objects: selectedObjs, startPoint: .zero, scene: studioManager.scene)
        transformController.setAxis(.free)
        
        print("💡 Rotate mode active - press X/Y/Z to constrain axis, then click and drag")
    }
    
    private func startDistanceBasedScaleMode() {
        let selectedObjs = getSelectedStudioObjects()
        guard !selectedObjs.isEmpty else { 
            print("⚠️ No objects selected for distance-based scaling")
            keyboardFeedback.showFeedback("⚠️ No objects selected", color: .orange)
            return 
        }
        
        print("📏 Starting distance-based scale mode for \(selectedObjs.count) objects")
        selectedTool = .select
        isTrackingCursor = true
        
        transformController.startDistanceBasedScaling(selectedObjs, startPoint: currentMousePosition, scene: studioManager.scene)
        
        print("💡 Distance scaling active - move cursor closer/farther to scale, Enter to confirm")
    }
    
    private func setTransformAxis(_ axis: TransformController.TransformAxis) {
        let selectedObjs = getSelectedStudioObjects()
        
        if transformController.isActive {
            transformController.setAxis(axis)
            print("🎯 Set transform axis to: \(axis.label)")
        } else if !selectedObjs.isEmpty {
            transformController.startTransform(.move, objects: selectedObjs, startPoint: .zero, scene: studioManager.scene)
            transformController.setAxis(axis)
            print("🎯 Started grab mode with axis: \(axis.label)")
        } else {
            print("⚠️ No objects selected for axis constraint")
            keyboardFeedback.showFeedback("⚠️ No objects selected", color: .orange)
        }
    }
    
    private func confirmTransform() {
        if transformController.isActive {
            print("✅ Confirming transform")
            transformController.confirmTransform()
        }
    }
    
    private func cancelTransform() {
        if transformController.isActive {
            print("❌ Cancelling transform")
            transformController.cancelTransform()
        }
    }
    
    private func getSelectedStudioObjects() -> [StudioObject] {
        return studioManager.studioObjects.filter { selectedObjects.contains($0.id) }
    }
    
    private func duplicateSelectedObjects() {
        let selectedObjs = getSelectedStudioObjects()
        guard !selectedObjs.isEmpty else {
            keyboardFeedback.showFeedback("⚠️ No objects selected to duplicate", color: .orange)
            return
        }
        
        var newSelection: Set<UUID> = []
        
        for object in selectedObjs {
            let offset: Float = 2.0
            let newPosition = SCNVector3(
                object.position.x + CGFloat(offset),
                object.position.y,
                object.position.z + CGFloat(offset)
            )
            
            let duplicate = StudioObject(name: "\(object.name) Copy", type: object.type, position: newPosition)
            duplicate.rotation = object.rotation
            duplicate.scale = object.scale
            
            if let geometry = object.node.geometry?.copy() as? SCNGeometry {
                duplicate.node.geometry = geometry
                if let materials = object.node.geometry?.materials {
                    duplicate.node.geometry?.materials = materials.map { $0.copy() as! SCNMaterial }
                }
            }
            
            studioManager.studioObjects.append(duplicate)
            studioManager.scene.rootNode.addChildNode(duplicate.node)
            duplicate.setupHighlightAfterGeometry()
            
            newSelection.insert(duplicate.id)
        }
        
        selectedObjects = newSelection
        keyboardFeedback.showFeedback("📋 Duplicated \(selectedObjs.count) object(s)", color: .green)
    }
    
    // MARK: - Actions
    
    private func handleObjectDrop(_ asset: any StudioAsset, at dropPoint: CGPoint) {
        print("🎯 Object drop initiated: \(asset.name)")
    }
    
    private func handleAddObject(_ toolType: StudioTool, _ asset: any StudioAsset) {
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
        case let stagingAsset as StagingAsset:
            studioManager.addStagingEquipment(from: stagingAsset, at: randomPos)
        case let setPieceAsset as SetPieceAsset:
            studioManager.addSetPiece(from: setPieceAsset, at: randomPos)
        default:
            print("⚠️ Unknown asset type: \(type(of: asset))")
        }
        
        selectedTool = .select 
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
        case .staging: return .gray
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
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Camera Management:")
                    .font(.caption.weight(.semibold))
                
                if cameraFeedManager.availableDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Click 'Discover Cameras' to find devices")
                        Text("Connect feeds to LED walls for content")
                    }
                    .font(.caption2)
                    .foregroundColor(.blue.opacity(0.8))
                    
                    Button("Discover Cameras") {
                        discoverCamerasForVirtual()
                    }
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
                } else {
                    Text("✅ \(cameraFeedManager.availableDevices.count) camera(s) available")
                        .font(.caption2)
                        .foregroundColor(.green)
                    
                    if cameraFeedManager.activeFeeds.count > 0 {
                        Text("📺 \(cameraFeedManager.activeFeeds.count) feed(s) active")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.horizontal)
            
            Divider()
                .padding(.vertical, 8)
            
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
            
            Button("Debug Cameras") {
                debugCameras()
            }
            .padding()
            
            Button("Test Camera Access") {
                Task {
                    await CameraDebugHelper.testSimpleCameraCapture()
                }
            }
            .padding(.horizontal)
            .font(.caption)
            .foregroundColor(.blue)
            
            Button("Test LED Wall Materials") {
                testLEDWallMaterials()
            }
            .padding(.horizontal)
            .font(.caption)
            .foregroundColor(.yellow)
            
            Button("Simple Camera Test") {
                let testWindow = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
                    styleMask: [.titled, .closable, .resizable],
                    backing: .buffered,
                    defer: false
                )
                testWindow.title = "Simple Camera Test"
                testWindow.contentView = NSHostingView(rootView: SimpleCameraTestView())
                testWindow.center()
                testWindow.makeKeyAndOrderFront(nil)
            }
            .padding(.horizontal)
            .font(.caption)
            .foregroundColor(.green)
            
            Button("Run Full Diagnostic") {
                Task {
                    await CameraSessionDiagnostic.runFullDiagnostic()
                }
            }
            .padding(.horizontal)
            .font(.caption)
            .foregroundColor(.red)
            
            Button("Advanced Debug") {
                let debugWindow = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                    styleMask: [.titled, .closable, .resizable],
                    backing: .buffered,
                    defer: false
                )
                debugWindow.title = "Advanced Camera Debug"
                debugWindow.contentView = NSHostingView(rootView: AdvancedCameraDebugView())
                debugWindow.center()
                debugWindow.makeKeyAndOrderFront(nil)
            }
            .padding(.horizontal)
            .font(.caption)
            .foregroundColor(.purple)
            
            Button("State Monitor") {
                let monitorWindow = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                    styleMask: [.titled, .closable, .resizable],
                    backing: .buffered,
                    defer: false
                )
                monitorWindow.title = "Camera State Monitor"
                monitorWindow.contentView = NSHostingView(rootView: CameraStateMonitorView(cameraFeedManager: cameraFeedManager))
                monitorWindow.center()
                monitorWindow.makeKeyAndOrderFront(nil)
            }
            .padding(.horizontal)
            .font(.caption)
            .foregroundColor(.cyan)
            
            // Add test LED wall materials button
            Button("Test LED Wall Materials") {
                testLEDWallMaterials()
            }
            .padding(.horizontal)
            .font(.caption)
            .foregroundColor(.yellow)
        }
        .background(.regularMaterial)
    }
    
    private var rightPanel: some View {
        VStack(spacing: 0) {
            ObjectListPanel(selectedObjects: $selectedObjects)
                .environmentObject(studioManager)
            
            LEDWallStatusPanel(cameraFeedManager: cameraFeedManager)
                .environmentObject(studioManager)
            
            Spacer(minLength: 16)
            
            if !selectedObjects.isEmpty {
                propertiesPanel
            }
        }
    }
    
    private var propertiesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            propertiesPanelHeader
            
            Divider()
                .background(.white.opacity(0.2))
            
            propertiesPanelContent
        }
        .background(.regularMaterial)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private var propertiesPanelHeader: some View {
        HStack {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            
            Text("Properties")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.black.opacity(0.8))
    }
    
    private var propertiesPanelContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let firstSelected = getSelectedStudioObjects().first {
                    transformSection(for: firstSelected)
                    objectInfoSection(for: firstSelected)
                    
                    if selectedObjects.count > 1 {
                        multiSelectionSection
                    }
                }
            }
            .padding(12)
        }
        .background(.black.opacity(0.4))
    }
    
    private func transformSection(for object: StudioObject) -> some View {
        PropertySection(title: "Transform") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Position:")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 60, alignment: .leading)
                    
                    let pos = object.position
                    Text("(\(pos.x, specifier: "%.2f"), \(pos.y, specifier: "%.2f"), \(pos.z, specifier: "%.2f"))")
                        .font(.caption.monospaced())
                        .foregroundColor(.white.opacity(0.8))
                    
                    Spacer()
                }
                
                HStack {
                    Text("Rotation:")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 60, alignment: .leading)
                    
                    let rot = object.rotation
                    let xDeg = Float(rot.x) * 180.0 / Float.pi
                    let yDeg = Float(rot.y) * 180.0 / Float.pi
                    let zDeg = Float(rot.z) * 180.0 / Float.pi
                    Text("(\(xDeg, specifier: "%.1f")°, \(yDeg, specifier: "%.1f")°, \(zDeg, specifier: "%.1f")°)")
                        .font(.caption.monospaced())
                        .foregroundColor(.white.opacity(0.8))
                    
                    Spacer()
                }
                
                HStack {
                    Text("Scale:")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 60, alignment: .leading)
                    
                    let scale = object.scale
                    Text("(\(scale.x, specifier: "%.2f"), \(scale.y, specifier: "%.2f"), \(scale.z, specifier: "%.2f"))")
                        .font(.caption.monospaced())
                        .foregroundColor(.white.opacity(0.8))
                    
                    Spacer()
                }
            }
        }
    }
    
    private func objectInfoSection(for object: StudioObject) -> some View {
        PropertySection(title: "Object Info") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Name:")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 60, alignment: .leading)
                    
                    Text(object.name)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    
                    Spacer()
                }
                
                HStack {
                    Text("Type:")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 60, alignment: .leading)
                    
                    HStack(spacing: 4) {
                        Image(systemName: object.type.icon)
                            .foregroundColor(colorForObjectType(object.type))
                        Text(object.type.name)
                    }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    
                    Spacer()
                }
                
                HStack {
                    Text("Visible:")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.1))
                        .frame(width: 60, alignment: .leading)
                    
                    Image(systemName: object.isVisible ? "eye" : "eye.slash")
                        .foregroundColor(object.isVisible ? .green : .red)
                        .font(.caption)
                    
                    Spacer()
                }
                
                HStack {
                    Text("Locked:")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 60, alignment: .leading)
                    
                    Image(systemName: object.isLocked ? "lock.fill" : "lock.open")
                        .foregroundColor(object.isLocked ? .orange : .gray)
                        .font(.caption)
                    
                    Spacer()
                }
            }
        }
    }
    
    private var multiSelectionSection: some View {
        PropertySection(title: "Multi-Selection") {
            Text("+ \(selectedObjects.count - 1) more objects")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
    }
    
    // MARK: - Mouse Event Handlers
    
    private func handleMouseDown(at position: CGPoint) {
        print("🖱️ Mouse down at: \(position)")
        
        if transformController.isDistanceScaling {
            print("📏 Mouse down during distance scaling")
        }
    }
    
    private func handleMouseUp(at position: CGPoint) {
        print("🖱️ Mouse up at: \(position)")
        
        if transformController.isDistanceScaling {
            print("📏 Mouse up during distance scaling")
        }
    }
    
    private func handleMouseDrag(to position: CGPoint) {
        if transformController.isDistanceScaling {
            transformController.updateDistanceBasedScaling(currentMousePos: position)
        }
    }
    
    // MARK: - Camera Management (Updated)
    
    private func discoverCamerasForVirtual() {
        Task {
            print("🎬 Virtual Production: Discovering available cameras...")
            await cameraFeedManager.getAvailableDevices()
            let devices = cameraFeedManager.availableDevices
            print("📹 Virtual Production: Found \(devices.count) camera devices available for LED wall connections")
            
            for device in devices {
                print("  📱 Available: \(device.displayName) (\(device.deviceType.rawValue))")
            }
        }
    }
    
    // Add this method to test LED wall material updates
    private func testLEDWallMaterials() {
        let ledWalls = studioManager.studioObjects.filter { $0.type == .ledWall }
        
        for (index, ledWall) in ledWalls.enumerated() {
            let testColors: [CGColor] = [
                CGColor(red: 1, green: 0, blue: 0, alpha: 1), // Red
                CGColor(red: 0, green: 1, blue: 0, alpha: 1), // Green
                CGColor(red: 0, green: 0, blue: 1, alpha: 1), // Blue
                CGColor(red: 1, green: 1, blue: 0, alpha: 1)  // Yellow
            ]
            
            let color = testColors[index % testColors.count]
            ledWall.testLEDWallWithColor(color)
            
            print("🎨 Testing LED wall '\(ledWall.name)' with color at index \(index)")
            print("   Debug info: \(ledWall.debugLEDWallMaterial())")
        }
    }
}

// MARK: - Scene View (Simplified)

enum CameraMode: String, CaseIterable, Hashable {
    case orbit, pan, fly}

// Helper views for properties panel
struct PropertySection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.7))
                .textCase(.uppercase)
            
            content
        }
    }
}

struct PropertyRow<Content: View>: View {
    let label: String
    let content: Content
    
    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }
    
    var body: some View {
        HStack {
            Text(label + ":")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 60, alignment: .leading)
            
            content
            
            Spacer()
        }
    }
}

// Helper views for command palette
struct CommandPaletteItem: View {
    let title: String
    let shortcut: String
    let icon: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 20)
                
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text(shortcut)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.1))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? .white.opacity(0.1) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}
