import Foundation
import SwiftUI
import Combine
import Metal
import OSLog
import simd

@MainActor
class OutputMappingManager: ObservableObject {
    // MARK: - Published Properties
    @Published var currentMapping: OutputMapping = OutputMapping()
    @Published var presets: [OutputMappingPreset] = []
    @Published var selectedPreset: OutputMappingPreset?
    @Published var isEnabled: Bool = true
    @Published var showMappingPanel: Bool = false
    
    // REAL-TIME EDITING ENHANCEMENTS
    @Published var isDragging: Bool = false
    @Published var isResizing: Bool = false
    @Published var isHovering: Bool = false
    @Published var snapToEdges: Bool = true
    @Published var snapThreshold: CGFloat = 10.0
    @Published var showGizmo: Bool = true
    @Published var showGrid: Bool = false
    @Published var gridOpacity: CGFloat = 0.3
    
    // PREMIERE PRO-STYLE SCRUBBING
    @Published var isScrubbingX: Bool = false
    @Published var isScrubbingY: Bool = false
    @Published var isScrubbingW: Bool = false
    @Published var isScrubbingH: Bool = false
    @Published var scrubStartValue: CGFloat = 0
    @Published var scrubSensitivity: CGFloat = 1.0
    @Published var precisionMode: Bool = false  // Hold shift for precision
    
    // LIVE PREVIEW & FEEDBACK
    @Published var livePreviewEnabled: Bool = true
    @Published var previewOpacity: CGFloat = 1.0
    @Published var showBounds: Bool = true
    @Published var boundsColor: Color = .yellow
    @Published var showCenterCross: Bool = false
    
    // Output canvas settings
    @Published var canvasSize: CGSize = CGSize(width: 1920, height: 1080)
    @Published var previewScale: CGFloat = 0.3
    
    // Control integration - lazy initialized
    private var _oscController: OSCController?
    private var _midiController: MIDIController?
    private var _hotkeyController: HotkeyController?
    
    var oscController: OSCController {
        if _oscController == nil {
            _oscController = OSCController()
            _oscController?.outputMappingManager = self
        }
        return _oscController!
    }
    
    var midiController: MIDIController {
        if _midiController == nil {
            _midiController = MIDIController()
            _midiController?.outputMappingManager = self
        }
        return _midiController!
    }
    
    var hotkeyController: HotkeyController {
        if _hotkeyController == nil {
            _hotkeyController = HotkeyController()
            _hotkeyController?.outputMappingManager = self
        }
        return _hotkeyController!
    }
    
    // MARK: - Private Properties
    private let logger = Logger(subsystem: "com.vistaview.app", category: "OutputMapping")
    private var cancellables = Set<AnyCancellable>()
    private let presetsURL: URL
    
    // Metal resources
    let metalDevice: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var computePipelineState: MTLComputePipelineState?
    
    // MARK: - Initialization
    
    init(metalDevice: MTLDevice) {
        self.metalDevice = metalDevice
        
        guard let queue = metalDevice.makeCommandQueue() else {
            fatalError("Could not create Metal command queue for OutputMappingManager")
        }
        self.commandQueue = queue
        
        // Setup presets storage
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        presetsURL = documentsPath.appendingPathComponent("VantaviewOutputPresets.json")
        
        setupDefaultMapping()
        loadPresets()
        setupBindings()
        
        logger.info("🎯 OutputMappingManager initialized (controllers will be lazy-loaded)")
    }
    
    // MARK: - Setup
    
    private func setupDefaultMapping() {
        currentMapping = OutputMapping()
        currentMapping.outputResolution = canvasSize
        
        // Create some default presets
        createDefaultPresets()
    }
    
    private func setupBindings() {
        // Update selected preset when mapping changes
        $currentMapping
            .sink { [weak self] mapping in
                self?.updateSelectedPresetIfNeeded(mapping)
            }
            .store(in: &cancellables)
    }
    
