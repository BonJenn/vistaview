import Foundation
import CoreMIDI
import OSLog

@MainActor
class MIDIController: ObservableObject {
    @Published var isEnabled: Bool = false
    @Published var isConnected: Bool = false
    @Published var availableDevices: [MIDIDevice] = []
    @Published var selectedDevice: MIDIDevice?
    @Published var learnMode: Bool = false
    
    private var midiClient: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private let logger = Logger(subsystem: "com.vistaview.app", category: "MIDI")
    
    // Weak reference to avoid retain cycles
    weak var outputMappingManager: OutputMappingManager?
    
    // Parameter mappings
    private var parameterMappings: [UInt8: MIDIParameterMapping] = [:]
    
    init() {
        setupMIDI()
        scanForDevices()
        setupDefaultMappings()
    }
    
    deinit {
        Task { @MainActor in
            self.cleanup()
        }
    }
    
    // MARK: - MIDI Setup
    
    private func setupMIDI() {
        do {
            let clientName = "Vistaview" as CFString
            let status = MIDIClientCreate(clientName, { _, _ in
                // MIDI system changed notification
                Task { @MainActor in
                    // Rescan devices
                }
            }, nil, &midiClient)
            
            if status != noErr {
                logger.warning("🎹 Failed to create MIDI client: \(status) - MIDI will be unavailable")
                return
            }
            
            let portName = "Vistaview Input" as CFString
            let portStatus = MIDIInputPortCreate(midiClient, portName, { packetList, refCon, connRefCon in
                // Handle MIDI input
                guard let refCon = refCon else { return }
                let controller = Unmanaged<MIDIController>.fromOpaque(refCon).takeUnretainedValue()
                
                Task { @MainActor in
                    controller.handleMIDIPacketList(packetList)
                }
            }, Unmanaged.passUnretained(self).toOpaque(), &inputPort)
            
            if portStatus != noErr {
                logger.warning("🎹 Failed to create MIDI input port: \(portStatus) - MIDI will be unavailable")
                return
            }
            
            logger.info("🎹 MIDI Controller initialized successfully")
        } catch {
            logger.error("🎹 MIDI Controller initialization failed: \(error)")
        }
    }
    
    private func cleanup() {
        if inputPort != 0 {
            MIDIPortDispose(inputPort)
        }
        if midiClient != 0 {
            MIDIClientDispose(midiClient)
        }
    }
    
    // MARK: - Device Management
    
    func scanForDevices() {
        self.availableDevices.removeAll()
        
        let deviceCount = MIDIGetNumberOfDevices()
        
        for i in 0..<deviceCount {
            let device = MIDIGetDevice(i)
            guard device != 0 else { continue }
            
            // Get device name
            var nameProperty: Unmanaged<CFString>?
            let status = MIDIObjectGetStringProperty(device, kMIDIPropertyName, &nameProperty)
            
            if status == noErr, let name = nameProperty?.takeRetainedValue() {
                let deviceInfo = MIDIDevice(
                    id: device,
                    name: String(name),
                    isConnected: false
                )
                self.availableDevices.append(deviceInfo)
            }
        }
        
        logger.info("🎹 Found \(self.availableDevices.count) MIDI devices")
    }
    
    func connectToDevice(_ device: MIDIDevice) {
        disconnectCurrentDevice()
        
        // Get all sources for this device
        let entityCount = MIDIDeviceGetNumberOfEntities(device.id)
        
        for i in 0..<entityCount {
            let entity = MIDIDeviceGetEntity(device.id, i)
            guard entity != 0 else { continue }
            
            let sourceCount = MIDIEntityGetNumberOfSources(entity)
            for j in 0..<sourceCount {
                let source = MIDIEntityGetSource(entity, j)
                guard source != 0 else { continue }
                
                let status = MIDIPortConnectSource(inputPort, source, nil)
                if status == noErr {
                    selectedDevice = device
                    isConnected = true
                    logger.info("🎹 Connected to MIDI device: \(device.name)")
                    return
                }
            }
        }
        
        logger.error("🎹 Failed to connect to MIDI device: \(device.name)")
    }
    
