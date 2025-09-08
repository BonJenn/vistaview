import SwiftUI

struct EffectsListPanel: View {
    @ObservedObject var effectManager: EffectManager
    @ObservedObject var previewProgramManager: PreviewProgramManager
    @State private var selectedOutput: OutputType = .preview
    
    enum OutputType: String, CaseIterable {
        case preview = "Preview"
        case program = "Program"
        
        var color: Color {
            switch self {
            case .preview: return .yellow
            case .program: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .preview: return "eye"
            case .program: return "tv"
            }
        }
    }
    
    private var currentChain: EffectChain? {
        switch selectedOutput {
        case .preview:
            return effectManager.getPreviewEffectChain()
        case .program:
            return effectManager.getProgramEffectChain()
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with output selector
            VStack(spacing: 8) {
                HStack {
                    Text("Applied Effects")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: clearCurrentEffects) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(currentChain?.effects.isEmpty ?? true)
                }
                
                // Output Type Picker
                Picker("Output", selection: $selectedOutput) {
                    ForEach(OutputType.allCases, id: \.self) { output in
                        HStack {
                            Image(systemName: output.icon)
                                .foregroundColor(output.color)
                            Text(output.rawValue)
                        }
                        .tag(output)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            
            Divider()
            
            // Effects List
            if let chain = currentChain {
                EffectsChainListView(
                    effectChain: chain,
                    effectManager: effectManager,
                    outputType: selectedOutput
                )
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "wand.and.stars.inverse")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    
                    Text("No Effects Applied")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Drag effects from the Effects tab onto the \(selectedOutput.rawValue) monitor")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .environmentObject(effectManager)
    }
    
    private func clearCurrentEffects() {
        switch selectedOutput {
        case .preview:
            previewProgramManager.clearPreviewEffects()
        case .program:
            previewProgramManager.clearProgramEffects()
        }
    }
}

struct EffectsChainListView: View {
    @ObservedObject var effectChain: EffectChain
    @ObservedObject var effectManager: EffectManager
    let outputType: EffectsListPanel.OutputType
    @State private var draggedEffect: (any VideoEffect)?
    
    var body: some View {
        VStack(spacing: 0) {
            // Chain controls
            HStack {
                Toggle("Enable All", isOn: $effectChain.isEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: outputType.color))
                
                Spacer()
                
                Text("Opacity")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Slider(value: $effectChain.opacity, in: 0...1)
                    .frame(width: 80)
                    .accentColor(outputType.color)
                
                Text("\(Int(effectChain.opacity * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 35, alignment: .trailing)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            
            Divider()
            
            // Effects List
            ScrollView {
                LazyVStack(spacing: 4) {
                    if effectChain.effects.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "tray")
                                .font(.title)
                                .foregroundColor(.secondary)
                            
                            Text("No effects in \(outputType.rawValue.lowercased())")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(Array(effectChain.effects.enumerated()), id: \.1.id) { index, effect in
                            EffectListItemView(
                                effect: effect as! BaseVideoEffect,
                                index: index,
                                totalCount: effectChain.effects.count,
                                outputType: outputType,
                                onRemove: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        effectChain.removeEffect(at: index)
                                    }
                                },
                                onMoveUp: index > 0 ? {
                                    let fromIndex = IndexSet(integer: index)
                                    effectChain.moveEffect(from: fromIndex, to: index - 1)
                                } : nil,
                                onMoveDown: index < effectChain.effects.count - 1 ? {
                                    let fromIndex = IndexSet(integer: index)
                                    effectChain.moveEffect(from: fromIndex, to: index + 2)
                                } : nil
                            )
                            .transition(.asymmetric(
                                insertion: .slide.combined(with: .opacity),
                                removal: .scale.combined(with: .opacity)
                            ))
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
    }
}

struct EffectListItemView: View {
    @ObservedObject var effect: BaseVideoEffect
    let index: Int
    let totalCount: Int
    let outputType: EffectsListPanel.OutputType
    let onRemove: () -> Void
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Effect Header
            HStack(spacing: 8) {
                // Order number
                Text("\(index + 1)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(outputType.color)
                    .clipShape(Circle())
                
                // Effect icon and name
                Image(systemName: effect.icon)
                    .font(.caption)
                    .foregroundColor(effect.category.color)
                    .frame(width: 16)
                
                Text(effect.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Effect controls
                HStack(spacing: 4) {
                    // Move buttons
                    if let onMoveUp = onMoveUp {
                        Button(action: onMoveUp) {
                            Image(systemName: "chevron.up")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    if let onMoveDown = onMoveDown {
                        Button(action: onMoveDown) {
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Expand/collapse
                    Button(action: {
                        if effect is ChromaKeyEffect {
                            // OPEN IMMEDIATELY for Chroma Key (no animation)
                            isExpanded.toggle()
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Enable/disable toggle
                    Toggle("", isOn: $effect.isEnabled)
                        .toggleStyle(SwitchToggleStyle(tint: effect.category.color))
                        .scaleEffect(0.8)
                    
                    // Remove button
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(effect.isEnabled ? Color.gray.opacity(0.1) : Color.gray.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(effect.category.color.opacity(effect.isEnabled ? 0.3 : 0.1), lineWidth: 1)
                    )
            )
            
            // Effect Parameters (expandable)
            if isExpanded && !effect.parameters.isEmpty {
                VStack(spacing: 6) {
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
                        Button("Reset Parameters") {
                            effect.reset()
                        }
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                // Open instantly for Chroma Key, otherwise animate
                .transition((effect is ChromaKeyEffect) ? .identity : .slide.combined(with: .opacity))
            }
        }
        .contextMenu {
            Button("Duplicate") {
                // TODO: Implement effect duplication
            }
            
            if onMoveUp != nil {
                Button("Move Up") {
                    onMoveUp?()
                }
            }
            
            if onMoveDown != nil {
                Button("Move Down") {
                    onMoveDown?()
                }
            }
            
            Divider()
            
            Button("Remove", role: .destructive) {
                onRemove()
            }
        }
    }
}