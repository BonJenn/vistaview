import Foundation
import Network
import OSLog

@MainActor
class OSCController: ObservableObject {
    @Published var isEnabled: Bool = false
    @Published var isConnected: Bool = false
    @Published var port: UInt16 = 8000
    @Published var learnMode: Bool = false
    
    private var listener: NWListener?
    private var connection: NWConnection?
    private let logger = Logger(subsystem: "com.vistaview.app", category: "OSC")
    
    // Weak reference to avoid retain cycles
    weak var outputMappingManager: OutputMappingManager?
    
    // Parameter mappings
    private var parameterMappings: [String: OSCParameterMapping] = [:]
    
    init() {
        setupDefaultMappings()
    }
    
    deinit {
        Task { @MainActor in
            self.stopListening()
        }
    }
    
    // MARK: - Connection Management
    
    func startListening() {
        stopListening()
        
        do {
            let parameters = NWParameters.udp
            parameters.allowLocalEndpointReuse = true
            
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))
            
            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleNewConnection(connection)
                }
            }
            
            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isConnected = true
                        self?.logger.info("🎛️ OSC Controller listening on port \(self?.port ?? 0)")
                    case .failed(let error):
                        self?.logger.warning("🎛️ OSC Controller failed: \(error)")
                        self?.isConnected = false
                    default:
                        break
                    }
                }
            }
            
            listener?.start(queue: .main)
            isEnabled = true
            
        } catch {
            logger.warning("🎛️ Failed to start OSC listener: \(error) - OSC will be unavailable")
            isEnabled = false
        }
    }
    
    func stopListening() {
        listener?.cancel()
        listener = nil
        connection?.cancel()
        connection = nil
        isConnected = false
        isEnabled = false
        logger.info("🎛️ OSC Controller stopped")
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        self.connection = connection
        
        connection.start(queue: .main)
        receiveMessages(on: connection)
        
        logger.info("🎛️ New OSC connection established")
    }
    
    // MARK: - Message Handling
    
    private func receiveMessages(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                Task { @MainActor in
                    self?.processOSCData(data)
                }
            }
            
            if let error = error {
                self?.logger.error("🎛️ OSC receive error: \(error)")
                return
            }
            
            if !isComplete {
                self?.receiveMessages(on: connection)
            }
        }
    }
    
    private func processOSCData(_ data: Data) {
        guard let message = parseOSCMessage(data) else { return }
        
        logger.debug("🎛️ Received OSC message: \(message.address) with \(message.arguments.count) arguments")
        
        if learnMode {
            handleLearnMode(message)
        } else {
            handleMappedMessage(message)
        }
    }
    
    private func handleMappedMessage(_ message: OSCMessage) {
        guard let mapping = parameterMappings[message.address],
              let outputMappingManager = outputMappingManager else { return }
        
        // Extract first argument as float value
        guard let floatValue = message.arguments.first as? Float else { return }
        
        // Apply mapping transformation
        let normalizedValue = (floatValue - mapping.inputRange.min) / (mapping.inputRange.max - mapping.inputRange.min)
        let mappedValue = mapping.outputRange.min + normalizedValue * (mapping.outputRange.max - mapping.outputRange.min)
        
        // Apply to output mapping parameter
        switch mapping.parameter {
        case .positionX:
            outputMappingManager.setPosition(CGPoint(
                x: CGFloat(mappedValue),
                y: outputMappingManager.currentMapping.position.y
            ))
        case .positionY:
            outputMappingManager.setPosition(CGPoint(
                x: outputMappingManager.currentMapping.position.x,
                y: CGFloat(mappedValue)
            ))
        case .sizeWidth:
            outputMappingManager.setSize(CGSize(
                width: CGFloat(mappedValue),
                height: outputMappingManager.currentMapping.size.height
            ))
        case .sizeHeight:
            outputMappingManager.setSize(CGSize(
                width: outputMappingManager.currentMapping.size.width,
                height: CGFloat(mappedValue)
            ))
        case .scale:
            outputMappingManager.setScale(CGFloat(mappedValue))
        case .rotation:
            outputMappingManager.setRotation(mappedValue)
        case .opacity:
            outputMappingManager.setOpacity(mappedValue)
        case .preset:
            // Handle preset selection
            let presetIndex = Int(mappedValue)
            if presetIndex < outputMappingManager.presets.count {
                let preset = outputMappingManager.presets[presetIndex]
                outputMappingManager.applyPreset(preset)
            }
        }
        
        logger.debug("🎛️ Applied OSC control")
    }
    
    private func handleLearnMode(_ message: OSCMessage) {
        // In learn mode, we can dynamically create mappings
        logger.info("🎛️ Learn mode: Received \(message.address)")
        
        // Here you could implement a UI to let users assign this address to a parameter
        // For now, we'll just log it
    }
    
    // MARK: - Parameter Mapping Management
    
    func addParameterMapping(address: String, parameter: OSCMappableParameter, inputRange: OSCRange, outputRange: OSCRange) {
        let mapping = OSCParameterMapping(
            address: address,
            parameter: parameter,
            inputRange: inputRange,
            outputRange: outputRange
        )
        parameterMappings[address] = mapping
        
        logger.info("🎛️ Added OSC mapping")
    }
    
    func removeParameterMapping(address: String) {
        parameterMappings.removeValue(forKey: address)
        logger.info("🎛️ Removed OSC mapping")
    }
    
    private func setupDefaultMappings() {
        // Set up some default OSC mappings
        addParameterMapping(
            address: "/vistaview/output/position/x",
            parameter: .positionX,
            inputRange: OSCRange(min: 0.0, max: 1.0),
            outputRange: OSCRange(min: 0.0, max: 1.0)
        )
        
        addParameterMapping(
            address: "/vistaview/output/position/y",
            parameter: .positionY,
            inputRange: OSCRange(min: 0.0, max: 1.0),
            outputRange: OSCRange(min: 0.0, max: 1.0)
        )
        
        addParameterMapping(
            address: "/vistaview/output/scale",
            parameter: .scale,
            inputRange: OSCRange(min: 0.0, max: 1.0),
            outputRange: OSCRange(min: 0.1, max: 3.0)
        )
        
        addParameterMapping(
            address: "/vistaview/output/rotation",
            parameter: .rotation,
            inputRange: OSCRange(min: 0.0, max: 1.0),
            outputRange: OSCRange(min: -180.0, max: 180.0)
        )
        
        addParameterMapping(
            address: "/vistaview/output/opacity",
            parameter: .opacity,
            inputRange: OSCRange(min: 0.0, max: 1.0),
            outputRange: OSCRange(min: 0.0, max: 1.0)
        )
    }
    
    // MARK: - OSC Message Parsing
    
    private func parseOSCMessage(_ data: Data) -> OSCMessage? {
        guard data.count >= 4 else { return nil }
        
        var offset = 0
        
        // Parse address
        guard let address = parseOSCString(data, offset: &offset) else { return nil }
        
        // Align to 4-byte boundary
        while offset % 4 != 0 { offset += 1 }
        
        // Parse type tag string
        guard let typeTag = parseOSCString(data, offset: &offset) else { return nil }
        
        // Align to 4-byte boundary
        while offset % 4 != 0 { offset += 1 }
        
        // Parse arguments based on type tag
        var arguments: [Any] = []
        
        for char in typeTag.dropFirst() { // Skip the comma
            switch char {
            case "f": // Float
                guard offset + 4 <= data.count else { return nil }
                let floatValue = data.withUnsafeBytes { bytes in
                    let value = bytes.load(fromByteOffset: offset, as: UInt32.self)
                    return Float(bitPattern: CFSwapInt32BigToHost(value))
                }
                arguments.append(floatValue)
                offset += 4
                
            case "i": // Integer
                guard offset + 4 <= data.count else { return nil }
                let intValue = data.withUnsafeBytes { bytes in
                    bytes.load(fromByteOffset: offset, as: Int32.self).bigEndian
                }
                arguments.append(intValue)
                offset += 4
                
            case "s": // String
                guard let stringValue = parseOSCString(data, offset: &offset) else { return nil }
                arguments.append(stringValue)
                while offset % 4 != 0 { offset += 1 }
                
            default:
                // Unsupported type, skip
                break
            }
        }
        
        return OSCMessage(address: address, arguments: arguments)
    }
    
    private func parseOSCString(_ data: Data, offset: inout Int) -> String? {
        guard offset < data.count else { return nil }
        
        var endOffset = offset
        while endOffset < data.count && data[endOffset] != 0 {
            endOffset += 1
        }
        
        guard endOffset < data.count else { return nil }
        
        let stringData = data.subdata(in: offset..<endOffset)
        let string = String(data: stringData, encoding: .utf8)
        
        offset = endOffset + 1 // Skip null terminator
        
        return string
    }
}

// MARK: - Supporting Types

struct OSCMessage {
    let address: String
    let arguments: [Any]
}

struct OSCParameterMapping {
    let address: String
    let parameter: OSCMappableParameter
    let inputRange: OSCRange
    let outputRange: OSCRange
}

struct OSCRange {
    let min: Float
    let max: Float
}

enum OSCMappableParameter: String, CaseIterable {
    case positionX = "Position X"
    case positionY = "Position Y"
    case sizeWidth = "Size Width"
    case sizeHeight = "Size Height"
    case scale = "Scale"
    case rotation = "Rotation"
    case opacity = "Opacity"
    case preset = "Preset"
}