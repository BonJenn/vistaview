//
//  ObjectPropertiesView.swift
//  Vantaview - Raycast-Inspired Object Properties
//

import SwiftUI
import SceneKit

struct ObjectPropertiesView: View {
    @ObservedObject var object: StudioObject
    var transformController: TransformController? = nil
    @State private var showingAdvanced = false
    @State private var editingName = false
    @State private var tempName = ""
    
    // Raycast spacing system
    private let spacing1: CGFloat = 4
    private let spacing2: CGFloat = 8
    private let spacing3: CGFloat = 16
    
    var body: some View {
        VStack(alignment: .leading, spacing: spacing3) {
            // Transform mode indicator
            if let transformController = transformController, transformController.isActive {
                transformModeIndicator
            }
            
            // Enhanced object header with Raycast styling
            objectHeader
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            // Transform properties with enhanced UI
            if let transformController = transformController {
                transformSection(transformController: transformController)
            }
            
            // Visibility and layer controls
            visibilitySection
            
            // Type-specific properties
            if showingAdvanced {
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                typeSpecificProperties
            }
            
            // Advanced toggle
            advancedToggle
            
            Spacer()
        }
        .onAppear {
            tempName = object.name
        }
    }
    
    private var objectHeader: some View {
        VStack(alignment: .leading, spacing: spacing2) {
            HStack(spacing: spacing2) {
                // Enhanced icon with background
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.blue.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: object.type.icon)
                        .font(.system(.title2, design: .default, weight: .semibold))
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    // Enhanced name field with proper state management
                    Group {
                        if editingName {
                            TextField("Object Name", text: $tempName)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.headline, design: .default, weight: .medium))
                                .onSubmit {
                                    commitNameChange()
                                }
                                .onExitCommand {
                                    cancelNameEdit()
                                }
                        } else {
                            Button(action: {
                                startNameEdit()
                            }) {
                                Text(object.name)
                                    .font(.system(.headline, design: .default, weight: .medium))
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Type badge with better styling
                    HStack(spacing: spacing1) {
                        Text(object.type.name)
                            .font(.system(.caption, design: .default, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("ID: \(String(object.id.uuidString.prefix(8)))")
                            .font(.system(.caption2, design: .monospaced, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, spacing3)
    }
    
    private func transformSection(transformController: TransformController) -> some View {
        VStack(alignment: .leading, spacing: spacing2) {
            // Section header with Raycast styling
            sectionHeader(title: "Transform", icon: "move.3d")
            
            VStack(spacing: spacing3) {
                // Position controls
                transformGroup(title: "Position", icon: "location") {
                    HStack(spacing: spacing2) {
                        transformField(
                            label: "X",
                            color: .red,
                            value: Binding(
                                get: { Double(object.position.x) },
                                set: { newValue in
                                    let clampedValue = max(-1000, min(1000, newValue))
                                    object.position.x = CGFloat(clampedValue)
                                    object.updateNodeTransform()
                                }
                            )
                        )
                        transformField(
                            label: "Y",
                            color: .green,
                            value: Binding(
                                get: { Double(object.position.y) },
                                set: { newValue in
                                    let clampedValue = max(-1000, min(1000, newValue))
                                    object.position.y = CGFloat(clampedValue)
                                    object.updateNodeTransform()
                                }
                            )
                        )
                        transformField(
                            label: "Z",
                            color: .blue,
                            value: Binding(
                                get: { Double(object.position.z) },
                                set: { newValue in
                                    let clampedValue = max(-1000, min(1000, newValue))
                                    object.position.z = CGFloat(clampedValue)
                                    object.updateNodeTransform()
                                }
                            )
                        )
                    }
                }
                
                // Rotation controls
                transformGroup(title: "Rotation", icon: "rotate.3d") {
                    HStack(spacing: spacing2) {
                        transformField(
                            label: "X",
                            color: .red,
                            value: Binding(
                                get: { Double(object.rotation.x * 180 / .pi) },
                                set: { newValue in
                                    let normalizedValue = newValue.truncatingRemainder(dividingBy: 360)
                                    object.rotation.x = CGFloat(normalizedValue * .pi / 180)
                                    object.updateNodeTransform()
                                }
                            ),
                            suffix: "°"
                        )
                        transformField(
                            label: "Y",
                            color: .green,
                            value: Binding(
                                get: { Double(object.rotation.y * 180 / .pi) },
                                set: { newValue in
                                    let normalizedValue = newValue.truncatingRemainder(dividingBy: 360)
                                    object.rotation.y = CGFloat(normalizedValue * .pi / 180)
                                    object.updateNodeTransform()
                                }
                            ),
                            suffix: "°"
                        )
                        transformField(
                            label: "Z",
                            color: .blue,
                            value: Binding(
                                get: { Double(object.rotation.z * 180 / .pi) },
                                set: { newValue in
                                    let normalizedValue = newValue.truncatingRemainder(dividingBy: 360)
                                    object.rotation.z = CGFloat(normalizedValue * .pi / 180)
                                    object.updateNodeTransform()
                                }
                            ),
                            suffix: "°"
                        )
                    }
                }
                
                // Scale controls
                transformGroup(title: "Scale", icon: "arrow.up.left.and.arrow.down.right") {
                    HStack(spacing: spacing2) {
                        transformField(
                            label: "X",
                            color: .red,
                            value: Binding(
                                get: { Double(object.scale.x) },
                                set: { newValue in
                                    let clampedValue = max(0.01, min(100, newValue))
                                    object.scale.x = CGFloat(clampedValue)
                                    object.updateNodeTransform()
                                }
                            )
                        )
                        transformField(
                            label: "Y",
                            color: .green,
                            value: Binding(
                                get: { Double(object.scale.y) },
                                set: { newValue in
                                    let clampedValue = max(0.01, min(100, newValue))
                                    object.scale.y = CGFloat(clampedValue)
                                    object.updateNodeTransform()
                                }
                            )
                        )
                        transformField(
                            label: "Z",
                            color: .blue,
                            value: Binding(
                                get: { Double(object.scale.z) },
                                set: { newValue in
                                    let clampedValue = max(0.01, min(100, newValue))
                                    object.scale.z = CGFloat(clampedValue)
                                    object.updateNodeTransform()
                                }
                            )
                        )
                    }
                }
            }
        }
        .padding(.horizontal, spacing3)
    }
    
    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: spacing2) {
            sectionHeader(title: "Visibility", icon: "eye")
            
            VStack(spacing: spacing2) {
                // Visibility toggle with enhanced styling
                HStack {
                    Toggle(isOn: Binding(
                        get: { object.isVisible },
                        set: { newValue in
                            object.isVisible = newValue
                            object.updateNodeTransform()
                        }
                    )) {
                        HStack(spacing: spacing2) {
                            Image(systemName: object.isVisible ? "eye" : "eye.slash")
                                .font(.system(.callout, design: .default, weight: .medium))
                                .foregroundColor(object.isVisible ? .blue : .secondary)
                            
                            Text("Visible in Scene")
                                .font(.system(.body, design: .default, weight: .regular))
                        }
                    }
                    .toggleStyle(.switch)
                }
                
                // Selection state indicator
                HStack {
                    Image(systemName: object.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(.callout, design: .default, weight: .medium))
                        .foregroundColor(object.isSelected ? .blue : .secondary)
                    
                    Text("Selected")
                        .font(.system(.body, design: .default, weight: .regular))
                        .foregroundColor(object.isSelected ? .primary : .secondary)
                    
                    Spacer()
                }
            }
        }
        .padding(.horizontal, spacing3)
    }
    
    private var typeSpecificProperties: some View {
        VStack(alignment: .leading, spacing: spacing3) {
            sectionHeader(title: "\(object.type.name) Properties", icon: object.type.icon)
            
            switch object.type {
            case .ledWall:
                ledWallAdvancedProperties
            case .camera:
                cameraAdvancedProperties
            case .setPiece:
                setPieceAdvancedProperties
            case .light:
                lightAdvancedProperties
            default:
                Text("No advanced properties available")
                    .font(.system(.caption, design: .default, weight: .regular))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, spacing3)
    }
    
    private var advancedToggle: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                showingAdvanced.toggle()
            }
        }) {
            HStack(spacing: spacing2) {
                Image(systemName: showingAdvanced ? "chevron.down" : "chevron.right")
                    .font(.system(.caption, design: .default, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text("Advanced Properties")
                    .font(.system(.body, design: .default, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
                
                if showingAdvanced {
                    Text("Hide")
                        .font(.system(.caption, design: .default, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, spacing3)
            .padding(.vertical, spacing2)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, spacing3)
    }
    
    private var transformModeIndicator: some View {
        HStack(spacing: spacing2) {
            Image(systemName: "move.3d")
                .font(.system(.callout, design: .default, weight: .semibold))
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Transform Mode: \(transformController?.mode.instruction ?? "")")
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundColor(.blue)
                
                Text("Axis: \(transformController?.axis.label ?? "")")
                    .font(.system(.caption2, design: .default, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, spacing3)
        .padding(.vertical, spacing2)
        .background(.blue.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal, spacing3)
    }
    
    // MARK: - Helper Functions
    
    private func startNameEdit() {
        tempName = object.name
        editingName = true
    }
    
    private func commitNameChange() {
        let trimmedName = tempName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            object.name = trimmedName
            object.node.name = trimmedName
        }
        editingName = false
    }
    
    private func cancelNameEdit() {
        tempName = object.name
        editingName = false
    }
    
    // MARK: - Helper Components
    
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: spacing2) {
            Image(systemName: icon)
                .font(.system(.callout, design: .default, weight: .medium))
                .foregroundColor(.blue)
            
            Text(title)
                .font(.system(.callout, design: .default, weight: .semibold))
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
    
    private func transformGroup<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: spacing1) {
            HStack(spacing: spacing1) {
                Image(systemName: icon)
                    .font(.system(.caption, design: .default, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 12)
                
                Text(title)
                    .font(.system(.caption, design: .default, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            content()
        }
    }
    
    private func transformField(label: String, color: Color, value: Binding<Double>, suffix: String = "") -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(.caption2, design: .default, weight: .semibold))
                    .foregroundColor(color)
                
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.system(.caption2, design: .default, weight: .regular))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            TextField(label, value: value, format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced, weight: .regular))
        }
    }
    
    // MARK: - Type-Specific Properties
    
    private var ledWallAdvancedProperties: some View {
        VStack(alignment: .leading, spacing: spacing2) {
            propertyRow(icon: "tv", title: "Resolution", value: "1920×1080")
            propertyRow(icon: "light.max", title: "Brightness", value: "5000 nits")
            propertyRow(icon: "grid", title: "Pixel Pitch", value: "2.5mm")
            
            Button("Configure Display Settings") {
                // Open LED wall configuration
                print("Opening LED wall configuration for \(object.name)")
            }
            .font(.system(.caption, design: .default, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(6)
        }
    }
    
    private var cameraAdvancedProperties: some View {
        VStack(alignment: .leading, spacing: spacing2) {
            propertyRow(icon: "camera.viewfinder", title: "FOV", value: "60°")
            propertyRow(icon: "focus", title: "Focal Length", value: "50mm")
            propertyRow(icon: "aspectratio", title: "Aspect", value: "16:9")
            
            Button("Camera Settings") {
                // Open camera configuration
                print("Opening camera settings for \(object.name)")
            }
            .font(.system(.caption, design: .default, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(6)
        }
    }
    
    private var setPieceAdvancedProperties: some View {
        VStack(alignment: .leading, spacing: spacing2) {
            propertyRow(icon: "cube", title: "Material", value: "Default")
            propertyRow(icon: "paintbrush", title: "Color", value: "Gray")
            propertyRow(icon: "weight", title: "Physics", value: "Static")
            
            Button("Material Editor") {
                // Open material editor
                print("Opening material editor for \(object.name)")
            }
            .font(.system(.caption, design: .default, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(6)
        }
    }
    
    private var lightAdvancedProperties: some View {
        VStack(alignment: .leading, spacing: spacing2) {
            propertyRow(icon: "lightbulb", title: "Type", value: "Directional")
            propertyRow(icon: "sun.max", title: "Intensity", value: "1000 lm")
            propertyRow(icon: "thermometer", title: "Temperature", value: "5600K")
            
            Button("Lighting Controls") {
                // Open lighting controls
                print("Opening lighting controls for \(object.name)")
            }
            .font(.system(.caption, design: .default, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(6)
        }
    }
    
    private func propertyRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: spacing2) {
            Image(systemName: icon)
                .font(.system(.caption, design: .default, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 16)
            
            Text(title)
                .font(.system(.caption, design: .default, weight: .regular))
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, spacing2)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(4)
    }
}