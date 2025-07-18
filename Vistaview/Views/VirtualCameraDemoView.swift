import SwiftUI
import SceneKit

struct VirtualCameraDemoView: View {
    
    @StateObject private var demoProductionManager = UnifiedProductionManager()
    @StateObject private var performanceMonitor = VirtualCameraPerformanceMonitor()
    
    @State private var selectedQuality: VirtualRenderQuality = .high
    @State private var showingDiagnostics = false
    @State private var isVirtualStreaming = false
    
    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            mainContentSection
        }
        .navigationTitle("Virtual Camera Demo")
        .task {
            await setupDemo()
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack {
            Text("🎥 Virtual Camera Integration Demo")
                .font(.headline)
                .fontWeight(.semibold)
            
            Spacer()
            
            qualityPickerView
            streamingToggleButton
            diagnosticsToggleButton
        }
        .padding()
        .background(Color.gray.opacity(0.05))
    }
    
    private var qualityPickerView: some View {
        Picker("Quality", selection: $selectedQuality) {
            ForEach(VirtualRenderQuality.allCases, id: \.self) { quality in
                Text(quality.displayName).tag(quality)
            }
        }
        .pickerStyle(MenuPickerStyle())
        .frame(width: 150)
        .onChange(of: selectedQuality) { quality in
            print("🎨 Quality changed to: \(quality)")
        }
    }
    
    private var streamingToggleButton: some View {
        Button(action: toggleVirtualStreaming) {
            HStack {
                Image(systemName: isVirtualStreaming ? "stop.circle.fill" : "play.circle.fill")
                Text(isVirtualStreaming ? "Stop Virtual Stream" : "Start Virtual Stream")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isVirtualStreaming ? Color.red : Color.green)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
    }
    
    private var diagnosticsToggleButton: some View {
        Button(action: { showingDiagnostics.toggle() }) {
            Image(systemName: "chart.line.uptrend.xyaxis")
        }
    }
    
    // MARK: - Main Content Section
    
    private var mainContentSection: some View {
        HSplitView {
            leftPanelSection
            centerPreviewSection
            rightPanelSection
        }
    }
    
    // MARK: - Left Panel
    
    private var leftPanelSection: some View {
        VStack(spacing: 0) {
            studioSelectorHeader
            Divider()
            virtualCamerasListSection
            Spacer()
            quickActionsSection
        }
        .frame(minWidth: 250, maxWidth: 300)
        .background(Color.gray.opacity(0.02))
    }
    
    private var studioSelectorHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Virtual Studio")
                .font(.headline)
                .padding(.horizontal)
            
            Button(demoProductionManager.currentStudioName) {
                // Open studio selector
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color.blue.opacity(0.05))
    }
    
    private var virtualCamerasListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Virtual Cameras")
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal)
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(demoProductionManager.availableVirtualCameras, id: \.id) { camera in
                        VirtualCameraCardView(
                            camera: camera,
                            isActive: camera.isActive,
                            isStreaming: isVirtualStreaming
                        ) {
                            selectVirtualCameraForDemo(camera)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }
    
    private var quickActionsSection: some View {
        VStack(spacing: 8) {
            Button("Add Camera") {
                addVirtualCamera()
            }
            .buttonStyle(.bordered)
            
            Button("Reset Studio") {
                resetStudio()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
    
    // MARK: - Center Preview
    
    private var centerPreviewSection: some View {
        VStack(spacing: 0) {
            previewHeaderSection
            previewContentSection
            
            if isVirtualStreaming && showingDiagnostics {
                performanceOverlaySection
            }
        }
    }
    
    private var previewHeaderSection: some View {
        HStack {
            Text("Virtual Camera Output")
                .font(.headline)
            
            Spacer()
            
            activeCameraIndicator
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }
    
    private var activeCameraIndicator: some View {
        Group {
            if let activeCamera = getActiveCamera() {
                HStack {
                    Circle()
                        .fill(isVirtualStreaming ? Color.red : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(activeCamera.name)
                        .font(.caption)
                }
            }
        }
    }
    
    private var previewContentSection: some View {
        ZStack {
            Rectangle()
                .fill(Color.black)
                .aspectRatio(16/9, contentMode: .fit)
            
            if isVirtualStreaming {
                VirtualCameraPreviewView(
                    studioManager: demoProductionManager.studioManager,
                    activeCamera: getActiveCamera()
                )
            } else {
                placeholderPreviewContent
            }
        }
        .background(Color.black)
        .cornerRadius(8)
        .padding()
    }
    
    private var placeholderPreviewContent: some View {
        VStack {
            Image(systemName: "video.3d")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("Virtual Camera Preview")
                .font(.title2)
                .foregroundColor(.gray)
            
            Text("Start virtual streaming to see output")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var performanceOverlaySection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("🎥 LIVE")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
                
                Text("FPS: \(String(format: "%.0f", performanceMonitor.averageFPS))")
                    .font(.caption)
                    .foregroundColor(.white)
                
                Text("\(selectedQuality.rawValue)")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .padding(8)
            .background(Color.black.opacity(0.7))
            .cornerRadius(6)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Right Panel
    
    private var rightPanelSection: some View {
        VStack(spacing: 0) {
            diagnosticsHeaderSection
            diagnosticsContentSection
        }
        .frame(minWidth: 250, maxWidth: 300)
        .background(Color.gray.opacity(0.02))
    }
    
    private var diagnosticsHeaderSection: some View {
        HStack {
            Text("Performance")
                .font(.headline)
            Spacer()
            Button("Reset") {
                performanceMonitor.reset()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }
    
    private var diagnosticsContentSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                performanceStatsSection
                Divider()
                metalDeviceInfoSection
                Divider()
                studioStatsSection
            }
            .padding()
        }
    }
    
    private var performanceStatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Real-time Performance")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            performanceRowView("FPS:", value: String(format: "%.1f", performanceMonitor.averageFPS), color: performanceMonitor.averageFPS > 55 ? .green : .orange)
            performanceRowView("Latency:", value: String(format: "%.1f ms", performanceMonitor.renderingLatency * 1000), color: performanceMonitor.renderingLatency < 0.020 ? .green : .orange)
            performanceRowView("Memory:", value: String(format: "%.1f MB", performanceMonitor.memoryUsage), color: .primary)
            performanceRowView("Dropped Frames:", value: "\(performanceMonitor.frameDrops)", color: performanceMonitor.frameDrops == 0 ? .green : .red)
        }
    }
    
    private func performanceRowView(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(color)
        }
    }
    
    private var metalDeviceInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metal Device")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Text("Apple Silicon GPU")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("Quality: \(selectedQuality.displayName)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var studioStatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Virtual Studio")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            HStack {
                Text("Cameras:")
                Spacer()
                Text("\(demoProductionManager.availableVirtualCameras.count)")
            }
            
            HStack {
                Text("LED Walls:")
                Spacer()
                Text("\(demoProductionManager.availableLEDWalls.count)")
            }
            
            HStack {
                Text("Objects:")
                Spacer()
                Text("\(demoProductionManager.studioManager.studioObjects.count)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func getActiveCamera() -> VirtualCamera? {
        return demoProductionManager.availableVirtualCameras.first(where: { $0.isActive })
    }
    
    // MARK: - Actions
    
    private func setupDemo() async {
        if let concertStudio = demoProductionManager.availableStudios.first(where: { $0.name == "Concert" }) {
            demoProductionManager.loadStudio(concertStudio)
        }
        
        demoProductionManager.streamingViewModel.enableVirtualCamera()
        print("🎬 Virtual Camera Demo initialized")
    }
    
    private func toggleVirtualStreaming() {
        if isVirtualStreaming {
            demoProductionManager.stopVirtualCameraStreaming()
            isVirtualStreaming = false
            performanceMonitor.reset()
        } else {
            demoProductionManager.startVirtualCameraStreaming()
            isVirtualStreaming = true
            startPerformanceSimulation()
        }
    }
    
    private func selectVirtualCameraForDemo(_ camera: VirtualCamera) {
        // Use the correct method name
        demoProductionManager.switchToVirtualCamera(camera)
        
        if isVirtualStreaming {
            print("🔄 Switched to camera: \(camera.name) while streaming")
        }
    }
    
    private func addVirtualCamera() {
        demoProductionManager.studioManager.addCamera()
        print("➕ Added new virtual camera")
    }
    
    private func resetStudio() {
        demoProductionManager.clearCurrentStudio()
        print("🔄 Studio reset")
    }
    
    private func startPerformanceSimulation() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if !isVirtualStreaming {
                timer.invalidate()
                return
            }
            
            let fps = Double.random(in: 58...62)
            let latency = Double.random(in: 0.012...0.018)
            let memory = Double.random(in: 45...55)
            
            performanceMonitor.updateMetrics(fps: fps, latency: latency, memoryMB: memory)
        }
    }
}

// MARK: - Virtual Camera Card

struct VirtualCameraCardView: View {
    let camera: VirtualCamera
    let isActive: Bool
    let isStreaming: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            cardContent
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var cardContent: some View {
        HStack {
            cardIcon
            cardInfo
            Spacer()
            cardStatusIndicator
        }
        .padding(12)
        .background(isActive ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .overlay(cardBorder)
    }
    
    private var cardIcon: some View {
        Image(systemName: "video.3d")
            .font(.title2)
            .foregroundColor(isActive ? .blue : .gray)
            .frame(width: 30)
    }
    
    private var cardInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(camera.name)
                .font(.subheadline)
                .fontWeight(isActive ? .semibold : .regular)
            
            Text("Position: (\(String(format: "%.1f", camera.position.x)), \(String(format: "%.1f", camera.position.y)), \(String(format: "%.1f", camera.position.z)))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var cardStatusIndicator: some View {
        VStack {
            if isActive {
                Circle()
                    .fill(isStreaming ? Color.red : Color.blue)
                    .frame(width: 8, height: 8)
            }
            
            if isStreaming && isActive {
                Text("LIVE")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
            }
        }
    }
    
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(isActive ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
    }
}

// MARK: - Virtual Camera Preview

struct VirtualCameraPreviewView: View {
    let studioManager: VirtualStudioManager
    let activeCamera: VirtualCamera?
    
    var body: some View {
        ZStack {
            previewBackground
            previewContent
        }
        .onAppear {
            print("🎥 Virtual camera preview active - Camera: \(activeCamera?.name ?? "None")")
        }
    }
    
    private var previewBackground: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
    
    private var previewContent: some View {
        VStack {
            Text("🎬 Virtual Studio Rendering")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            if let camera = activeCamera {
                Text("Camera: \(camera.name)")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))
            }
            
            Text("Metal Pipeline Active")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            
            animatedPerformanceBars
        }
    }
    
    private var animatedPerformanceBars: some View {
        HStack {
            ForEach(0..<10, id: \.self) { index in
                Rectangle()
                    .fill(Color.green)
                    .frame(width: 3, height: CGFloat.random(in: 10...30))
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(Double(index) * 0.1), value: UUID())
            }
        }
    }
}

#Preview {
    VirtualCameraDemoView()
        .frame(width: 1200, height: 800)
}