    private func createDefaultPresets() {
        let defaultPresets = [
            OutputMappingPreset(
                name: "Full Screen",
                mapping: OutputMapping(),
                description: "Fill the entire output screen"
            ),
            OutputMappingPreset(
                name: "Center 80%",
                mapping: {
                    var mapping = OutputMapping()
                    mapping.scale = 0.8
                    mapping.position = CGPoint(x: 0.1, y: 0.1)
                    return mapping
                }(),
                description: "Centered at 80% scale with margins"
            ),
            OutputMappingPreset(
                name: "Top Half",
                mapping: {
                    var mapping = OutputMapping()
                    mapping.size = CGSize(width: 1.0, height: 0.5)
                    mapping.position = CGPoint(x: 0, y: 0)
                    return mapping
                }(),
                description: "Upper half of the screen"
            ),
            OutputMappingPreset(
                name: "Bottom Half",
                mapping: {
                    var mapping = OutputMapping()
                    mapping.size = CGSize(width: 1.0, height: 0.5)
                    mapping.position = CGPoint(x: 0, y: 0.5)
                    return mapping
                }(),
                description: "Lower half of the screen"
            ),
            OutputMappingPreset(
                name: "Left Third",
                mapping: {
                    var mapping = OutputMapping()
                    mapping.size = CGSize(width: 0.33, height: 1.0)
                    mapping.position = CGPoint(x: 0, y: 0)
                    return mapping
                }(),
                description: "Left third of the screen"
            ),
            OutputMappingPreset(
                name: "Right Third",
                mapping: {
                    var mapping = OutputMapping()
                    mapping.size = CGSize(width: 0.33, height: 1.0)
                    mapping.position = CGPoint(x: 0.67, y: 0)
                    return mapping
                }(),
                description: "Right third of the screen"
            )
        ]
        
        if presets.isEmpty {
            presets = defaultPresets
            savePresets()
        }
    }
    
    // MARK: - Mapping Control
    
    func updateMapping(_ newMapping: OutputMapping) {
        currentMapping = newMapping
        logger.debug("🎯 Updated output mapping: pos(\(newMapping.position.x), \(newMapping.position.y)) size(\(newMapping.size.width), \(newMapping.size.height))")
    }
    
    func setPosition(_ position: CGPoint) {
        let clampedX = max(0.0, min(1.0 - currentMapping.scaledSize.width, position.x))
        let clampedY = max(0.0, min(1.0 - currentMapping.scaledSize.height, position.y))
        currentMapping.position = CGPoint(x: clampedX, y: clampedY)
        if snapToEdges {
            currentMapping.snapToEdges(in: canvasSize, threshold: snapThreshold)
        }
        publishAndNotify()
    }
    
    func setSize(_ size: CGSize) {
        let oldCenter = currentMapping.center
        currentMapping.setSize(size, maintainAspectRatio: currentMapping.aspectRatioLocked)
        currentMapping.position = CGPoint(
            x: oldCenter.x - currentMapping.scaledSize.width / 2,
            y: oldCenter.y - currentMapping.scaledSize.height / 2
        )
        setPosition(currentMapping.position)
        publishAndNotify()
    }
    
    func setRotation(_ rotation: Float) {
        currentMapping.rotation = rotation
        publishAndNotify()
    }
    
    func setScale(_ scale: CGFloat) {
        let clamped = max(0.1, min(5.0, scale))
        let oldCenter = currentMapping.center
        currentMapping.scale = clamped
        currentMapping.position = CGPoint(
            x: oldCenter.x - currentMapping.scaledSize.width / 2,
            y: oldCenter.y - currentMapping.scaledSize.height / 2
        )
        setPosition(currentMapping.position)
        publishAndNotify()
    }
    
    func setOpacity(_ opacity: Float) {
        currentMapping.opacity = max(0.0, min(1.0, opacity))
        publishAndNotify()
    }
    
    func setPositionX(_ normalizedX: CGFloat) {
        setPosition(CGPoint(x: normalizedX, y: currentMapping.position.y))
    }
    
