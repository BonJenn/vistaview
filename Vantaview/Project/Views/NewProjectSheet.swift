import SwiftUI
import UniformTypeIdentifiers

struct NewProjectSheet: View {
    @Binding var title: String
    @Binding var selectedTemplate: ProjectTemplate
    let recentProjectsManager: RecentProjectsManager
    let onProjectCreated: (ProjectState) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var mediaPolicy: ProjectManifest.MediaPolicy = .copy
    @State private var selectedDirectory: URL?
    @State private var isCreating = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("Create New Project")
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text("Choose a template and configure your project settings")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Project Settings
            Form {
                Section {
                    TextField("Project Title", text: $title)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Picker("Media Policy", selection: $mediaPolicy) {
                        ForEach(ProjectManifest.MediaPolicy.allCases, id: \.self) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    
                    HStack {
                        Text("Save Location:")
                        Spacer()
                        if let directory = selectedDirectory {
                            Text(directory.lastPathComponent)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Choose folder...")
                                .foregroundColor(.secondary)
                        }
                        
                        Button("Browse...") {
                            showDirectoryPicker()
                        }
                    }
                } header: {
                    Text("Project Settings")
                }
                
                Section {
                    TemplatePickerView(selectedTemplate: $selectedTemplate)
                } header: {
                    Text("Template")
                }
            }
            .formStyle(GroupedFormStyle())
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            // Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Create Project") {
                    createProject()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.isEmpty || selectedDirectory == nil || isCreating)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 600, height: 500)
        .onAppear {
            if selectedDirectory == nil {
                selectedDirectory = getDefaultProjectsDirectory()
            }
        }
    }
    
    private func showDirectoryPicker() {
        let panel = NSOpenPanel()
        panel.title = "Choose Project Location"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            selectedDirectory = url
        }
    }
    
    private func getDefaultProjectsDirectory() -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent("Vantaview Projects")
    }
    
    private func createProject() {
        guard let directory = selectedDirectory else { return }
        
        isCreating = true
        errorMessage = nil
        
        Task { @MainActor in
            do {
                let projectManager = ProjectManager()
                
                // Ensure directory exists
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                
                let projectState = try await projectManager.createProject(
                    title: title,
                    template: selectedTemplate,
                    mediaPolicy: mediaPolicy,
                    at: directory
                )
                
                onProjectCreated(projectState)
                dismiss()
                
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}

struct TemplatePickerView: View {
    @Binding var selectedTemplate: ProjectTemplate
    
    private let columns = [
        GridItem(.adaptive(minimum: 120), spacing: 12)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(ProjectTemplate.allCases) { template in
                TemplateCard(
                    template: template,
                    isSelected: selectedTemplate == template
                ) {
                    selectedTemplate = template
                }
            }
        }
    }
}

struct TemplateCard: View {
    let template: ProjectTemplate
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                Image(systemName: template.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .accentColor)
                
                Text(template.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(isSelected ? .white : .primary)
                
                Text("\(Int(template.resolution.width))×\(Int(template.resolution.height))")
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                
                Text("\(Int(template.frameRate)) fps")
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    NewProjectSheet(
        title: .constant("My Project"),
        selectedTemplate: .constant(.blank),
        recentProjectsManager: RecentProjectsManager(),
        onProjectCreated: { _ in }
    )
}