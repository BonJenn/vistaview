import SwiftUI

struct TemplatesSection: View {
    @Binding var selectedTemplate: ProjectTemplate
    let onCreateFromTemplate: (ProjectTemplate) -> Void
    
    private let columns = [
        GridItem(.adaptive(minimum: 200), spacing: 16)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Project Templates")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(ProjectTemplate.allCases.count) templates")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                    )
            }
            
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(ProjectTemplate.allCases) { template in
                    TemplatePreviewCard(
                        template: template,
                        onCreateFromTemplate: onCreateFromTemplate
                    )
                }
            }
        }
    }
}

struct TemplatePreviewCard: View {
    let template: ProjectTemplate
    let onCreateFromTemplate: (ProjectTemplate) -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Template preview
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            gradient: templateGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .aspectRatio(16/9, contentMode: .fit)
                
                VStack(spacing: 8) {
                    Image(systemName: template.icon)
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                    
                    Text(template.displayName)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
                
                // Overlay button when hovering
                if isHovering {
                    Button("Use Template") {
                        onCreateFromTemplate(template)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            
            // Template details
            VStack(alignment: .leading, spacing: 4) {
                Text(template.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack {
                    Label("\(Int(template.resolution.width))×\(Int(template.resolution.height))", 
                          systemImage: "rectangle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Label("\(Int(template.frameRate)) fps", 
                          systemImage: "speedometer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(isHovering ? 0.1 : 0.05), radius: isHovering ? 6 : 3)
        )
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var templateGradient: Gradient {
        switch template {
        case .blank:
            return Gradient(colors: [.gray, .secondary])
        case .news:
            return Gradient(colors: [.blue, .cyan])
        case .talkShow:
            return Gradient(colors: [.purple, .pink])
        case .podcast:
            return Gradient(colors: [.orange, .red])
        case .gaming:
            return Gradient(colors: [.green, .mint])
        case .concert:
            return Gradient(colors: [.purple, .blue])
        case .productDemo:
            return Gradient(colors: [.yellow, .orange])
        case .webinar:
            return Gradient(colors: [.indigo, .blue])
        case .interview:
            return Gradient(colors: [.teal, .cyan])
        }
    }
}

#Preview {
    ScrollView {
        TemplatesSection(
            selectedTemplate: .constant(.blank),
            onCreateFromTemplate: { _ in }
        )
        .padding()
    }
}