import SwiftUI

struct CloudProjectsSection: View {
    @State private var isLoadingCloudProjects = false
    @State private var cloudProjects: [CloudProject] = []
    @State private var cloudError: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Cloud Projects")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Image(systemName: "icloud")
                    .foregroundColor(.accentColor)
                
                Spacer()
                
                if isLoadingCloudProjects {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button("Refresh") {
                        loadCloudProjects()
                    }
                    .font(.caption)
                }
            }
            
            if let error = cloudError {
                VStack(spacing: 12) {
                    Image(systemName: "icloud.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    
                    Text("Cloud Sync Unavailable")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Retry") {
                        loadCloudProjects()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.1))
                )
            } else if cloudProjects.isEmpty && !isLoadingCloudProjects {
                VStack(spacing: 12) {
                    Image(systemName: "icloud")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    
                    Text("No Cloud Projects")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Your cloud projects will appear here when you're online")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 280), spacing: 16)
                ], spacing: 16) {
                    ForEach(cloudProjects) { project in
                        CloudProjectCard(project: project)
                    }
                }
            }
        }
        .onAppear {
            loadCloudProjects()
        }
    }
    
    private func loadCloudProjects() {
        isLoadingCloudProjects = true
        cloudError = nil
        
        // Simulate cloud loading with delay
        Task {
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                
                await MainActor.run {
                    // For now, show placeholder projects
                    cloudProjects = []
                    isLoadingCloudProjects = false
                    cloudError = "Cloud sync is not yet implemented"
                }
            } catch {
                await MainActor.run {
                    cloudError = error.localizedDescription
                    isLoadingCloudProjects = false
                }
            }
        }
    }
}

struct CloudProject: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let lastModified: Date
    let thumbnailURL: URL?
    let fileSize: Int64
    let isShared: Bool
    let collaborators: [String]
    
    init(title: String, lastModified: Date = Date(), thumbnailURL: URL? = nil, 
         fileSize: Int64 = 0, isShared: Bool = false, collaborators: [String] = []) {
        self.title = title
        self.lastModified = lastModified
        self.thumbnailURL = thumbnailURL
        self.fileSize = fileSize
        self.isShared = isShared
        self.collaborators = collaborators
    }
}

struct CloudProjectCard: View {
    let project: CloudProject
    @State private var isHovering = false
    @State private var isDownloading = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Cloud project preview
            ZStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "icloud.and.arrow.down")
                                .font(.largeTitle)
                                .foregroundColor(.accentColor)
                            
                            if isDownloading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Text("Cloud Project")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    )
                
                // Status indicators
                VStack {
                    HStack {
                        if project.isShared {
                            Image(systemName: "person.2.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                        }
                        
                        Spacer()
                        
                        Image(systemName: "icloud.fill")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.accentColor)
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                }
                .padding(8)
            }
            .cornerRadius(8)
            
            // Project info
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.headline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack {
                    Text("Modified \(project.lastModified, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if project.fileSize > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: project.fileSize, countStyle: .binary))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.secondary.opacity(0.2))
                            )
                    }
                }
                
                if !project.collaborators.isEmpty {
                    HStack {
                        Image(systemName: "person.2")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text("\(project.collaborators.count) collaborators")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(isHovering ? 0.15 : 0.05), radius: isHovering ? 8 : 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: isHovering ? 1 : 0)
        )
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            downloadProject()
        }
    }
    
    private func downloadProject() {
        isDownloading = true
        
        // Simulate download
        Task {
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            await MainActor.run {
                isDownloading = false
            }
        }
    }
}

#Preview {
    ScrollView {
        CloudProjectsSection()
            .padding()
    }
}