    func setPositionY(_ normalizedY: CGFloat) {
        setPosition(CGPoint(x: currentMapping.position.x, y: normalizedY))
    }
    
    func setWidth(_ normalizedWidth: CGFloat) {
        let clampedW = max(0.01, min(1.0, normalizedWidth))
        setSize(CGSize(width: clampedW, height: currentMapping.size.height))
    }
    
    func setHeight(_ normalizedHeight: CGFloat) {
        let clampedH = max(0.01, min(1.0, normalizedHeight))
        setSize(CGSize(width: currentMapping.size.width, height: clampedH))
    }

    func startScrubbing(for parameter: MappingParameter, initialValue: CGFloat) {
        switch parameter {
        case .positionX:
            isScrubbingX = true
            scrubStartValue = initialValue
        case .positionY:
            isScrubbingY = true
            scrubStartValue = initialValue
        case .width:
            isScrubbingW = true
            scrubStartValue = initialValue
        case .height:
            isScrubbingH = true
            scrubStartValue = initialValue
        default:
            break
        }
    }
    
    func stopScrubbing() {
        isScrubbingX = false
        isScrubbingY = false
        isScrubbingW = false
        isScrubbingH = false
    }
    
    func setPrecisionMode(_ enabled: Bool) {
        precisionMode = enabled
        scrubSensitivity = enabled ? 0.2 : 1.0
    }

    // MARK: - Quick Actions
    
    func fitToScreen() {
        currentMapping.fitToScreen()
        logger.info("🎯 Fit output to screen")
        publishAndNotify()
    }
    
    func centerOutput() {
        currentMapping.centerOutput(in: canvasSize)
        logger.info("🎯 Centered output")
        publishAndNotify()
    }
    
    func resetMapping() {
        currentMapping = OutputMapping()
        currentMapping.outputResolution = canvasSize
        selectedPreset = nil
        logger.info("🎯 Reset output mapping")
        publishAndNotify()
    }
    
    func toggleAspectRatioLock() {
        currentMapping.aspectRatioLocked.toggle()
        logger.info("🎯 Aspect ratio lock: \(self.currentMapping.aspectRatioLocked ? "ON" : "OFF")")
        publishAndNotify()
    }
    
    // MARK: - Preset Management
    
    func saveCurrentAsPreset(name: String, description: String? = nil) {
        let preset = OutputMappingPreset(
            name: name,
            mapping: currentMapping,
            description: description
        )
        
        presets.append(preset)
        selectedPreset = preset
        savePresets()
        
        logger.info("🎯 Saved preset: \(name)")
    }
    
    func applyPreset(_ preset: OutputMappingPreset) {
        currentMapping = preset.mapping
        currentMapping.outputResolution = canvasSize
        selectedPreset = preset
        
        logger.info("🎯 Applied preset: \(preset.name)")
    }
    
