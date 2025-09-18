import SwiftUI

// MARK: - Project Section

struct ProjectSection: View {
    let title: String
    let projects: [RecentProject]
    let viewMode: ProjectHub.ViewMode
    let onOpenProject: (RecentProject) -> Void
    let onDuplicateProject: (RecentProject) -> Void
    let onDeleteProject: (RecentProject) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(projects.count) projects")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                    )
            }
            
            switch viewMode {
            case .grid:
                ProjectGrid(
                    projects: projects,
                    onOpenProject: onOpenProject,
                    onDuplicateProject: onDuplicateProject,
                    onDeleteProject: onDeleteProject
                )
            case .list:
                ProjectList(
                    projects: projects,
                    onOpenProject: onOpenProject,
                    onDuplicateProject: onDuplicateProject,
                    onDeleteProject: onDeleteProject
                )
            }
        }
    }
}

// MARK: - Project Grid

struct ProjectGrid: View {
    let projects: [RecentProject]
    let onOpenProject: (RecentProject) -> Void
    let onDuplicateProject: (RecentProject) -> Void
    let onDeleteProject: (RecentProject) -> Void
    
    private let columns = [
        GridItem(.adaptive(minimum: 280), spacing: 16)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(projects) { project in
                ProjectCard(
                    project: project,
                    onOpenProject: onOpenProject,
                    onDuplicateProject: onDuplicateProject,
                    onDeleteProject: onDeleteProject
                )
            }
        }
    }
}

// MARK: - Project Card

struct ProjectCard: View {
    let project: RecentProject
    let onOpenProject: (RecentProject) -> Void
    let onDuplicateProject: (RecentProject) -> Void
    let onDeleteProject: (RecentProject) -> Void
    
    @State private var isHovering = false
    @State private var showingContextMenu = false
    
    var body: some View {
        Button(action: { onOpenProject(project) }) {
            VStack(spacing: 12) {
                // Thumbnail
                AsyncImage(url: thumbnailURL) { image in
                    image
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .aspectRatio(16/9, contentMode: .fit)
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "tv")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                
                                Text("No Preview")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        )
                }
                .clipped()
                .cornerRadius(8)
                .overlay(
                    // Overlay controls when hovering
                    Group {
                        if isHovering {
                            HStack {
                                Spacer()
                                
                                VStack {
                                    Menu {
                                        Button("Open") { onOpenProject(project) }
                                        Button("Duplicate") { onDuplicateProject(project) }
                                        Divider()
                                        Button("Delete", role: .destructive) { onDeleteProject(project) }
                                    } label: {
                                        Image(systemName: "ellipsis.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.white)
                                            .background(Color.black.opacity(0.5))
                                            .clipShape(Circle())
                                    }
                                    .menuStyle(BorderlessButtonMenuStyle())
                                    
                                    Spacer()
                                }
                                .padding(8)
                            }
                        }
                    }
                )
                
                // Project info
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.title)
                        .font(.headline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    HStack {
                        Text("Modified \(project.lastOpenedAt, style: .relative)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if let resolution = project.resolution {
                            Text("\(Int(resolution.width))×\(Int(resolution.height))")
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
                    
                    if let frameRate = project.frameRate {
                        HStack {
                            Text("\(Int(frameRate)) fps")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if let duration = project.duration {
                                Text(formatDuration(duration))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(12)
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(isHovering ? 0.15 : 0.05), radius: isHovering ? 8 : 4)
        )
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var thumbnailURL: URL? {
        guard let thumbnailPath = project.thumbnailPath else { return nil }
        return URL(fileURLWithPath: thumbnailPath)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Project List

struct ProjectList: View {
    let projects: [RecentProject]
    let onOpenProject: (RecentProject) -> Void
    let onDuplicateProject: (RecentProject) -> Void
    let onDeleteProject: (RecentProject) -> Void
    
    var body: some View {
        VStack(spacing: 1) {
            ForEach(projects) { project in
                ProjectRow(
                    project: project,
                    onOpenProject: onOpenProject,
                    onDuplicateProject: onDuplicateProject,
                    onDeleteProject: onDeleteProject
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

// MARK: - Project Row

struct ProjectRow: View {
    let project: RecentProject
    let onOpenProject: (RecentProject) -> Void
    let onDuplicateProject: (RecentProject) -> Void
    let onDeleteProject: (RecentProject) -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: { onOpenProject(project) }) {
            HStack(spacing: 16) {
                // Mini thumbnail
                AsyncImage(url: thumbnailURL) { image in
                    image
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                        .frame(width: 80, height: 45)
                        .clipped()
                        .cornerRadius(6)
                } placeholder: {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 80, height: 45)
                        .overlay(
                            Image(systemName: "tv")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                        )
                        .cornerRadius(6)
                }
                
                // Project details
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.title)
                        .font(.headline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    HStack {
                        Text("Modified \(project.lastOpenedAt, style: .relative)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let resolution = project.resolution {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text("\(Int(resolution.width))×\(Int(resolution.height))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if let frameRate = project.frameRate {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text("\(Int(frameRate)) fps")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                }
                
                Spacer()
                
                // Actions
                if isHovering {
                    HStack(spacing: 8) {
                        Button("Duplicate") { onDuplicateProject(project) }
                            .buttonStyle(BorderlessButtonStyle())
                            .font(.caption)
                        
                        Menu {
                            Button("Open") { onOpenProject(project) }
                            Button("Duplicate") { onDuplicateProject(project) }
                            Divider()
                            Button("Delete", role: .destructive) { onDeleteProject(project) }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundColor(.secondary)
                        }
                        .menuStyle(BorderlessButtonMenuStyle())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            Color(NSColor.controlBackgroundColor)
                .opacity(isHovering ? 1.0 : 0.0)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
    
    private var thumbnailURL: URL? {
        guard let thumbnailPath = project.thumbnailPath else { return nil }
        return URL(fileURLWithPath: thumbnailPath)
    }
}

#Preview {
    VStack {
        ProjectSection(
            title: "Recent Projects",
            projects: [],
            viewMode: .grid,
            onOpenProject: { _ in },
            onDuplicateProject: { _ in },
            onDeleteProject: { _ in }
        )
    }
    .padding()
}