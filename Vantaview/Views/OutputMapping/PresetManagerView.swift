import SwiftUI
import UniformTypeIdentifiers

struct PresetManagerView: View {
    @ObservedObject var mappingManager: OutputMappingManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPresets = Set<UUID>()
    @State private var editingPreset: OutputMappingPreset?
    @State private var showDeleteAlert = false
    @State private var presetToDelete: OutputMappingPreset?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Preset Manager")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                
                Divider()
                
                // Preset List
                if mappingManager.presets.isEmpty {
                    emptyStateView
                } else {
                    presetListView
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .alert("Delete Preset", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let preset = presetToDelete {
                    mappingManager.deletePreset(preset)
                }
                presetToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                presetToDelete = nil
            }
        } message: {
            if let preset = presetToDelete {
                Text("Are you sure you want to delete the preset '\(preset.name)'? This action cannot be undone.")
            }
        }
        .sheet(item: $editingPreset) { preset in
            PresetEditView(preset: preset, mappingManager: mappingManager)
        }
    }
    
    // MARK: - Empty State
    
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Presets")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Create your first output mapping preset by adjusting the settings and saving them.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Close and Create Preset") {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    mappingManager.showPanel()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Preset List
    
    @ViewBuilder
    private var presetListView: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("\(mappingManager.presets.count) presets")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: { selectedPresets.removeAll() }) {
                    Text("Deselect All")
                }
                .disabled(selectedPresets.isEmpty)
                
                if !selectedPresets.isEmpty {
                    Button(action: deleteSelectedPresets) {
                        Label("Delete Selected", systemImage: "trash")
                    }
                    .foregroundColor(.red)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // List
            List(selection: $selectedPresets) {
                ForEach(mappingManager.presets) { preset in
                    PresetRowView(
                        preset: preset,
                        isSelected: mappingManager.selectedPreset?.id == preset.id,
                        onApply: { mappingManager.applyPreset(preset) },
                        onEdit: { editingPreset = preset },
                        onDuplicate: { mappingManager.duplicatePreset(preset) },
                        onDelete: { 
                            presetToDelete = preset
                            showDeleteAlert = true
                        }
                    )
                    .tag(preset.id)
                }
            }
            .listStyle(.inset)
        }
    }
    
    // MARK: - Actions
    
    private func deleteSelectedPresets() {
        let presetsToDelete = mappingManager.presets.filter { selectedPresets.contains($0.id) }
        for preset in presetsToDelete {
            mappingManager.deletePreset(preset)
        }
        selectedPresets.removeAll()
    }
}

// MARK: - Preset Row View

