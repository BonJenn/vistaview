import SwiftUI

struct EffectParameterPanel: View {
    @ObservedObject var effect: BaseVideoEffect
    @State private var isExpanded = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    if effect is ChromaKeyEffect {
                        // Open immediately for Chroma Key
                        isExpanded.toggle()
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Image(systemName: effect.icon)
                            .font(.caption)
                            .foregroundColor(effect.category.color)
                        
                        Text(effect.name)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        // Enable/Disable toggle
                        Toggle("", isOn: Binding(
                            get: { effect.isEnabled },
                            set: { effect.isEnabled = $0 }
                        ))
                        .toggleStyle(SwitchToggleStyle(tint: effect.category.color))
                        .scaleEffect(0.8)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            
            // Parameters
            if isExpanded {
                VStack(spacing: 8) {
                    if let ck = effect as? ChromaKeyEffect {
                        ChromaKeyControlsView(effect: ck)
                            .padding(.bottom, 4)
                    }
                    
                    ForEach(Array(effect.parameters.keys.sorted()), id: \.self) { key in
                        if let parameter = effect.parameters[key] {
                            EffectParameterSlider(
                                parameter: Binding(
                                    get: { effect.parameters[key] ?? parameter },
                                    set: { effect.parameters[key] = $0 }
                                ),
                                color: effect.category.color
                            )
                        }
                    }
                    
                    // Reset button
                    HStack {
                        Spacer()
                        Button("Reset") {
                            effect.reset()
                        }
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.2))
                        .foregroundColor(.red)
                        .cornerRadius(4)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                // Instant show for Chroma Key panel, animated for others
                .transition((effect is ChromaKeyEffect) ? .identity : .opacity.combined(with: .slide))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(effect.category.color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

struct EffectParameterSlider: View {
    @Binding var parameter: EffectParameter
    let color: Color
    @State private var isEditing = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(parameter.name)
                    .font(.caption2)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Value display/editor
                if isEditing {
                    TextField("", value: $parameter.value, format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 60)
                        .font(.caption2)
                        .onSubmit {
                            isEditing = false
                            // Clamp value to range
                            parameter.value = min(max(parameter.value, parameter.range.lowerBound), parameter.range.upperBound)
                        }
                } else {
                    Button(action: {
                        isEditing = true
                    }) {
                        Text(String(format: "%.2f", parameter.value))
                            .font(.caption2)
                            .foregroundColor(color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(color.opacity(0.2))
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            // Slider
            HStack {
                Text(String(format: "%.1f", parameter.range.lowerBound))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 30, alignment: .leading)
                
                Slider(
                    value: $parameter.value,
                    in: parameter.range,
                    step: parameter.step
                ) {
                    Text(parameter.name)
                } minimumValueLabel: {
                    EmptyView()
                } maximumValueLabel: {
                    EmptyView()
                }
                .accentColor(color)
                
                Text(String(format: "%.1f", parameter.range.upperBound))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }
        }
    }
}

// MARK: - Effect Chain Panel

struct EffectChainPanel: View {
    @ObservedObject var effectChain: EffectChain
    @ObservedObject var effectManager: EffectManager
    @State private var draggedEffect: (any VideoEffect)?
    
    var body: some View {
        VStack(spacing: 0) {
            // Chain Header
            HStack {
                Image(systemName: "link")
                    .foregroundColor(.blue)
                
                Text(effectChain.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Chain controls
                HStack(spacing: 8) {
                    Button(action: {
                        effectChain.isEnabled.toggle()
                    }) {
                        Image(systemName: effectChain.isEnabled ? "eye" : "eye.slash")
                            .foregroundColor(effectChain.isEnabled ? .blue : .gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: duplicateChain) {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            
            Divider()
            
            // Effects List
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(effectChain.effects.enumerated()), id: \.1.id) { index, effect in
                        EffectParameterPanel(effect: effect as! BaseVideoEffect)
                            .environmentObject(effectManager)
                            .onDrag {
                                draggedEffect = effect
                                return NSItemProvider(object: "\(index)" as NSString)
                            }
                            .onDrop(of: [.text], delegate: EffectDropDelegate(
                                chain: effectChain,
                                targetIndex: index,
                                draggedEffect: $draggedEffect
                            ))
                            .contextMenu {
                                Button("Duplicate") {
                                    duplicateEffect(at: index)
                                }
                                
                                Button("Remove", role: .destructive) {
                                    effectChain.removeEffect(at: index)
                                }
                            }
                    }
                    
                    // Drop zone for new effects
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 40)
                        .overlay(
                            HStack {
                                Image(systemName: "plus.circle.dashed")
                                    .foregroundColor(.secondary)
                                Text("Drop effects here")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        )
                        .onDrop(of: [.data], isTargeted: nil) { providers in
                            handleEffectDrop(providers)
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            
            Spacer()
        }
    }
    
    private func duplicateChain() {
        let _ = effectManager.duplicateChain(effectChain)
    }
    
    private func duplicateEffect(at index: Int) {
        guard index < effectChain.effects.count else { return }
        let effect = effectChain.effects[index]
        
        // Create duplicate - this would need proper effect duplication logic
        if let duplicatedEffect = createDuplicateEffect(effect) {
            effectChain.effects.insert(duplicatedEffect, at: index + 1)
        }
    }
    
    private func createDuplicateEffect(_ effect: any VideoEffect) -> (any VideoEffect)? {
        // This would properly duplicate effects based on their type
        return nil
    }
    
    private func handleEffectDrop(_ providers: [NSItemProvider]) -> Bool {
        // Handle dropping new effects onto the chain
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.data", options: nil) { data, error in
                if let data = data as? Data,
                   let effectType = String(data: data, encoding: .utf8),
                   let newEffect = effectManager.effectsLibrary.createEffect(ofType: effectType) {
                    
                    DispatchQueue.main.async {
                        effectChain.addEffect(newEffect)
                    }
                }
            }
        }
        return true
    }
}

// MARK: - Effect Drop Delegate

struct EffectDropDelegate: DropDelegate {
    let chain: EffectChain
    let targetIndex: Int
    @Binding var draggedEffect: (any VideoEffect)?
    
    func performDrop(info: DropInfo) -> Bool {
        guard let draggedEffect = draggedEffect else { return false }
        
        // Find the source index
        if let sourceIndex = chain.effects.firstIndex(where: { $0.id == draggedEffect.id }) {
            // Reorder within the same chain
            let fromIndex = IndexSet(integer: sourceIndex)
            chain.moveEffect(from: fromIndex, to: targetIndex)
        }
        
        self.draggedEffect = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        // Visual feedback when hovering over drop target
    }
    
    func dropExited(info: DropInfo) {
        // Remove visual feedback
    }
}