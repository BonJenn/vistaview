import Foundation
import AppKit
import Carbon
import OSLog

@MainActor
class HotkeyController: ObservableObject {
    @Published var isEnabled: Bool = false
    @Published var registeredHotkeys: [String] = []
    @Published var hasAccessibilityPermission: Bool = false
    
    private let logger = Logger(subsystem: "com.vantaview.app", category: "Hotkeys")
    private var eventTap: CFMachPort?
    
    // Weak reference to avoid retain cycles
    weak var outputMappingManager: OutputMappingManager?
    
    // Hotkey mappings
    private var hotkeyMappings: [HotkeyMapping] = []
    
    init() {
        checkAccessibilityPermission()
        setupDefaultHotkeys()
    }
    
    deinit {
        Task { @MainActor in
            self.disableHotkeys()
        }
    }
    
    // MARK: - Permission Checking
    
    private func checkAccessibilityPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
        if !hasAccessibilityPermission {
            logger.warning("⌨️ Accessibility permission not granted - hotkeys will be disabled")
        }
    }
    
    func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - Hotkey Management
    
    func enableHotkeys() {
        guard !isEnabled else { return }
        
        checkAccessibilityPermission()
        guard hasAccessibilityPermission else {
            logger.warning("⌨️ Cannot enable hotkeys - accessibility permission required")
            return
        }
        
        // Create event tap
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                
                let controller = Unmanaged<HotkeyController>.fromOpaque(refcon).takeUnretainedValue()
                
                if controller.handleKeyEvent(event) {
                    // Consume the event
                    return nil
                } else {
                    // Pass the event through
                    return Unmanaged.passUnretained(event)
                }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        guard let eventTap = eventTap else {
            logger.error("⌨️ Failed to create event tap")
            return
        }
        
        // Enable the event tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        isEnabled = true
        logger.info("⌨️ Hotkey controller enabled")
    }
    
    func disableHotkeys() {
        guard isEnabled else { return }
        
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        
        isEnabled = false
        logger.info("⌨️ Hotkey controller disabled")
    }
    
    private func handleKeyEvent(_ event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        
        // Check if this matches any of our hotkey mappings
        for mapping in hotkeyMappings {
            if mapping.matches(keyCode: Int(keyCode), flags: flags) {
                executeHotkeyAction(mapping.action)
                return true // Consume the event
            }
        }
        
        return false // Don't consume the event
    }
    
    private func executeHotkeyAction(_ action: HotkeyAction) {
        guard let outputMappingManager = outputMappingManager else { return }
        
        switch action {
        case .togglePanel:
            outputMappingManager.toggleMappingPanel()
            
        case .fitToScreen:
            outputMappingManager.fitToScreen()
            
        case .centerOutput:
            outputMappingManager.centerOutput()
            
        case .resetMapping:
            outputMappingManager.resetMapping()
            
        case .toggleEnabled:
            outputMappingManager.isEnabled.toggle()
            
        case .nextPreset:
            if let currentIndex = outputMappingManager.presets.firstIndex(where: { $0.id == outputMappingManager.selectedPreset?.id }),
               currentIndex < outputMappingManager.presets.count - 1 {
                let nextPreset = outputMappingManager.presets[currentIndex + 1]
                outputMappingManager.applyPreset(nextPreset)
            } else if !outputMappingManager.presets.isEmpty {
                outputMappingManager.applyPreset(outputMappingManager.presets[0])
            }
            
        case .previousPreset:
            if let currentIndex = outputMappingManager.presets.firstIndex(where: { $0.id == outputMappingManager.selectedPreset?.id }),
               currentIndex > 0 {
                let previousPreset = outputMappingManager.presets[currentIndex - 1]
                outputMappingManager.applyPreset(previousPreset)
            } else if !outputMappingManager.presets.isEmpty {
                outputMappingManager.applyPreset(outputMappingManager.presets.last!)
            }
            
        case .applyPreset(let index):
            if index < outputMappingManager.presets.count {
                let preset = outputMappingManager.presets[index]
                outputMappingManager.applyPreset(preset)
            }
        }
        
        logger.info("⌨️ Executed hotkey action")
    }
    
    // MARK: - Hotkey Configuration
    
    private func setupDefaultHotkeys() {
        hotkeyMappings = [
            HotkeyMapping(
                keyCode: kVK_Space,
                modifiers: [.command, .shift],
                action: .togglePanel,
                description: "⌘⇧Space - Toggle Output Mapping Panel"
            ),
            HotkeyMapping(
                keyCode: 0x03, // F key
                modifiers: [.command, .option],
                action: .fitToScreen,
                description: "⌘⌥F - Fit to Screen"
            ),
            HotkeyMapping(
                keyCode: 0x08, // C key
                modifiers: [.command, .option],
                action: .centerOutput,
                description: "⌘⌥C - Center Output"
            ),
            HotkeyMapping(
                keyCode: 0x0F, // R key
                modifiers: [.command, .option],
                action: .resetMapping,
                description: "⌘⌥R - Reset Mapping"
            ),
            HotkeyMapping(
                keyCode: 0x0E, // E key
                modifiers: [.command, .option],
                action: .toggleEnabled,
                description: "⌘⌥E - Toggle Output Mapping"
            ),
            HotkeyMapping(
                keyCode: kVK_RightArrow,
                modifiers: [.command, .option],
                action: .nextPreset,
                description: "⌘⌥→ - Next Preset"
            ),
            HotkeyMapping(
                keyCode: kVK_LeftArrow,
                modifiers: [.command, .option],
                action: .previousPreset,
                description: "⌘⌥← - Previous Preset"
            )
        ]
        
        // Add number key presets (1-9)
        for i in 0..<9 {
            let keyCode = kVK_ANSI_1 + i
            hotkeyMappings.append(HotkeyMapping(
                keyCode: keyCode,
                modifiers: [.command, .option],
                action: .applyPreset(i),
                description: "⌘⌥\(i + 1) - Apply Preset \(i + 1)"
            ))
        }
        
        registeredHotkeys = self.hotkeyMappings.map { $0.description }
        logger.info("⌨️ Setup \(self.hotkeyMappings.count) default hotkeys")
    }
    
    func addCustomHotkey(keyCode: Int, modifiers: NSEvent.ModifierFlags, action: HotkeyAction, description: String) {
        let mapping = HotkeyMapping(
            keyCode: keyCode,
            modifiers: modifiers,
            action: action,
            description: description
        )
        hotkeyMappings.append(mapping)
        registeredHotkeys.append(description)
        
        logger.info("⌨️ Added custom hotkey: \(description)")
    }
    
    func removeHotkey(at index: Int) {
        guard index < hotkeyMappings.count else { return }
        
        let removed = hotkeyMappings.remove(at: index)
        registeredHotkeys.remove(at: index)
        
        logger.info("⌨️ Removed hotkey: \(removed.description)")
    }
}

// MARK: - Supporting Types

struct HotkeyMapping {
    let keyCode: Int
    let modifiers: NSEvent.ModifierFlags
    let action: HotkeyAction
    let description: String
    
    func matches(keyCode: Int, flags: CGEventFlags) -> Bool {
        guard self.keyCode == keyCode else { return false }
        
        let nsFlags = NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue))
        let requiredFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        
        return (nsFlags.intersection(requiredFlags)) == modifiers
    }
}

enum HotkeyAction: Equatable {
    case togglePanel
    case fitToScreen
    case centerOutput
    case resetMapping
    case toggleEnabled
    case nextPreset
    case previousPreset
    case applyPreset(Int)
}