struct PresetRowView: View {
    let preset: OutputMappingPreset
    let isSelected: Bool
    let onApply: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Preview thumbnail
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.blue.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                        .overlay(
                            // Simple representation of the mapping
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.blue.opacity(0.6))
                                .frame(
                                    width: 40 * preset.mapping.size.width * preset.mapping.scale,
                                    height: 30 * preset.mapping.size.height * preset.mapping.scale
                                )
                                .position(
                                    x: 20 + preset.mapping.position.x * 40,
                                    y: 15 + preset.mapping.position.y * 30
                                )
                        )
                )
                .frame(width: 60, height: 45)
                .clipped()
            
            // Preset info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(preset.name)
                        .font(.headline)
                        .fontWeight(isSelected ? .semibold : .medium)
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                    }
                    
                    Spacer()
                }
                
                if let description = preset.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // Mapping details
                HStack(spacing: 8) {
                    Label("Pos: \(Int(preset.mapping.position.x * 1920)), \(Int(preset.mapping.position.y * 1080))", systemImage: "location")
                    Label("Size: \(Int(preset.mapping.size.width * 1920))×\(Int(preset.mapping.size.height * 1080))", systemImage: "aspectratio")
                    if preset.mapping.rotation != 0 {
                        Label("\(preset.mapping.rotation, specifier: "%.1f")°", systemImage: "rotate.right")
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 4) {
                Button("Apply") {
                    onApply()
                }
                .buttonStyle(.borderless)
                .foregroundColor(.blue)
                
                Menu {
                    Button("Edit", action: onEdit)
                    Button("Duplicate", action: onDuplicate)
                    Divider()
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Preset Edit View

struct PresetEditView: View {
    @State var preset: OutputMappingPreset
    let mappingManager: OutputMappingManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String
    @State private var description: String
    @State private var tags: String
    
    init(preset: OutputMappingPreset, mappingManager: OutputMappingManager) {
        self.preset = preset
        self.mappingManager = mappingManager
        self._name = State(initialValue: preset.name)
        self._description = State(initialValue: preset.description ?? "")
        self._tags = State(initialValue: preset.tags.joined(separator: ", "))
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Preset Information") {
                    TextField("Name", text: $name)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Tags (comma-separated)", text: $tags)
                }
                
                Section("Mapping Settings") {
                    HStack {
                        Text("Position:")
                        Spacer()
                        Text("X: \(Int(preset.mapping.position.x * 1920)), Y: \(Int(preset.mapping.position.y * 1080))")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Size:")
                        Spacer()
                        Text("\(Int(preset.mapping.size.width * 1920))×\(Int(preset.mapping.size.height * 1080))")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Scale:")
                        Spacer()
                        Text("\(preset.mapping.scale, specifier: "%.2f")x")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Rotation:")
                        Spacer()
                        Text("\(preset.mapping.rotation, specifier: "%.1f")°")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    Button("Update from Current Mapping") {
                        preset.mapping = mappingManager.currentMapping
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("Edit Preset")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePreset()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
    
    private func savePreset() {
        var updatedPreset = preset
        updatedPreset.name = name
        updatedPreset.description = description.isEmpty ? nil : description
        updatedPreset.tags = tags.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        updatedPreset.updatedAt = Date()
        
        mappingManager.updatePreset(updatedPreset)
    }
}

// MARK: - Export/Import View

struct ExportImportView: View {
    @ObservedObject var mappingManager: OutputMappingManager
    @Environment(\.dismiss) private var dismiss
    @State private var showFileExporter = false
    @State private var showFileImporter = false
    @State private var exportResult: String?
    @State private var importResult: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Export & Import Presets")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                // Export Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Export")
                        .font(.headline)
                    
                    Text("Export all your output mapping presets to share them or backup your configurations.")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Button(action: { showFileExporter = true }) {
                        Label("Export All Presets", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(mappingManager.presets.isEmpty)
                    
                    if let result = exportResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                // Import Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Import")
                        .font(.headline)
                    
                    Text("Import output mapping presets from a previously exported file.")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Button(action: { showFileImporter = true }) {
                        Label("Import Presets", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    
                    if let result = importResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(result.contains("Failed") ? .red : .green)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Export & Import")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .fileExporter(
            isPresented: $showFileExporter,
            document: PresetExportDocument(presets: mappingManager.presets),
            contentType: .json,
            defaultFilename: "VantaviewOutputPresets"
        ) { result in
            switch result {
            case .success(let url):
                exportResult = "Exported successfully to \(url.lastPathComponent)"
            case .failure(let error):
                exportResult = "Export failed: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    let success = mappingManager.importPresets(from: url)
                    importResult = success ? 
                        "Import successful! \(mappingManager.presets.count) presets loaded." :
                        "Import failed. Please check the file format."
                }
            case .failure(let error):
                importResult = "Import failed: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Export Document

struct PresetExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    let presets: [OutputMappingPreset]
    
    init(presets: [OutputMappingPreset]) {
        self.presets = presets
    }
    
    init(configuration: ReadConfiguration) throws {
        // Not needed for export-only document
        presets = []
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let collection = OutputMappingPresetCollection(presets: presets)
        let data = try JSONEncoder().encode(collection)
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Preview

#Preview {
    let manager = OutputMappingManager(metalDevice: MTLCreateSystemDefaultDevice()!)
    return PresetManagerView(mappingManager: manager)
}