    func updatePreset(_ preset: OutputMappingPreset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            var updatedPreset = preset
            updatedPreset.updateMapping(currentMapping)
            presets[index] = updatedPreset
            selectedPreset = updatedPreset
            savePresets()
            
            logger.info("🎯 Updated preset: \(preset.name)")
        }
    }
    
    func deletePreset(_ preset: OutputMappingPreset) {
        presets.removeAll { $0.id == preset.id }
        if selectedPreset?.id == preset.id {
            selectedPreset = nil
        }
        savePresets()
        
        logger.info("🎯 Deleted preset: \(preset.name)")
    }
    
    func duplicatePreset(_ preset: OutputMappingPreset) {
        var newPreset = preset
        newPreset.name = "\(preset.name) Copy"
        presets.append(newPreset)
        savePresets()
        
        logger.info("🎯 Duplicated preset: \(preset.name)")
    }
    
    private func updateSelectedPresetIfNeeded(_ mapping: OutputMapping) {
        // Check if current mapping matches any preset
        if let selected = selectedPreset,
           selected.mapping != mapping {
            selectedPreset = nil
        }
    }
    
    // MARK: - Import/Export
    
    func exportPresets() -> URL? {
        let collection = OutputMappingPresetCollection(presets: presets)
        
        do {
            let data = try JSONEncoder().encode(collection)
            let exportURL = presetsURL.appendingPathExtension("export")
            try data.write(to: exportURL)
            
            logger.info("🎯 Exported \(self.presets.count) presets")
            return exportURL
        } catch {
            logger.error("🎯 Failed to export presets: \(error)")
            return nil
        }
    }
    
    func importPresets(from url: URL) -> Bool {
        do {
            let data = try Data(contentsOf: url)
            let collection = try JSONDecoder().decode(OutputMappingPresetCollection.self, from: data)
            
            // Merge with existing presets
            for preset in collection.presets {
                if !presets.contains(where: { $0.name == preset.name }) {
                    presets.append(preset)
                }
            }
            
            savePresets()
            logger.info("🎯 Imported \(collection.presets.count) presets")
            return true
        } catch {
            logger.error("🎯 Failed to import presets: \(error)")
            return false
        }
    }
    
    // MARK: - Persistence
    
    private func savePresets() {
        do {
            let collection = OutputMappingPresetCollection(presets: presets)
            let data = try JSONEncoder().encode(collection)
            try data.write(to: presetsURL)
        } catch {
            logger.error("🎯 Failed to save presets: \(error)")
        }
    }
    
    private func loadPresets() {
        guard FileManager.default.fileExists(atPath: presetsURL.path) else {
            logger.info("🎯 No saved presets found, using defaults")
            return
        }
        
        do {
            let data = try Data(contentsOf: presetsURL)
            let collection = try JSONDecoder().decode(OutputMappingPresetCollection.self, from: data)
            presets = collection.presets
            
            logger.info("🎯 Loaded \(self.presets.count) presets")
        } catch {
            logger.error("🎯 Failed to load presets: \(error)")
        }
    }
    
    // MARK: - Metal Processing (OPTIMIZED FOR LOW LATENCY)
    
    func applyOutputMapping(to texture: MTLTexture) -> MTLTexture? {
        guard isEnabled else { return texture }
        
        // OPTIMIZATION: Skip processing if mapping is essentially identity
        if !hasSignificantMapping {
            return texture
        }
        
        // Create descriptor for output texture with optimal settings
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat,
            width: Int(canvasSize.width),
            height: Int(canvasSize.height),
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private  // Fastest GPU-only storage
        
        guard let outputTexture = metalDevice.makeTexture(descriptor: descriptor),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return texture
        }
        
        // OPTIMIZATION: Set label for better debugging and Metal profiling
        commandBuffer.label = "OutputMapping"
        
        // Apply transformation using optimized Metal compute shader
        applyMappingTransform(
            from: texture,
            to: outputTexture,
            mapping: currentMapping,
            commandBuffer: commandBuffer
        )
        
        // OPTIMIZATION: Don't wait for completion - pipeline the GPU work
        commandBuffer.commit()
        
        // ONLY wait if we need immediate results - for LED walls, pipeline instead
        // commandBuffer.waitUntilCompleted()  // Commented out for better performance
        
        return outputTexture
    }
    
    private func applyMappingTransform(
        from sourceTexture: MTLTexture,
        to destinationTexture: MTLTexture,
        mapping: OutputMapping,
        commandBuffer: MTLCommandBuffer
    ) {
        // Get the compute pipeline state
        guard let computePipelineState = getComputePipelineState() else {
            logger.error("🎯 Failed to get compute pipeline state")
            return
        }
        
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            logger.error("🎯 Failed to create compute encoder")
            return
        }
        
        // OPTIMIZATION: Set encoder label for profiling
        computeEncoder.label = "OutputMappingTransform"
        
        let centerNormalized = simd_float2(
            Float(mapping.position.x + mapping.scaledSize.width / 2),
            Float(mapping.position.y + mapping.scaledSize.height / 2)
        )
        let translationFromCenter = centerNormalized - simd_float2(0.5, 0.5)

        var uniforms = OutputMappingUniforms(
            transformMatrix: mapping.transformMatrix,
            outputSize: simd_float2(Float(canvasSize.width), Float(canvasSize.height)),
            inputSize: simd_float2(Float(sourceTexture.width), Float(sourceTexture.height)),
            opacity: mapping.opacity,
            rotation: mapping.rotation * .pi / 180.0,
            scale: simd_float2(Float(mapping.scale * mapping.size.width), Float(mapping.scale * mapping.size.height)),
            translation: translationFromCenter
        )
        
        // Set compute pipeline and resources
        computeEncoder.setComputePipelineState(computePipelineState)
        computeEncoder.setTexture(sourceTexture, index: 0)
        computeEncoder.setTexture(destinationTexture, index: 1)
        computeEncoder.setBytes(&uniforms, length: MemoryLayout<OutputMappingUniforms>.stride, index: 0)
        
        // OPTIMIZATION: Use larger thread groups for better GPU utilization
        let threadGroupSize = MTLSize(width: 32, height: 32, depth: 1)  // Increased from 16x16
        let threadGroups = MTLSize(
            width: (destinationTexture.width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (destinationTexture.height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        
        // Dispatch compute threads
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
    }
    
    private func getComputePipelineState() -> MTLComputePipelineState? {
        // Cache the pipeline state
        if computePipelineState == nil {
            guard let library = metalDevice.makeDefaultLibrary() else {
                logger.error("🎯 Failed to get default Metal library")
                return nil
            }
            
            // Choose the fastest appropriate compute function
            let functionName: String
            if hasSignificantMapping {
                // Use bilinear for quality when we have significant mapping
                functionName = "outputMappingComputeBilinear"
            } else {
                // Use ultra-fast version for LED walls when mapping is minimal
                functionName = "outputMappingComputeFast"
            }
            
            guard let computeFunction = library.makeFunction(name: functionName) else {
                logger.error("🎯 Failed to create compute function: \(functionName)")
                // Fallback to basic function
                guard let fallbackFunction = library.makeFunction(name: "outputMappingComputeBilinear") else {
                    logger.error("🎯 Failed to create fallback compute function")
                    return nil
                }
                
                do {
                    computePipelineState = try metalDevice.makeComputePipelineState(function: fallbackFunction)
                } catch {
                    logger.error("🎯 Failed to create fallback compute pipeline state: \(error)")
                    return nil
                }
                
                return computePipelineState
            }
            
            do {
                computePipelineState = try metalDevice.makeComputePipelineState(function: computeFunction)
            } catch {
                logger.error("🎯 Failed to create compute pipeline state: \(error)")
                return nil
            }
        }
        
        return computePipelineState
    }
    
    // MARK: - UI State
    
    func toggleMappingPanel() {
        showMappingPanel.toggle()
        logger.info("🎯 Output mapping panel: \(self.showMappingPanel ? "SHOWN" : "HIDDEN")")
    }
    
    func showPanel() {
        showMappingPanel = true
    }
    
    func hidePanel() {
        showMappingPanel = false
    }
    
    // MARK: - Control Integration Convenience Properties
    
    var oscEnabled: Bool {
        get { _oscController?.isEnabled ?? false }
        set { 
            if newValue {
                enableOSCControl()
            } else {
                _oscController?.stopListening()
            }
        }
    }
    
    var midiEnabled: Bool {
        get { _midiController?.isEnabled ?? false }
        set { 
            if newValue {
                enableMIDIControl()
            } else {
                _midiController?.disconnectCurrentDevice()
            }
        }
    }
    
    var learnMode: Bool {
        get { (_oscController?.learnMode ?? false) || (_midiController?.learnMode ?? false) }
        set { 
            if _oscController != nil { _oscController!.learnMode = newValue }
            if _midiController != nil { _midiController!.learnMode = newValue }
        }
    }
    
    var hotkeyEnabled: Bool {
        get { _hotkeyController?.isEnabled ?? false }
        set {
            if newValue {
                _ = hotkeyController // Initialize if needed
                hotkeyController.enableHotkeys()
            } else {
                _hotkeyController?.disableHotkeys()
            }
        }
    }
    
    // MARK: - Control Integration
    
    func enableOSCControl() {
        oscController.startListening()
        logger.info("🎯 OSC control enabled on port \(self.oscController.port)")
    }
    
    func enableMIDIControl() {
        midiController.scanForDevices()
        logger.info("🎯 MIDI control enabled")
    }
    
    func toggleLearnMode() {
        learnMode.toggle()
        logger.info("🎯 Learn mode: \(self.learnMode ? "ON" : "OFF")")
    }
    
    // MARK: - Validation
    
    func validateMapping(_ mapping: OutputMapping) -> Bool {
        // Ensure mapping parameters are within valid ranges
        let validPosition = mapping.position.x >= 0 && mapping.position.y >= 0
        let validSize = mapping.size.width > 0 && mapping.size.height > 0 && 
                       mapping.size.width <= 1 && mapping.size.height <= 1
        let validScale = mapping.scale > 0 && mapping.scale <= 5.0
        let validOpacity = mapping.opacity >= 0 && mapping.opacity <= 1.0
        
        return validPosition && validSize && validScale && validOpacity
    }

    private func publishAndNotify() {
        self.currentMapping = self.currentMapping
        NotificationCenter.default.post(
            name: .outputMappingDidChange,
            object: self,
            userInfo: ["mapping": currentMapping]
        )
    }
}

// MARK: - Convenience Extensions

extension OutputMappingManager {
    var mappingDescription: String {
        let pos = currentMapping.position
        let size = currentMapping.size
        return "Pos: (\(Int(pos.x * canvasSize.width)), \(Int(pos.y * canvasSize.height))) Size: \(Int(size.width * canvasSize.width))×\(Int(size.height * canvasSize.height))"
    }
    
    /// Determines if the current mapping has significant changes that warrant processing
    var hasSignificantMapping: Bool {
        guard isEnabled else { return false }
        
        let mapping = currentMapping
        
        // OPTIMIZATION: Use more precise thresholds to avoid unnecessary processing
        let hasPositionChange = abs(mapping.position.x) > 0.0001 || abs(mapping.position.y) > 0.0001
        let hasSizeChange = abs(mapping.size.width - 1.0) > 0.0001 || abs(mapping.size.height - 1.0) > 0.0001
        let hasScaleChange = abs(mapping.scale - 1.0) > 0.0001
        let hasRotationChange = abs(mapping.rotation) > 0.01  // degrees (more precise)
        let hasOpacityChange = abs(mapping.opacity - 1.0) > 0.0001
        
        return hasPositionChange || hasSizeChange || hasScaleChange || hasRotationChange || hasOpacityChange
    }
    
    func pixelPosition() -> CGPoint {
        return CGPoint(
            x: currentMapping.position.x * canvasSize.width,
            y: currentMapping.position.y * canvasSize.height
        )
    }
    
    func pixelSize() -> CGSize {
        return CGSize(
            width: currentMapping.size.width * canvasSize.width,
            height: currentMapping.size.height * canvasSize.height
        )
    }
}

// MARK: - Supporting Structures

struct OutputMappingUniforms {
    var transformMatrix: simd_float4x4
    var outputSize: simd_float2
    var inputSize: simd_float2
    var opacity: Float
    var rotation: Float
    var scale: simd_float2
    var translation: simd_float2
}

// MARK: - Supporting Types

enum MappingParameter: String, CaseIterable {
    case positionX = "Position X"
    case positionY = "Position Y"
    case width = "Width"
    case height = "Height"
    case rotation = "Rotation"
    case scale = "Scale"
    case opacity = "Opacity"
}

extension Notification.Name {
    static let outputMappingDidChange = Notification.Name("outputMappingDidChange")
}