    func disconnectCurrentDevice() {
        guard let device = selectedDevice else { return }
        
        let entityCount = MIDIDeviceGetNumberOfEntities(device.id)
        
        for i in 0..<entityCount {
            let entity = MIDIDeviceGetEntity(device.id, i)
            guard entity != 0 else { continue }
            
            let sourceCount = MIDIEntityGetNumberOfSources(entity)
            for j in 0..<sourceCount {
                let source = MIDIEntityGetSource(entity, j)
                guard source != 0 else { continue }
                
                MIDIPortDisconnectSource(inputPort, source)
            }
        }
        
        selectedDevice = nil
        isConnected = false
        logger.info("🎹 Disconnected from MIDI device: \(device.name)")
    }
    
    // MARK: - MIDI Message Handling
    
    private func handleMIDIPacketList(_ packetList: UnsafePointer<MIDIPacketList>) {
        let packets = MIDIPacketListIterator(packetList)
        
        for packet in packets {
            handleMIDIPacket(packet)
        }
    }
    
    private func handleMIDIPacket(_ packet: MIDIPacket) {
        guard packet.length >= 3 else { return }
        
        let data = withUnsafeBytes(of: packet.data) { bytes in
            Array(bytes.prefix(Int(packet.length)))
        }
        
        // Parse MIDI message
        let status = data[0]
        let messageType = status & 0xF0
        let channel = status & 0x0F
        
        switch messageType {
        case 0xB0: // Control Change
            if data.count >= 3 {
                let controlNumber = data[1]
                let value = data[2]
                handleControlChange(controlNumber: controlNumber, value: value, channel: channel)
            }
            
        case 0x90: // Note On
            if data.count >= 3 {
                let note = data[1]
                let velocity = data[2]
                if velocity > 0 {
                    handleNoteOn(note: note, velocity: velocity, channel: channel)
                } else {
                    handleNoteOff(note: note, channel: channel)
                }
            }
            
        case 0x80: // Note Off
            if data.count >= 2 {
                let note = data[1]
                handleNoteOff(note: note, channel: channel)
            }
            
        default:
            break
        }
    }
    
    private func handleControlChange(controlNumber: UInt8, value: UInt8, channel: UInt8) {
        logger.debug("🎹 CC: Controller \(controlNumber) = \(value) on channel \(channel)")
        
        if learnMode {
            logger.info("🎹 Learn mode: CC \(controlNumber) = \(value)")
            return
        }
        
        guard let mapping = parameterMappings[controlNumber],
              let outputMappingManager = outputMappingManager else { return }
        
        // Convert MIDI value (0-127) to normalized value (0.0-1.0)
        let normalizedValue = Float(value) / 127.0
        
        // Apply mapping transformation
        let mappedValue = mapping.outputRange.min + normalizedValue * (mapping.outputRange.max - mapping.outputRange.min)
        
        // Apply to output mapping parameter
        applyParameterValue(mapping.parameter, value: mappedValue)
    }
    
    private func handleNoteOn(note: UInt8, velocity: UInt8, channel: UInt8) {
        logger.debug("🎹 Note On: Note \(note), Velocity \(velocity) on channel \(channel)")
        
        if learnMode {
            logger.info("🎹 Learn mode: Note On \(note)")
            return
        }
        
        // Handle note-based triggers (e.g., preset selection)
        if let mapping = parameterMappings[note + 128], // Offset notes to avoid CC conflicts
           mapping.parameter == .preset,
           let outputMappingManager = outputMappingManager {
            
            let presetIndex = Int(Float(note) - mapping.outputRange.min)
            if presetIndex >= 0 && presetIndex < outputMappingManager.presets.count {
                let preset = outputMappingManager.presets[presetIndex]
                outputMappingManager.applyPreset(preset)
                logger.info("🎹 Applied preset via MIDI note: \(preset.name)")
            }
        }
    }
    
    private func handleNoteOff(note: UInt8, channel: UInt8) {
        logger.debug("🎹 Note Off: Note \(note) on channel \(channel)")
    }
    
