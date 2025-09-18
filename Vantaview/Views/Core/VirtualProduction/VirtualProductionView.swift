import SwiftUI
import SceneKit

struct VirtualProductionView: View {
    @EnvironmentObject var studioManager: VirtualStudioManager
    
    // Core States
    @State private var selectedTool: StudioTool = .select
    @State private var selectedObject: StudioObject?
    @State private var lastWorldPos: SCNVector3 = SCNVector3(0,0,0)
    
    // Transform Controller for Blender-style interactions
    @StateObject private var transformController = TransformController()
    
    @State private var cameraMode: CameraMode = .orbit
    @State private var showingCommandPalette = false
    @State private var showingLeftPanel = true
    @State private var showingRightPanel = true
    @State private var searchText = ""
    @State private var selectedObjects: Set<UUID> = []
    @State private var showingAddMenu = false
    @State private var showingDraggableMenu = true 
    @State private var showingObjectBrowser = true 
    
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
    private let spacing1: CGFloat = 4   
    private let spacing2: CGFloat = 8   
    private let spacing3: CGFloat = 16  
    private let spacing4: CGFloat = 24  
    private let spacing5: CGFloat = 32  

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
                    print(" Received request to show camera feed modal for: \(ledWall.name)")
                    selectedLEDWallForFeed = ledWall
                    showingCameraFeedModal = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .ledWallCameraFeedDisconnected)) { notification in
                if let ledWall = notification.object as? StudioObject {
                    print(" LED Wall camera feed disconnected: \(ledWall.name)")
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
                    keyboardFeedback.showFeedback(" Scale Locked", color: .green)
                    isTrackingCursor = false
                } else {
                    confirmTransform()
                    keyboardFeedback.showFeedback(" Transform Confirmed", color: .green)
                }
                return .handled
            }
            .onKeyPress(.escape) { 
                if transformController.isDistanceScaling {
                    transformController.cancelDistanceScaling()
                    keyboardFeedback.showFeedback(" Scale Cancelled", color: .red)
                    isTrackingCursor = false
                } else {
                    cancelTransform()
                    keyboardFeedback.showFeedback(" Transform Cancelled", color: .red)
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
                studioManager.testSelectionSystem()
                keyboardFeedback.showFeedback("T - Testing Selection System", color: .yellow)
                return .handled
            }
            .onKeyPress("h") {
                studioManager.resetObjectHighlights()
                keyboardFeedback.showFeedback("H - Reset Highlights", color: .cyan)
                return .handled
            }
            .onChange(of: selectedTool) { _, newValue in
                if newValue == .select { selectedObject = nil }
            }
            .onAppear {
                print(" Virtual Production: Ready - cameras available for user selection")
            }
            // Arrow key support for fine object positioning
            .onKeyPress(.upArrow) {
                if transformController.isActive {
                    transformController.nudgeObjects(.up)
                    
                    switch transformController.axis {
                    case .z:
                        keyboardFeedback.showFeedback(" Nudge Forward (Z+)", color: .blue)
                    case .y, .free:
                        keyboardFeedback.showFeedback(" Nudge Up (Y+)", color: .green)
                    case .x:
                        keyboardFeedback.showFeedback(" No movement (X-axis only)", color: .orange)
                    }
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.downArrow) {
                if transformController.isActive {
                    transformController.nudgeObjects(.down)
                    
                    switch transformController.axis {
                    case .z:
                        keyboardFeedback.showFeedback(" Nudge Backward (Z-)", color: .blue)
                    case .y, .free:
                        keyboardFeedback.showFeedback(" Nudge Down (Y-)", color: .green)
                    case .x:
                        keyboardFeedback.showFeedback(" No movement (X-axis only)", color: .orange)
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
                        keyboardFeedback.showFeedback(" Nudge Left (X-)", color: .red)
                    default:
                        keyboardFeedback.showFeedback(" No movement (axis constrained)", color: .orange)
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
                        keyboardFeedback.showFeedback(" Nudge Right (X+)", color: .red)
                    default:
                        keyboardFeedback.showFeedback(" No movement (axis constrained)", color: .orange)
                    }
                    return .handled
                }
                return .ignored
            }
            // Add support for forward/backward with Shift+Up/Down
            .onKeyPress(.upArrow) {
                if NSEvent.modifierFlags.contains(.shift) && transformController.isActive {
                    transformController.nudgeObjects(.forward)
                    keyboardFeedback.showFeedback(" Nudge Forward", color: .blue)
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.downArrow) {
                if NSEvent.modifierFlags.contains(.shift) && transformController.isActive {
                    transformController.nudgeObjects(.backward)
                    keyboardFeedback.showFeedback(" Nudge Backward", color: .blue)
                    return .handled
                }
                return .ignored
            }
            // Delete key support - ENHANCED VERSION
            .onKeyPress(.delete) {
                let selectedObjs = getSelectedStudioObjects()
                if !selectedObjs.isEmpty {
                    let lockedObjects = selectedObjs.filter { $0.isLocked }
                    let unlocked = selectedObjs.filter { !$0.isLocked }
                    
                    if !lockedObjects.isEmpty {
                        keyboardFeedback.showFeedback(" Cannot delete  locked object(s)", color: .orange)
                        print(" Blocked deletion of locked objects: \(lockedObjects.map { $0.name })")
                    }
                    
                    if !unlocked.isEmpty {
                        for obj in unlocked {
                            studioManager.deleteObject(obj)
                            selectedObjects.remove(obj.id)
                        }
                        keyboardFeedback.showFeedback(" Deleted  object(s)", color: .red)
                    }
                } else {
                    keyboardFeedback.showFeedback(" No objects selected to delete", color: .orange)
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
            backgroundViewport
            
            BlenderStyleToolbar(
                selectedTool: $selectedTool,
                showingAddMenu: $showingAddMenu,
                onAddObject: handleAddObject
            )
            
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
            
            if showingObjectBrowser {
                DraggableResizableWindow(title: "Studio Objects") {
                    VisibleObjectBrowser()
                        .environmentObject(studioManager) 
                }
            }
            
            KeyboardFeedbackOverlay(controller: keyboardFeedback)
                .zIndex(100) 
            
            floatingOverlays
            
            TransformOverlay(
                controller: transformController,
                selectedObjects: getSelectedStudioObjects()
            )
            .zIndex(20) 
        }
    }
    
    @ViewBuilder
    private var floatingOverlays: some View {
        VStack {
            HStack {
                Spacer()
                PerformanceOverlay()
            }
            Spacer()
        }
        .padding()
        .allowsHitTesting(false) // Don't block interactions
        
        if showingCommandPalette {
            commandPalette
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95).combined(with: .opacity),
                    removal: .scale(scale: 0.95).combined(with: .opacity)
                ))
        }
        
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
    
    // MARK: - Command Palette
    
    private var commandPalette: some View {
        VStack(spacing: 0) {
            // Enhanced header with glassmorphism
            HStack(spacing: 12) {
                Image(systemName: "command.circle.fill")
                    .font(.system(.title2, design: .default, weight: .semibold))
                    .foregroundStyle(.white.gradient)
                // Removed this line to keep only systemName, without extra styling: Image(systemName: "command.circle.fill")
                Text("Command Palette")
                    .font(.system(.title2, design: .default, weight: .semibold))
                    .foregroundStyle(.white)
                // Removed this line to keep the default Spacer without extra styling: Spacer()
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                        showingCommandPalette = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(.title3, design: .default, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .scaleEffect(1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: false)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 0.5)
            )
            
            // Search field with modern styling
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(.callout, design: .default, weight: .medium))
                    .foregroundStyle(.secondary)
                // Removed this line to keep the default TextField without background styling: TextField Search styles 
                TextField("Search commands...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .default, weight: .regular))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 0.5)
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            
            // Command list with enhanced styling
            ScrollView {
                VStack(spacing: 8) {
                    CommandPaletteItem(
                        title: "Add LED Wall",
                        shortcut: "L",
                        icon: "tv.fill"
                    ) {
                        selectedTool = .ledWall
                        showingCommandPalette = false
                    }
                    
                    CommandPaletteItem(
                        title: "Add Camera",
                        shortcut: "C",
                        icon: "video.fill"
                    ) {
                        selectedTool = .camera
                        showingCommandPalette = false
                    }
                    
                    CommandPaletteItem(
                        title: "Add Light",
                        shortcut: "⇧L",
                        icon: "lightbulb.fill"
                    ) {
                        selectedTool = .light
                        showingCommandPalette = false
                    }
                    
                    CommandPaletteItem(
                        title: "Toggle Object Browser",
                        shortcut: "B",
                        icon: "cube.box.fill"
                    ) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showingObjectBrowser.toggle()
                        }
                        showingCommandPalette = false
                    }
                    
                    CommandPaletteItem(
                        title: "Select Tool",
                        shortcut: "V",
                        icon: "cursorarrow"
                    ) {
                        selectedTool = .select
                        showingCommandPalette = false
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .frame(maxHeight: 300)
            .scrollIndicators(.hidden)
        }
        .frame(width: 450, height: 500)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 24, x: 0, y: 12)
    }
    
    private var backgroundViewport: some View {
        ZStack {
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
                    print(" Mouse down at: \(position)")
                    // Removed this line to keep the default mouseDown event without distance scaling check: if transformController.isDistanceScaling 
                    if transformController.isDistanceScaling {
                        print(" Mouse down during distance scaling")
                    }
                },
                onMouseUp: { position in
                    print(" Mouse up at: \(position)")
                    // Removed this line to keep the default mouseUp event without distance scaling check: if transformController.isDistanceScaling 
                    if transformController.isDistanceScaling {
                        print(" Mouse up during distance scaling")
                    }
                },
                onMouseDrag: { position in
                    if transformController.isDistanceScaling {
                        transformController.updateDistanceBasedScaling(currentMousePos: position)
                    }
                }
            )
            .onAppear {
            }
            
            Viewport3DCompass(
                cameraAzimuth: $cameraAzimuth,
                cameraElevation: $cameraElevation,
                cameraRoll: $cameraRoll
            )
        }
    }
    
    private func startGrabMode() {
        let selectedObjs = getSelectedStudioObjects()
        guard !selectedObjs.isEmpty else { 
            print(" No objects selected for grab mode")
            keyboardFeedback.showFeedback(" No objects selected", color: .orange)
            return 
        }
        
        print(" Starting grab mode for \(selectedObjs.count) objects")
        selectedTool = .select
        transformController.startTransform(.move, objects: selectedObjs, startPoint: .zero, scene: studioManager.scene)
        transformController.setAxis(.free)
        
        print(" Grab mode active - press X/Y/Z to constrain axis, then click and drag")
    }
    
    private func startRotateMode() {
        let selectedObjs = getSelectedStudioObjects()
        guard !selectedObjs.isEmpty else { 
            print(" No objects selected for rotate mode")
            keyboardFeedback.showFeedback(" No objects selected", color: .orange)
            return 
        }
        
        print(" Starting rotate mode for \(selectedObjs.count) objects")
        selectedTool = .select
        transformController.startTransform(.rotate, objects: selectedObjs, startPoint: .zero, scene: studioManager.scene)
        transformController.setAxis(.free)
        
        print(" Rotate mode active - press X/Y/Z to constrain axis, then click and drag")
    }
    
    private func startDistanceBasedScaleMode() {
        let selectedObjs = getSelectedStudioObjects()
        guard !selectedObjs.isEmpty else { 
            print(" No objects selected for distance-based scaling")
            keyboardFeedback.showFeedback(" No objects selected", color: .orange)
            return 
        }
        
        print(" Starting distance-based scale mode for \(selectedObjs.count) objects")
        selectedTool = .select
        isTrackingCursor = true
        
        transformController.startDistanceBasedScaling(selectedObjs, startPoint: currentMousePosition, scene: studioManager.scene)
        
        print(" Distance scaling active - move cursor closer/farther to scale, Enter to confirm")
    }
    
    private func setTransformAxis(_ axis: TransformController.TransformAxis) {
        let selectedObjs = getSelectedStudioObjects()
        
        if transformController.isActive {
            transformController.setAxis(axis)
            print(" Set transform axis to: \(axis.label)")
        } else if !selectedObjs.isEmpty {
            transformController.startTransform(.move, objects: selectedObjs, startPoint: .zero, scene: studioManager.scene)
            transformController.setAxis(axis)
            print(" Started grab mode with axis: \(axis.label)")
        } else {
            print(" No objects selected for axis constraint")
            keyboardFeedback.showFeedback(" No objects selected", color: .orange)
        }
    }
    
    private func confirmTransform() {
        if transformController.isActive {
            print(" Confirming transform")
            transformController.confirmTransform()
        }
    }
    
    private func cancelTransform() {
        if transformController.isActive {
            print(" Cancelling transform")
            transformController.cancelTransform()
        }
    }
    
    private func getSelectedStudioObjects() -> [StudioObject] {
        return studioManager.studioObjects.filter { selectedObjects.contains($0.id) }
    }
    
    private func duplicateSelectedObjects() {
        let selectedObjs = getSelectedStudioObjects()
        guard !selectedObjs.isEmpty else {
            keyboardFeedback.showFeedback(" No objects selected to duplicate", color: .orange)
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
        keyboardFeedback.showFeedback(" Duplicated \(selectedObjs.count) object(s)", color: .green)
    }
    
    private func handleObjectDrop(_ asset: any StudioAsset, at dropPoint: CGPoint) {
        print(" Object drop initiated: \(asset.name)")
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
            print(" Unknown asset type: \(type(of: asset))")
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
    
    private func refreshCameras() {
        Task {
            print(" Manually refreshing cameras...")
            await cameraFeedManager.forceRefreshDevices()
            
            let devices = cameraFeedManager.availableDevices
            print(" Virtual Production: Found \(devices.count) camera devices available for LED wall connections")
            
            for device in devices {
                print("  Available: \(device.displayName) (\(device.deviceID))")
            }
        }
    }
    
    private func debugCameras() {
        Task {
            print(" Running camera debug session...")
            await cameraFeedManager.debugCameraDetection()
        }
    }
    
    private func debugCameraConnection() {
        print("🔧 DEBUG: Camera connection diagnostics")
        
        Task {
            let devices = await productionManager.cameraFeedManager.getAvailableDevices()
            print("📱 Available devices (\(devices.count)):")
            for device in devices {
                print("  Available: \(device.displayName) (ID: \(device.deviceID))")
            }
        }
        
        print("📡 Active feeds (\(productionManager.cameraFeedManager.activeFeeds.count)):")
        for feed in productionManager.cameraFeedManager.activeFeeds {
            print("  Feed: \(feed.device.displayName) - Status: \(feed.connectionStatus.displayText)")
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

    private var leftPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(.title3, design: .default, weight: .semibold))
                    .foregroundStyle(.blue.gradient)
                
                Text("Studio Tools")
                    .font(.system(.title3, design: .default, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        statsCard("Selected Tool", selectedTool.name, .blue, "cursorarrow")
                        statsCard("Objects", "\(studioManager.studioObjects.count)", .green, "cube.box.fill")
                        statsCard("Cameras", "\(studioManager.virtualCameras.count)", .orange, "video.fill")
                        statsCard("Camera Feeds", "\(cameraFeedManager.activeFeeds.count)", .purple, "camera.tv")
                    }
                    .padding(.horizontal, 12)
                    
                    PropertySection(title: "Camera Management") {
                        VStack(alignment: .leading, spacing: 12) {
                            if cameraFeedManager.availableDevices.isEmpty {
                                VStack(spacing: 8) {
                                    Text("Click 'Discover Cameras' to find devices")
                                        .font(.system(.footnote, design: .default, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    
                                    Text("Connect feeds to LED walls for content")
                                        .font(.system(.caption, design: .default, weight: .regular))
                                        .foregroundStyle(.tertiary)
                                    
                                    modernButton("Discover Cameras", icon: "magnifyingglass", color: .blue) {
                                        discoverCamerasForVirtual()
                                    }
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                        Text("\(cameraFeedManager.availableDevices.count) camera(s) available")
                                            .font(.system(.footnote, design: .default, weight: .medium))
                                            .foregroundStyle(.primary)
                                    }
                                    
                                    if cameraFeedManager.activeFeeds.count > 0 {
                                        HStack(spacing: 6) {
                                            Image(systemName: "tv.fill")
                                                .foregroundStyle(.blue)
                                            Text("\(cameraFeedManager.activeFeeds.count) feed(s) active")
                                                .font(.system(.footnote, design: .default, weight: .medium))
                                                .foregroundStyle(.primary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    
                    PropertySection(title: "Shortcuts") {
                        VStack(spacing: 8) {
                            shortcutRow("V", "Select")
                            shortcutRow("L", "LED Wall")
                            shortcutRow("C", "Camera")
                            shortcutRow("B", "Object Browser")
                            shortcutRow("D", "Drag Menu")
                            shortcutRow("⇧L", "Light")
                            shortcutRow("⇧A", "Add Menu")
                        }
                    }
                    .padding(.horizontal, 12)
                    
                    if !selectedObjects.isEmpty {
                        PropertySection(title: "Selected Objects") {
                            VStack(spacing: 8) {
                                ForEach(Array(selectedObjects.prefix(3)), id: \.self) { objectID in
                                    if let object = studioManager.studioObjects.first(where: { $0.id == objectID }) {
                                        selectedObjectRow(object)
                                    }
                                }
                                
                                if selectedObjects.count > 3 {
                                    Text("... and \(selectedObjects.count - 3) more")
                                        .font(.system(.caption, design: .default, weight: .regular))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    
                    PropertySection(title: "Live Production Feeds") {
                        VStack(alignment: .leading, spacing: 8) {
                            if cameraFeedManager.activeFeeds.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("No active camera feeds")
                                        .font(.system(.footnote, design: .default, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    Text("Start cameras in Live Production mode")
                                        .font(.system(.caption, design: .default, weight: .regular))
                                        .foregroundStyle(.tertiary)
                                }
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(cameraFeedManager.activeFeeds.prefix(3)) { feed in
                                        activeFeedRow(feed)
                                    }
                                    
                                    if cameraFeedManager.activeFeeds.count > 3 {
                                        Text("... +\(cameraFeedManager.activeFeeds.count - 3) more")
                                            .font(.system(.caption, design: .default, weight: .regular))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    
                                    Text(" Right-click LED walls → 'Connect to Camera'")
                                        .font(.system(.caption, design: .default, weight: .regular))
                                        .foregroundColor(.blue)
                                        .padding(.top, 4)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    
                    PropertySection(title: "Debug Tools") {
                        VStack(spacing: 8) {
                            modernButton("Debug Cameras", icon: "camera.metering.unknown", color: .purple) {
                                debugCameras()
                            }
                            
                            modernButton("Quick Camera Diagnostic", icon: "stethoscope.circle", color: .red) {
                                let diagnosticWindow = NSWindow(
                                    contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
                                    styleMask: [.titled, .closable, .resizable],
                                    backing: .buffered,
                                    defer: false
                                )
                                diagnosticWindow.title = "Quick Camera Diagnostic"
                                diagnosticWindow.contentView = NSHostingView(rootView: QuickCameraTestView())
                                diagnosticWindow.center()
                                diagnosticWindow.makeKeyAndOrderFront(nil)
                            }
                            
                            modernButton("Test Camera Access", icon: "camera.circle", color: .blue) {
                                Task {
                                    await CameraDebugHelper.testSimpleCameraCapture()
                                }
                            }
                            
                            modernButton("Test LED Wall Materials", icon: "tv.circle", color: .yellow) {
                                testLEDWallMaterials()
                            }
                            
                            modernButton("Open Camera Debug", icon: "terminal", color: .purple) {
                                let debugWindow = NSWindow(
                                    contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                                    styleMask: [.titled, .closable, .resizable],
                                    backing: .buffered,
                                    defer: false
                                )
                                debugWindow.title = "Camera Debug Console"
                                debugWindow.contentView = NSHostingView(rootView: CameraDebugView())
                                debugWindow.center()
                                debugWindow.makeKeyAndOrderFront(nil)
                            }
                            
                            modernButton("Simple Camera Test", icon: "viewfinder.circle", color: .green) {
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
                            
                            modernButton("Run Full Diagnostic", icon: "stethoscope", color: .red) {
                                Task {
                                    await CameraSessionDiagnostic.runFullDiagnostic()
                                }
                            }
                            
                            modernButton("Advanced Debug", icon: "cpu", color: .purple) {
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
                            
                            modernButton("State Monitor", icon: "gauge.with.dots.needle.67percent", color: .cyan) {
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
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxHeight: .infinity)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
    }
    
    private var rightPanel: some View {
        VStack(spacing: 16) {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .font(.system(.title3, design: .default, weight: .semibold))
                        .foregroundStyle(.green.gradient)
                    
                    Text("Scene Objects")
                        .font(.system(.title3, design: .default, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
                
                ObjectListPanel(selectedObjects: $selectedObjects)
                    .environmentObject(studioManager) 
                    .padding(.top, 12)
            }
            
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "tv.and.hifispeaker.fill")
                        .font(.system(.title3, design: .default, weight: .semibold))
                        .foregroundStyle(.blue.gradient)
                    
                    Text("LED Walls")
                        .font(.system(.title3, design: .default, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
                
                LEDWallStatusPanel(cameraFeedManager: cameraFeedManager)
                    .environmentObject(studioManager)
                    .padding(.top, 12)
            }
            
            Spacer(minLength: 16)
            
            if !selectedObjects.isEmpty {
                enhancedPropertiesPanel
            }
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
    }
    
    private var enhancedPropertiesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(.title3, design: .default, weight: .semibold))
                    .foregroundStyle(.purple.gradient)
                
                Text("Properties")
                    .font(.system(.title3, design: .default, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 0.5)
            )
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let firstSelected = getSelectedStudioObjects().first {
                        enhancedTransformSection(for: firstSelected)
                        enhancedObjectInfoSection(for: firstSelected)
                        
                        if selectedObjects.count > 1 {
                            enhancedMultiSelectionSection
                        }
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 0.5)
            )
        }
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
    
    private func enhancedTransformSection(for object: StudioObject) -> some View {
        PropertySection(title: "Transform") {
            VStack(alignment: .leading, spacing: 8) {
                PropertyRow(label: "Position", value: (String(format: "(%.2f, %.2f, %.2f)", Float(object.position.x), Float(object.position.y), Float(object.position.z))), icon: "location.fill", color: Color.blue)
                PropertyRow(label: "Rotation", value: (String(format: "(%.1f°, %.1f°, %.1f°)", Float(object.rotation.x) * 180.0 / Float.pi, Float(object.rotation.y) * 180.0 / Float.pi, Float(object.rotation.z) * 180.0 / Float.pi)), icon: "rotate.3d.fill", color: Color.orange)
                PropertyRow(label: "Scale", value: (String(format: "(%.2f, %.2f, %.2f)", Float(object.scale.x), Float(object.scale.y), Float(object.scale.z))), icon: "scale.3d", color: Color.green)
            }
        }
    }
    
    private func enhancedObjectInfoSection(for object: StudioObject) -> some View {
        PropertySection(title: "Object Info") {
            VStack(alignment: .leading, spacing: 8) {
                PropertyRow(label: "Name", value: object.name, icon: "textformat", color: Color.primary)
                PropertyRow(label: "Type", value: object.type.name, icon: object.type.icon, color: colorForObjectType(object.type))
                PropertyRow(label: "Visible", value: object.isVisible ? "Yes" : "No", icon: object.isVisible ? "eye.fill" : "eye.slash.fill", color: object.isVisible ? Color.green : Color.red)
                PropertyRow(label: "Locked", value: object.isLocked ? "Yes" : "No", icon: object.isLocked ? "lock.fill" : "lock.open.fill", color: object.isLocked ? Color.orange : Color.gray)
            }
        }
    }
    
    private var enhancedMultiSelectionSection: some View {
        PropertySection(title: "Multi-Selection") {
            Text("+ \(selectedObjects.count - 1) more objects")
                .font(.system(.footnote, design: .default, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
    }
    
    private struct PropertyRow: View {
        let label: String
        let value: String
        let icon: String
        let color: Color
        
        var body: some View {
            HStack {
                Text(label + ":")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 60, alignment: .leading)
                
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
            }
        }
    }
    
    private func statsCard(_ title: String, _ value: String, _ color: Color, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(.callout, design: .default, weight: .semibold))
                .foregroundStyle(color.gradient)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.caption, design: .default, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Text(value)
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        )
    }
    
    private func modernSectionCard<Content: View>(
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(color.gradient)
                
                Text(title)
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Spacer()
            }
            
            content()
        }
        .padding(16)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        )
    }
    
    private func modernButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(.caption, design: .default, weight: .medium))
                    .foregroundStyle(color)
                
                Text(title)
                    .font(.system(.caption, design: .default, weight: .medium))
                    .foregroundStyle(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                color.opacity(0.1),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(color.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: false)
    }
    
    private func shortcutRow(_ key: String, _ description: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 20)
                .background(
                    .quaternary,
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(.white.opacity(0.2), lineWidth: 0.5)
                )
            
            Text(description)
                .font(.system(.caption, design: .default, weight: .regular))
                .foregroundStyle(.secondary)
            
            Spacer()
        }
    }
    
    private func selectedObjectRow(_ object: StudioObject) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(colorForObjectType(object.type).gradient)
                .frame(width: 8, height: 8)
            
            Text(object.name)
                .font(.system(.caption, design: .default, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            
            Spacer()
        }
    }
    
    private func activeFeedRow(_ feed: CameraFeed) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(feed.connectionStatus.color.gradient)
                .frame(width: 6, height: 6)
            
            Text(feed.device.displayName)
                .font(.system(.caption, design: .default, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            
            Spacer()
            
            if feed.previewImage != nil {
                Text("LIVE")
                    .font(.system(.caption2, design: .default, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        .green.gradient,
                        in: Capsule()
                    )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            feed.id == cameraFeedManager.selectedFeedForLiveProduction?.id 
                ? .blue.opacity(0.1) 
                : .clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }
    
    private func refreshCameraConnections() {
        Task {
            let devices = await productionManager.cameraFeedManager.getAvailableDevices()
            print("📱 Available devices (\(devices.count)):")
            for device in devices {
                print("  Available: \(device.displayName) (ID: \(device.deviceID))")
            }
        }
    }
    
    private func testLEDWallMaterials() {
        let ledWalls = studioManager.studioObjects.filter { $0.type == .ledWall }
        
        for (index, ledWall) in ledWalls.enumerated() {
            let testColors: [CGColor] = [
                CGColor(red: 1, green: 0, blue: 0, alpha: 1),
                CGColor(red: 0, green: 1, blue: 0, alpha: 1),
                CGColor(red: 0, green: 0, blue: 1, alpha: 1),
                CGColor(red: 1, green: 1, blue: 0, alpha: 1)  
            ]
            
            let color = testColors[index % testColors.count]
            ledWall.testLEDWallWithColor(color)
            
            print(" Testing LED wall '\(ledWall.name)' with color at index \(index)")
            print("   Debug info: \(ledWall.debugLEDWallMaterial())")
        }
    }
    
    private func discoverCamerasForVirtual() {
        Task {
            print(" Virtual Production: Discovering available cameras...")
            await cameraFeedManager.getAvailableDevices()
            let devices = cameraFeedManager.availableDevices
            print(" Virtual Production: Found \(devices.count) camera devices available for LED wall connections")
            
            for device in devices {
                print("  Available: \(device.displayName) (\(device.deviceID))")
            }
        }
    }
    
    private func handleCameraFeedConnection(feedID: UUID?, ledWall: StudioObject) {
        Task { @MainActor in
            if let feedID = feedID {
                // Connect the camera feed
                ledWall.connectCameraFeed(feedID)
                print(" Connected camera feed \(feedID) to LED wall: \(ledWall.name)")
                
                // Start live feed updates
                startLiveFeedUpdates(for: ledWall, feedID: feedID)
            } else {
                // Disconnect the camera feed
                ledWall.disconnectCameraFeed()
                print(" Disconnected camera feed from LED wall: \(ledWall.name)")
                
                // Stop live feed updates
                stopLiveFeedUpdates(for: ledWall)
            }
        }
    }
    
    private func startLiveFeedUpdates(for ledWall: StudioObject, feedID: UUID) {
        guard let cameraFeed = cameraFeedManager.activeFeeds.first(where: { $0.id == feedID }) else {
            print(" Camera feed not found: \(feedID)")
            return
        }
        
        print(" Starting live feed updates for LED wall: \(ledWall.name)")
        print("   - Feed device: \(cameraFeed.device.displayName)")
        print("   - Feed status: \(cameraFeed.connectionStatus.displayText)")
        
        startActualFeedUpdates(for: ledWall, feedID: feedID, cameraFeed: cameraFeed)
    }
    
    private func startActualFeedUpdates(for ledWall: StudioObject, feedID: UUID, cameraFeed: CameraFeed) {
        // PERFORMANCE: Keep at 30fps for smoother LED wall updates
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { timer in
            // Check if LED wall still needs updates
            guard ledWall.connectedCameraFeedID == feedID,
                  ledWall.isDisplayingCameraFeed else {
                timer.invalidate()
                objc_setAssociatedObject(ledWall, &AssociatedKeys.timer, nil, .OBJC_ASSOCIATION_RETAIN)
                return
            }
            
            Task { @MainActor in
                self.performLEDWallUpdate(ledWall: ledWall, feedID: feedID, timer: timer)
            }
        }
        
        print(" Started timer for LED wall: \(ledWall.name) at 30fps")
        
        // Store the timer for cleanup
        objc_setAssociatedObject(ledWall, &AssociatedKeys.timer, timer, .OBJC_ASSOCIATION_RETAIN)
    }
    
    private func performLEDWallUpdate(ledWall: StudioObject, feedID: UUID, timer: Timer) {
        // PERFORMANCE: Early exit checks
        guard ledWall.connectedCameraFeedID == feedID,
              ledWall.isDisplayingCameraFeed,
              let activeFeed = self.cameraFeedManager.activeFeeds.first(where: { $0.id == feedID }),
              activeFeed.connectionStatus == .connected else {
            // Stop the timer if conditions are no longer met
            timer.invalidate()
            objc_setAssociatedObject(ledWall, &AssociatedKeys.timer, nil, .OBJC_ASSOCIATION_RETAIN)
            return
        }
        
        var updated = false
        
        // PERFORMANCE: Use cached images when available, prefer NSImage for better SceneKit performance
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
        
        // PERFORMANCE: Still keep reduced debug logging (every 15 seconds instead of 5)
        if self.feedUpdateFrameCount % 450 == 1 { // Every ~15 seconds at 30fps
            print(" LED Wall '\(ledWall.name)' feed update #\(self.feedUpdateFrameCount) (30fps)")
            print("   - Has NSImage: \(activeFeed.previewNSImage != nil)")
            print("   - Has CGImage: \(activeFeed.previewImage != nil)")
            print("   - Has pixel buffer: \(activeFeed.currentFrame != nil)")
            print("   - Updated this frame: \(updated)")
            print("   - Feed frame count: \(activeFeed.frameCount)")
        }
    }
    
    private func stopLiveFeedUpdates(for ledWall: StudioObject) {
        // PERFORMANCE: Stop timer
        if let timer = objc_getAssociatedObject(ledWall, &AssociatedKeys.timer) as? Timer {
            timer.invalidate()
            objc_setAssociatedObject(ledWall, &AssociatedKeys.timer, nil, .OBJC_ASSOCIATION_RETAIN)
            print(" Stopped optimized timer for LED wall: \(ledWall.name)")
        }
        
        print(" Stopped live feed updates for LED wall: \(ledWall.name)")
    }
}

enum CameraMode: String, CaseIterable, Hashable {
    case orbit, pan, fly
}

struct PropertySection<Content: View> : View {
    let title: String
    let content: () -> Content
    
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            
            content()
        }
        .padding(16)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}

struct PropertyRow<Content: View>: View {
    let label: String
    let content: () -> Content
    
    init(label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }
    
    var body: some View {
        HStack {
            Text(label + ":")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 60, alignment: .leading)
            
            content()
            
            Spacer()
        }
    }
}

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

private class TimerTarget {
    private let callback: () -> Void
    
    init(callback: @escaping () -> Void) {
        self.callback = callback
    }
    
    @objc func timerFired() {
        callback()
    }
}

// PERFORMANCE: Associated object keys for storing timers
private struct AssociatedKeys {
    static var timer = "timer"
}