    private func applyParameterValue(_ parameter: MIDIMappableParameter, value: Float) {
        guard let outputMappingManager = outputMappingManager else { return }
        
        switch parameter {
        case .positionX:
            outputMappingManager.setPosition(CGPoint(
                x: CGFloat(value),
                y: outputMappingManager.currentMapping.position.y
            ))
        case .positionY:
            outputMappingManager.setPosition(CGPoint(
                x: outputMappingManager.currentMapping.position.x,
                y: CGFloat(value)
            ))
        case .sizeWidth:
            outputMappingManager.setSize(CGSize(
                width: CGFloat(value),
                height: outputMappingManager.currentMapping.size.height
            ))
        case .sizeHeight:
            outputMappingManager.setSize(CGSize(
                width: outputMappingManager.currentMapping.size.width,
                height: CGFloat(value)
            ))
        case .scale:
            outputMappingManager.setScale(CGFloat(value))
        case .rotation:
            outputMappingManager.setRotation(value)
        case .opacity:
            outputMappingManager.setOpacity(value)
        case .preset:
            // Handled in note on/off
            break
        }
        
        logger.debug("🎹 Applied MIDI control: \(parameter.rawValue)")
    }
    
    // MARK: - Parameter Mapping Management
    
    func addParameterMapping(controlNumber: UInt8, parameter: MIDIMappableParameter, outputRange: MIDIRange) {
        let mapping = MIDIParameterMapping(
            controlNumber: controlNumber,
            parameter: parameter,
            outputRange: outputRange
        )
        parameterMappings[controlNumber] = mapping
        
        logger.info("🎹 Added MIDI mapping: CC \(controlNumber) -> \(parameter.rawValue)")
    }
    
    func removeParameterMapping(controlNumber: UInt8) {
        parameterMappings.removeValue(forKey: controlNumber)
        logger.info("🎹 Removed MIDI mapping: CC \(controlNumber)")
    }
    
    private func setupDefaultMappings() {
        // Set up some default MIDI mappings
        addParameterMapping(
            controlNumber: 1, // Mod Wheel
            parameter: .scale,
            outputRange: MIDIRange(min: 0.1, max: 3.0)
        )
        
        addParameterMapping(
            controlNumber: 7, // Volume
            parameter: .opacity,
            outputRange: MIDIRange(min: 0.0, max: 1.0)
        )
        
        addParameterMapping(
            controlNumber: 10, // Pan
            parameter: .positionX,
            outputRange: MIDIRange(min: 0.0, max: 1.0)
        )
        
        addParameterMapping(
            controlNumber: 74, // Filter Cutoff (common on many controllers)
            parameter: .rotation,
            outputRange: MIDIRange(min: -180.0, max: 180.0)
        )
    }
}

// MARK: - Supporting Types

struct MIDIDevice: Identifiable, Equatable {
    let id: MIDIDeviceRef
    let name: String
    let isConnected: Bool
    
    static func == (lhs: MIDIDevice, rhs: MIDIDevice) -> Bool {
        lhs.id == rhs.id
    }
}

struct MIDIParameterMapping {
    let controlNumber: UInt8
    let parameter: MIDIMappableParameter
    let outputRange: MIDIRange
}

struct MIDIRange {
    let min: Float
    let max: Float
}

enum MIDIMappableParameter: String, CaseIterable {
    case positionX = "Position X"
    case positionY = "Position Y"
    case sizeWidth = "Size Width"
    case sizeHeight = "Size Height"
    case scale = "Scale"
    case rotation = "Rotation"
    case opacity = "Opacity"
    case preset = "Preset"
}

// MARK: - MIDI Packet List Iterator

struct MIDIPacketListIterator: Sequence, IteratorProtocol {
    private let packetList: UnsafePointer<MIDIPacketList>
    private var currentPacket: UnsafePointer<MIDIPacket>?
    private var packetsRemaining: UInt32
    
    init(_ packetList: UnsafePointer<MIDIPacketList>) {
        self.packetList = packetList
        self.packetsRemaining = packetList.pointee.numPackets
        
        if packetsRemaining > 0 {
            // Get pointer to first packet
            let packetPtr = withUnsafePointer(to: packetList.pointee.packet) { $0 }
            self.currentPacket = packetPtr
        } else {
            self.currentPacket = nil
        }
    }
    
    mutating func next() -> MIDIPacket? {
        guard packetsRemaining > 0, let packet = currentPacket else {
            return nil
        }
        
        let result = packet.pointee
        packetsRemaining -= 1
        
        if packetsRemaining > 0 {
            currentPacket = UnsafePointer(MIDIPacketNext(packet))
        } else {
            currentPacket = nil
        }
        
        return result
    }
}