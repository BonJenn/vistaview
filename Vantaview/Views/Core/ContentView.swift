import SwiftUI
import HaishinKit
import AVFoundation
import AVKit
import Metal
import MetalKit
import CoreImage
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum ProductionMode {
    case live, virtual
}

@MainActor
struct ContentView: View {
    @State private var productionManager: UnifiedProductionManager?
    @State private var productionMode: ProductionMode = .live
    @State private var showingStudioSelector = false
    @State private var showingVirtualCameraDemo = false
    @EnvironmentObject var licenseManager: LicenseManager
    @EnvironmentObject var projectCoordinator: ProjectCoordinator
    
    @StateObject private var appServices = AppServices.shared
    @Environment(\.scenePhase) private var scenePhase
    
    // Live Production States
    @State private var rtmpURL = "rtmp://live.twitch.tv/app"
    @State private var streamKey = ""
    @State private var selectedTab = 0
    @State private var showingFilePicker = false
    @State private var mediaFiles: [MediaFile] = []
    @State private var selectedPlatform = "Twitch"
    
    // PERFORMANCE: Add UI update throttling
    @State private var lastUIUpdate = Date()
    private let uiUpdateThreshold: TimeInterval = 1.0/20.0
    
    @StateObject private var layerManager = LayerStackManager()
    @State private var suppressInitialAnimations = true

    @StateObject private var scenesManager = ScenesManager()

    var body: some View {
        if let productionManager = productionManager {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    TopToolbarView(
                        productionManager: productionManager,
                        productionMode: $productionMode,
                        showingStudioSelector: $showingStudioSelector,
                        showingVirtualCameraDemo: $showingVirtualCameraDemo,
                        projectCoordinator: projectCoordinator
                    )
                    .environmentObject(appServices.recordingService)
                    
                    Divider()
                    
                    Group {
                        switch productionMode {
                        case .virtual:
                            VirtualProductionView()
                                .environmentObject(productionManager.studioManager)
                                .environmentObject(productionManager)
                                .gated(.virtualSet3D, licenseManager: licenseManager)
                        case .live:
                            FinalCutProStyleView(
                                productionManager: productionManager,
                                rtmpURL: $rtmpURL,
                                streamKey: $streamKey,
                                selectedTab: $selectedTab,
                                showingFilePicker: $showingFilePicker,
                                mediaFiles: $mediaFiles,
                                selectedPlatform: $selectedPlatform,
                                scenesManager: scenesManager
                            )
                            .environmentObject(layerManager)
                            .environmentObject(appServices.recordingService)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .sheet(isPresented: $showingStudioSelector) {
                    StudioSelectorSheet(productionManager: productionManager)
                        .environmentObject(appServices.recordingService)
                }
                .sheet(isPresented: $showingVirtualCameraDemo) {
                    VirtualCameraDemoView()
                        .frame(minWidth: 1000, minHeight: 700)
                }
                .fileImporter(
                    isPresented: $showingFilePicker,
                    allowedContentTypes: [.movie, .image, .audio],
                    allowsMultipleSelection: true
                ) { result in
                    handleFileImport(result)
                }
                .transaction { tx in
                    if suppressInitialAnimations {
                        tx.animation = nil
                    }
                }
                .task(id: projectCoordinator.currentProjectState?.manifest.projectId) {
                    if let projectState = projectCoordinator.currentProjectState {
                        await applyProjectTemplate(projectState)
                    }
                }
                .onChange(of: productionManager.previewProgramManager.programSource) { _, newValue in
                    let isActive = {
                        switch newValue {
                        case .none:
                            return false
                        default:
                            return true
                        }
                    }()
                    appServices.recordingService.updateAvailability(isProgramActive: isActive)
                }
                .onAppear {
                    let isActive = {
                        switch productionManager.previewProgramManager.programSource {
                        case .none:
                            return false
                        default:
                            return true
                        }
                    }()
                    appServices.recordingService.updateAvailability(isProgramActive: isActive)
                    appServices.recordingService.isEnabledByLicense = true
                }
                
                // Always-present overlay host that observes RecordingService
                FinalizationHUDOverlay()
                    .padding(16)
            }
            // Provide RecordingService to the whole subtree so the overlay can observe it
            .environmentObject(appServices.recordingService)
        } else {
            ProgressView("Initializing Production Manager...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task {
                    await initializeProductionManager()
                }
        }
    }
    
    private func applyProjectTemplate(_ projectState: ProjectState) async {
        guard let productionManager = productionManager else { return }
        let template = determineProjectTemplate(from: projectState)
        await TemplateConfiguration.applyTemplate(
            template,
            to: productionManager,
            with: projectState
        )
    }
    
    private func determineProjectTemplate(from projectState: ProjectState) -> ProjectTemplate {
        let title = projectState.manifest.title.lowercased()
        if title.contains("news") { return .news }
        if title.contains("talk show") { return .talkShow }
        if title.contains("podcast") { return .podcast }
        if title.contains("gaming") { return .gaming }
        if title.contains("concert") { return .concert }
        if title.contains("product demo") { return .productDemo }
        if title.contains("webinar") { return .webinar }
        if title.contains("interview") { return .interview }
        return .blank
    }

    private func initializeProductionManager() async {
        await requestPermissions()
        do {
            let manager = try await UnifiedProductionManager()
            await manager.initialize()
            
            await MainActor.run {
                self.productionManager = manager
                appServices.setProductionManager(manager)
                appServices.recordingService.setProductionManager(manager)
            }
            
            validateProductionManagerInitialization()
            await manager.connectRecordingSink(appServices.recordingService.sink())
            
            await MainActor.run {
                layerManager.setProductionManager(manager)
                manager.externalDisplayManager.setLayerStackManager(layerManager)
                manager.streamingViewModel.bindToProgramManager(manager.previewProgramManager)
                manager.streamingViewModel.bindToLayerManager(layerManager)
                manager.streamingViewModel.bindToProductionManager(manager)
            }

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                suppressInitialAnimations = false
            }
            
        } catch {
            print("Failed to initialize production manager: \(error)")
        }
    }

    private func requestPermissions() async {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        _ = await AVCaptureDevice.requestAccess(for: .audio)
    }
    
    private func validateProductionManagerInitialization() {
        guard let productionManager = productionManager else { return }
        productionManager.externalDisplayManager.setProductionManager(productionManager)
        _ = productionManager.effectManager.metalDevice.name
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                let fileType: MediaFile.MediaFileType
                let fileExtension = url.pathExtension.lowercased()
                switch fileExtension {
                case "mp4", "mov", "avi", "mkv", "webm":
                    fileType = .video
                case "mp3", "wav", "aac", "m4a":
                    fileType = .audio
                case "jpg", "jpeg", "png", "gif", "tiff":
                    fileType = .image
                default:
                    fileType = .video
                }
                let mediaFile = MediaFile(
                    name: url.lastPathComponent,
                    url: url,
                    fileType: fileType
                )
                mediaFiles.append(mediaFile)
            }
        case .failure:
            break
        }
    }
}

// MARK: - Finalization HUD

struct FinalizationHUDOverlay: View {
    @EnvironmentObject var recordingService: RecordingService
    
    var body: some View {
        Group {
            if recordingService.isFinalizing && recordingService.showFinalizationHUD {
                FinalizationHUDView(
                    progress: recordingService.finalizeProgress,
                    status: recordingService.finalizeStatusText,
                    filename: recordingService.outputURL?.lastPathComponent
                ) {
                    recordingService.showFinalizationHUD = false
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: recordingService.isFinalizing)
        .animation(.easeInOut(duration: 0.2), value: recordingService.showFinalizationHUD)
    }
}

struct FinalizationHUDView: View {
    let progress: Double
    let status: String
    let filename: String?
    let onClose: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Finalizing Recording")
                    .font(.headline)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Hide")
            }
            if let filename {
                Text(filename)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)
            HStack {
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
        )
        .frame(maxWidth: 320)
    }
}

// MARK: - Top Toolbar View

struct TopToolbarView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @Binding var productionMode: ProductionMode
    @Binding var showingStudioSelector: Bool
    @Binding var showingVirtualCameraDemo: Bool
    @EnvironmentObject var licenseManager: LicenseManager
    @EnvironmentObject var recordingService: RecordingService
    let projectCoordinator: ProjectCoordinator
    
    @State private var projectHasUnsavedChanges = false
    
    var body: some View {
        HStack {
            HStack {
                Image(systemName: "tv.circle.fill")
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    if let currentProject = projectCoordinator.currentProjectState {
                        Text(currentProject.manifest.title)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("Project Active")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Button(productionManager.currentStudioName) {
                            showingStudioSelector = true
                        }
                        .font(.headline)
                        .foregroundColor(.primary)
                    }
                }
                
                if projectHasUnsavedChanges || productionManager.hasUnsavedChanges {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.1))
            .liquidGlassMonitor(borderColor: TahoeDesign.Colors.preview, cornerRadius: TahoeDesign.CornerRadius.lg, glowIntensity: 0.4, isActive: true)
            .task(id: projectCoordinator.currentProjectState?.manifest.projectId) {
                if let currentProject = projectCoordinator.currentProjectState {
                    projectHasUnsavedChanges = await currentProject.hasUnsavedChanges
                }
            }
            
            Spacer()
            
            HStack(spacing: 0) {
                Button(action: {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        productionMode = .virtual
                        productionManager.switchToVirtualMode()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "cube.transparent.fill")
                        Text("Virtual Studio")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(productionMode == .virtual ? Color.blue : Color.clear)
                    .foregroundColor(productionMode == .virtual ? .white : .primary)
                }
                .buttonStyle(PlainButtonStyle())
                .gated(.virtualSet3D, licenseManager: licenseManager)
                
                Button(action: {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        productionMode = .live
                        productionManager.switchToLiveMode()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "video.circle.fill")
                        Text("Live Production")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(productionMode == .live ? Color.blue : Color.clear)
                    .foregroundColor(productionMode == .live ? .white : .primary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            
            Spacer()
            
            HStack(spacing: 16) {
                if productionManager.isVirtualStudioActive {
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Virtual Studio")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                
                if productionMode == .live {
                    HStack {
                        Circle()
                            .fill(productionManager.streamingViewModel.isPublishing ? Color.red : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(productionManager.streamingViewModel.isPublishing ? "LIVE" : "OFFLINE")
                            .font(.caption2)
                            .foregroundColor(productionManager.streamingViewModel.isPublishing ? .red : .secondary)
                    }
                }
                
                Menu {
                    Toggle(
                        "Studio Mode (Preview)",
                        isOn: Binding(
                            get: { productionManager.previewProgramManager.studioModeEnabled },
                            set: { productionManager.previewProgramManager.setStudioModeEnabled($0) }
                        )
                    )
                } label: {
                    Image(systemName: "rectangle.on.rectangle")
                }
                .help("Toggle Preview monitor and pipeline")
                
                Menu {
                    Button("Capture Preview Frame") {
                        productionManager.previewProgramManager.captureNextPreviewFrame()
                    }
                    Button("Capture Program Frame") {
                        productionManager.previewProgramManager.captureNextProgramFrame()
                    }
                } label: {
                    Image(systemName: "camera.aperture")
                }
                .help("Capture next GPU frame (NV12→BGRA + Effects)")

                Menu {
                    Toggle(
                        "HDR Tone Map",
                        isOn: Binding(
                            get: { productionManager.previewProgramManager.hdrToneMapEnabled },
                            set: { productionManager.previewProgramManager.hdrToneMapEnabled = $0 }
                        )
                    )
                    
                    Picker(
                        "Target FPS",
                        selection: Binding(
                            get: { productionManager.previewProgramManager.targetFPS },
                            set: { productionManager.previewProgramManager.targetFPS = $0 }
                        )
                    ) {
                        Text("30 FPS").tag(30.0)
                        Text("60 FPS").tag(60.0)
                        Text("120 FPS").tag(120.0)
                    }
                } label: {
                    Image(systemName: "speedometer")
                }
                .help("Performance settings")

                Button(action: {}) {
                    Image(systemName: "gear")
                }
                
                Button(action: { showingVirtualCameraDemo = true }) {
                    Image(systemName: "video.3d")
                }
                .help("Virtual Camera Demo")
                .gated(.virtualSet3D, licenseManager: licenseManager)
                
                Button {
                    print("[REC][UI] start tapped (if idle) / stop tapped (if recording)")
                    print("🚨 BUTTON CLICKED! This should always appear if button works")
                    recordingService.startOrStop()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: recordingService.isRecording ? "stop.circle.fill" : "record.circle")
                        Text(recordingService.isRecording ? "Stop" : "Record")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(recordingService.isRecording ? Color.red : Color.gray.opacity(0.2))
                    .foregroundColor(recordingService.isRecording ? .white : .primary)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .help(recordingService.outputURL?.lastPathComponent ?? "Start/Stop Recording")
                .onAppear {
                    print("🚨 RECORD BUTTON APPEARED - Disabled: \(!recordingService.isRecordActionAvailable)")
                    print("🚨 RecordingService values:")
                    print("   - isRecording: \(recordingService.isRecording)")
                    print("   - isRecordActionAvailable: \(recordingService.isRecordActionAvailable)")
                    print("   - isEnabledByLicense: \(recordingService.isEnabledByLicense)")
                }
            }
        }
        .padding()
        .background(TahoeDesign.Colors.surfaceLight)
        .onAppear {
            print("🎬 UI: TopToolbarView onAppear - checking program state")
            let isActive: Bool = {
                switch productionManager.previewProgramManager.programSource {
                case .none: return false
                default: return true
                }
            }()
            print("🎬 UI: Program is active: \(isActive)")
            print("🎬 UI: Program source: \(productionManager.previewProgramManager.programSource)")
            recordingService.updateAvailability(isProgramActive: isActive)
        }
    }
}

// MARK: - Final Cut Pro Style Layout

struct FinalCutProStyleView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @Binding var rtmpURL: String
    @Binding var streamKey: String
    @Binding var selectedTab: Int
    @Binding var showingFilePicker: Bool
    @Binding var mediaFiles: [MediaFile]
    @Binding var selectedPlatform: String
    @EnvironmentObject var layerManager: LayerStackManager
    @EnvironmentObject var licenseManager: LicenseManager
    @EnvironmentObject var recordingService: RecordingService

    @ObservedObject var scenesManager: ScenesManager

    @State private var showLayersSection = true
    @State private var showEffectsSection = true
    @State private var showOutputMappingSection = true
    @State private var showOutputControlsSection = true
    @State private var showScenesSection = true
    @StateObject private var multiviewModel: MultiviewViewModel

    init(
        productionManager: UnifiedProductionManager,
        rtmpURL: Binding<String>,
        streamKey: Binding<String>,
        selectedTab: Binding<Int>,
        showingFilePicker: Binding<Bool>,
        mediaFiles: Binding<[MediaFile]>,
        selectedPlatform: Binding<String>,
        scenesManager: ScenesManager
    ) {
        self._rtmpURL = rtmpURL
        self._streamKey = streamKey
        self._selectedTab = selectedTab
        self._showingFilePicker = showingFilePicker
        self._mediaFiles = mediaFiles
        self._selectedPlatform = selectedPlatform
        self.productionManager = productionManager
        self.scenesManager = scenesManager
        self._multiviewModel = StateObject(wrappedValue: MultiviewViewModel(productionManager: productionManager))
    }

    var body: some View {
        HSplitView {
            SourcesPanel(
                productionManager: productionManager,
                selectedTab: $selectedTab,
                mediaFiles: $mediaFiles,
                showingFilePicker: $showingFilePicker
            )
            .frame(minWidth: 280, maxWidth: 400)
            .liquidGlassPanel(material: .regularMaterial, cornerRadius: 0, shadowIntensity: .light)
            
            // Center Panel - Preview/Program
            PreviewProgramCenterView(
                productionManager: productionManager,
                previewProgramManager: productionManager.previewProgramManager,
                mediaFiles: $mediaFiles,
                multiviewModel: multiviewModel
            )
            .environmentObject(recordingService)
            
            // Right Panel
            ZStack {
                ScrollView {
                    VStack(spacing: 0) {
                        CollapsibleSection(title: "Scenes", isExpanded: $showScenesSection) {
                            ScenesPanel(scenesManager: scenesManager, layerManager: layerManager)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }

                        CollapsibleSection(title: "Layers", isExpanded: $showLayersSection) {
                            LayerStackPanel(layerManager: layerManager, productionManager: productionManager)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }

                        CollapsibleSection(title: "Effects", isExpanded: $showEffectsSection) {
                            EffectsListPanel(
                                effectManager: productionManager.effectManager,
                                previewProgramManager: productionManager.previewProgramManager
                            )
                            .gated(.effectsBasic, licenseManager: licenseManager)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        
                        CollapsibleSection(title: "Output Mapping", isExpanded: $showOutputMappingSection) {
                            OutputMappingControlsView(
                                outputMappingManager: productionManager.outputMappingManager,
                                externalDisplayManager: productionManager.externalDisplayManager,
                                productionManager: productionManager
                            )
                            .gated(.multiScreen, licenseManager: licenseManager)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        
                        CollapsibleSection(title: "Output Controls", isExpanded: $showOutputControlsSection) {
                            OutputControlsPanel(
                                productionManager: productionManager,
                                rtmpURL: $rtmpURL,
                                streamKey: $streamKey,
                                selectedPlatform: $selectedPlatform
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .frame(width: 360)
            .layoutPriority(1)
            .clipped()
            .background(
                RoundedRectangle(cornerRadius: TahoeDesign.CornerRadius.lg, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: TahoeDesign.CornerRadius.lg, style: .continuous)
                            .stroke(.white.opacity(0.15), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 8)
        }
    }
}

struct CollapsibleSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let content: () -> Content
    
    private let spring = Animation.spring(response: 0.35, dampingFraction: 0.86, blendDuration: 0.0)
    @State private var didAppear = false
    
    init(title: String, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self._isExpanded = isExpanded
        self.content = content
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(spring) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundColor(.secondary)
                        .animation(didAppear ? spring : nil, value: isExpanded)
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.1))
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                content()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            
            Divider()
        }
        .onAppear { didAppear = true }
    }
}

// MARK: - Preview/Program Center View

struct PreviewProgramCenterView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @ObservedObject var previewProgramManager: PreviewProgramManager
    @Binding var mediaFiles: [MediaFile]
    @EnvironmentObject var layerManager: LayerStackManager
    @ObservedObject var multiviewModel: MultiviewViewModel
    @EnvironmentObject var recordingService: RecordingService
    
    var body: some View {
        GeometryReader { geo in
            let shouldStackVertically = (geo.size.width > 0) ? (geo.size.width < 900) : false
            VStack(spacing: TahoeDesign.Spacing.md) {
                Group {
                    let studioOn = previewProgramManager.studioModeEnabled
                    if shouldStackVertically {
                        VStack(spacing: TahoeDesign.Spacing.md) {
                            if studioOn {
                                monitorView(isPreview: true)
                            }
                            monitorView(isPreview: false)
                        }
                    } else {
                        HStack(spacing: TahoeDesign.Spacing.md) {
                            if studioOn {
                                monitorView(isPreview: true)
                            }
                            monitorView(isPreview: false)
                        }
                    }
                }
                if multiviewModel.isOpen && !multiviewModel.isPoppedOut {
                    MultiviewDrawer(viewModel: multiviewModel, productionManager: productionManager)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                HStack(spacing: TahoeDesign.Spacing.xl) {
                    Button {
                        Task { await multiviewModel.toggleOpen() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "rectangle.grid.3x2")
                            Text("Multiview \(multiviewModel.isOpen ? "▾" : "▸")")
                        }
                    }
                    .buttonStyle(LiquidGlassButton(accentColor: TahoeDesign.Colors.virtual, size: .large))
                    
                    Spacer()
                    Button("TAKE") {
                        if productionManager.previewProgramManager.previewSource == .none {
                        } else {
                            if case .camera(let feed) = productionManager.previewProgramManager.previewSource {
                                Task {
                                    await productionManager.switchProgram(to: feed.device.deviceID)
                                }
                            }
                            withAnimation(TahoeAnimations.standardEasing) {
                                productionManager.previewProgramManager.take()
                            }
                            layerManager.pushPreviewToProgram(overwrite: true)
                            productionManager.previewProgramManager.objectWillChange.send()
                            productionManager.objectWillChange.send()
                        }
                    }
                    .buttonStyle(LiquidGlassButton(
                        accentColor: productionManager.previewProgramManager.previewSource == .none ? .gray : TahoeDesign.Colors.program,
                        size: .large
                    ))
                    .disabled(productionManager.previewProgramManager.previewSource == .none)
                    Button("AUTO") {
                        withAnimation(TahoeAnimations.slowEasing) {
                            productionManager.previewProgramManager.transition(duration: 1.0)
                        }
                    }
                    .buttonStyle(LiquidGlassButton(
                        accentColor: productionManager.previewProgramManager.previewSource == .none ? .gray : TahoeDesign.Colors.virtual,
                        size: .large
                    ))
                    .disabled(productionManager.previewProgramManager.previewSource == .none)
                    Spacer()
                }
                .padding(.vertical, TahoeDesign.Spacing.md)
                .liquidGlassPanel(
                    material: .ultraThinMaterial,
                    cornerRadius: TahoeDesign.CornerRadius.lg,
                    shadowIntensity: .light,
                    padding: EdgeInsets(
                        top: TahoeDesign.Spacing.sm,
                        leading: TahoeDesign.Spacing.xl,
                        bottom: TahoeDesign.Spacing.sm,
                        trailing: TahoeDesign.Spacing.xl
                    )
                )
            }
            .padding(TahoeDesign.Spacing.lg)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    @ViewBuilder
    private func monitorView(isPreview: Bool) -> some View {
        let monitorLabel = isPreview ? "PREVIEW" : "PROGRAM"
        let color = isPreview ? TahoeDesign.Colors.preview : TahoeDesign.Colors.program
        let sourceCase = isPreview ? previewProgramManager.previewSource : previewProgramManager.programSource

        let safeAspect: CGFloat = {
            let v = isPreview ? previewProgramManager.previewAspect : previewProgramManager.programAspect
            return (v.isFinite && v > 0) ? v : 16.0/9.0
        }()

        VStack(spacing: TahoeDesign.Spacing.xs) {
            HStack {
                Text(monitorLabel)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                    .statusIndicator(color: color, isActive: true)
                Spacer()
                if case .media(let mediaFile, _) = sourceCase {
                    Text(mediaFile.name)
                        .font(.caption2)
                        .foregroundColor(color)
                        .lineLimit(1)
                }
            }
            
            ZStack(alignment: .topTrailing) {
                if isPreview {
                    SimplePreviewMonitorView(productionManager: productionManager)
                        .aspectRatio(safeAspect, contentMode: .fit)
                        .liquidGlassMonitor(
                            borderColor: TahoeDesign.Colors.preview,
                            cornerRadius: TahoeDesign.CornerRadius.lg,
                            glowIntensity: 0.4,
                            isActive: true
                        )
                } else {
                    SimpleProgramMonitorView(productionManager: productionManager)
                        .aspectRatio(safeAspect, contentMode: .fit)
                        .liquidGlassMonitor(
                            borderColor: TahoeDesign.Colors.program,
                            cornerRadius: TahoeDesign.CornerRadius.lg,
                            glowIntensity: 0.4,
                            isActive: true
                        )
                }
                
                if !isPreview, recordingService.isRecording {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                        Text("REC \(formatElapsed(recordingService.elapsed))")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.85))
                    .cornerRadius(6)
                    .padding(8)
                    .help(recordingService.outputURL?.lastPathComponent ?? "Recording")
                }
            }
            
            if case .media(let mediaFile, _) = sourceCase {
                if mediaFile.fileType == .video || mediaFile.fileType == .audio {
                    ComprehensiveMediaControls(
                        previewProgramManager: productionManager.previewProgramManager,
                        isPreview: isPreview,
                        mediaFile: mediaFile
                    )
                    .liquidGlassPanel(
                        material: .ultraThinMaterial,
                        cornerRadius: TahoeDesign.CornerRadius.sm,
                        shadowIntensity: .light,
                        padding: EdgeInsets(
                            top: TahoeDesign.Spacing.xs,
                            leading: TahoeDesign.Spacing.sm,
                            bottom: TahoeDesign.Spacing.xs,
                            trailing: TahoeDesign.Spacing.sm
                        )
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
    
    private func formatElapsed(_ t: TimeInterval) -> String {
        let total = Int(t.rounded())
        let s = total % 60
        let m = (total / 60) % 60
        let h = total / 3600
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }
}

// MARK: - Sources Panel

struct SourcesPanel: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @Binding var selectedTab: Int
    @Binding var mediaFiles: [MediaFile]
    @Binding var showingFilePicker: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(["Cameras", "Media", "Virtual", "Effects"].enumerated()), id: \.offset) { index, tab in
                    Button(action: {
                        selectedTab = index
                    }) {
                        Text(tab)
                            .font(.caption)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(selectedTab == index ? Color.blue : Color.gray.opacity(0.2))
                            .foregroundColor(selectedTab == index ? .white : .primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                Spacer()
            }
            .background(Color.gray.opacity(0.1))
            
            Group {
                switch selectedTab {
                case 0:
                    CamerasSourceView(
                        productionManager: productionManager
                    )
                case 1:
                    MediaSourceView(mediaFiles: $mediaFiles, showingFilePicker: $showingFilePicker)
                        .environmentObject(productionManager)
                case 2:
                    VirtualSourceView(productionManager: productionManager)
                case 3:
                    EffectsSourceView(effectManager: productionManager.effectManager)
                default:
                    CamerasSourceView(
                        productionManager: productionManager
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Media Source View

struct MediaSourceView: View {
    @Binding var mediaFiles: [MediaFile]
    @Binding var showingFilePicker: Bool
    @EnvironmentObject var productionManager: UnifiedProductionManager
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Media Library")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { showingFilePicker = true }) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.blue)
                }
            }
            if mediaFiles.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "folder.badge.plus")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No Media Files")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Button("Add Files") {
                        showingFilePicker = true
                    }
                    .buttonStyle(LiquidGlassButton(accentColor: .accentColor, size: .medium))
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 100), spacing: 12)
                    ], spacing: 12) {
                        ForEach(mediaFiles) { file in
                            MediaItemView(
                                mediaFile: file,
                                thumbnailManager: productionManager.mediaThumbnailManager,
                                onMediaSelected: { selectedFile in
                                    let mediaSource = selectedFile.asContentSource()
                                    productionManager.previewProgramManager.loadToPreview(mediaSource)
                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 100_000_000)
                                        productionManager.previewProgramManager.objectWillChange.send()
                                        productionManager.objectWillChange.send()
                                    }
                                },
                                onMediaDropped: { _, _ in }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            Spacer()
        }
        .padding()
    }
}

// MARK: - Cameras Source View

struct CamerasSourceView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Camera Sources")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Refresh") {
                    Task {
                        await productionManager.cameraFeedManager.forceRefreshDevices()
                    }
                }
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .statusIndicator(color: TahoeDesign.Colors.virtual, isActive: true)
                .foregroundColor(.blue)
                .cornerRadius(4)
            }
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(productionManager.cameraFeedManager.availableDevices, id: \.id) { device in
                    CameraDeviceButton(device: LegacyCameraDevice(
                        id: device.id,
                        deviceID: device.deviceID,
                        displayName: device.displayName,
                        localizedName: device.displayName,
                        modelID: device.deviceID,
                        manufacturer: "Unknown",
                        isConnected: true
                    ), productionManager: productionManager)
                }
            }
            if !productionManager.cameraFeedManager.activeFeeds.isEmpty {
                Divider()
                HStack {
                    Text("Live Camera Feeds")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(productionManager.cameraFeedManager.activeFeeds.count)")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .statusIndicator(color: TahoeDesign.Colors.live, isActive: true)
                        .cornerRadius(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                let columns = [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(productionManager.cameraFeedManager.activeFeeds) { feed in
                        LiveCameraFeedButton(
                            feed: feed,
                            productionManager: productionManager
                        )
                    }
                }
            }
            Spacer()
        }
        .padding()
        .onAppear {
            Task {
                await productionManager.cameraFeedManager.getAvailableDevices()
            }
        }
    }
}

// MARK: - Virtual Camera Source View

struct VirtualSourceView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Virtual Sources")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(productionManager.availableVirtualCameras.count) cameras")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
            if productionManager.availableVirtualCameras.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "cube.transparent")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No Virtual Cameras")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Add cameras in Virtual Studio mode")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(productionManager.availableVirtualCameras, id: \.id) { camera in
                        VirtualCameraButton(camera: camera, productionManager: productionManager)
                    }
                }
            }
            Spacer()
        }
        .padding()
    }
}

struct VirtualCameraButton: View {
    let camera: VirtualCamera
    @ObservedObject var productionManager: UnifiedProductionManager
    
    var body: some View {
        Button(action: {
            productionManager.switchToVirtualCamera(camera)
        }) {
            VStack {
                Rectangle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(height: 80)
                    .overlay(
                        Image(systemName: "video.3d")
                            .font(.largeTitle)
                            .foregroundColor(.blue)
                    )
                    .liquidGlassMonitor(borderColor: TahoeDesign.Colors.preview, cornerRadius: TahoeDesign.CornerRadius.lg, glowIntensity: 0.4, isActive: true)
                Text(camera.name)
                    .font(.headline)
                Text("Focal: \(Int(camera.focalLength))mm")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Effects Source View

struct EffectsSourceView: View {
    @ObservedObject var effectManager: EffectManager
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Effects & Filters")
                .font(.caption)
                .foregroundColor(.secondary)
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(effectManager.effectsLibrary.availableEffects, id: \.id) { effect in
                        EffectDragButton(effect: effect)
                    }
                }
            }
            Spacer()
        }
        .padding()
    }
}

struct EffectDragButton: View {
    let effect: any VideoEffect
    @State private var dragOffset = CGSize.zero
    
    var body: some View {
        VStack(spacing: 4) {
            Rectangle()
                .fill(effect.category.color.opacity(0.2))
                .frame(height: 50)
                .overlay(
                    VStack(spacing: 2) {
                        Image(systemName: effect.icon)
                            .font(.title2)
                        Text(effect.name)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .foregroundColor(effect.category.color)
                    }
                    .padding(4)
                )
                .cornerRadius(6)
                .scaleEffect(dragOffset != .zero ? 0.95 : 1.0)
                .shadow(color: effect.category.color.opacity(0.3), radius: dragOffset != .zero ? 8 : 2)
        }
        .draggable(EffectDragItem(effectType: effect.name)) {
            VStack(spacing: 2) {
                Image(systemName: "video.bubble.left.fill")
                    .font(.title2)
                Text(effect.name)
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            .padding(8)
            .background(effect.category.color.opacity(0.8))
            .foregroundColor(.white)
            .liquidGlassMonitor(borderColor: TahoeDesign.Colors.preview, cornerRadius: TahoeDesign.CornerRadius.lg, glowIntensity: 0.4, isActive: true)
            .shadow(radius: 4)
        }
    }
}

// MARK: - Output Controls Panel

struct OutputControlsPanel: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @Binding var rtmpURL: String
    @Binding var streamKey: String
    @Binding var selectedPlatform: String
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                AudioLevelPanel(productionManager: productionManager)
                    .frame(height: 200)
                    .padding(.bottom, 28)
                
                GroupBox("Live Streaming") {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Platform")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("Platform", selection: $selectedPlatform) {
                                Text("YouTube").tag("YouTube")
                                Text("Twitch").tag("Twitch")
                                Text("Facebook").tag("Facebook")
                                Text("Custom").tag("Custom")
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Server")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("rtmp://server", text: $rtmpURL)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.caption2)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Stream Key")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            SecureField("Stream key", text: $streamKey)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.caption2)
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Picker(
                                selection:
                                    Binding(
                                        get: { productionManager.streamingViewModel.selectedAudioSource },
                                        set: {
                                            productionManager.streamingViewModel.selectedAudioSource = $0
                                            productionManager.streamingViewModel.applyAudioSourceChange()
                                        }
                                    ),
                                label: EmptyView()
                            ) {
                                ForEach(StreamingViewModel.AudioSource.allCases) { src in
                                    Text(src.displayName).tag(src)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .controlSize(.small)
                            .labelsHidden()
                            .padding(.vertical, 0)
                            
                            if productionManager.streamingViewModel.selectedAudioSource == .program
                                || productionManager.streamingViewModel.selectedAudioSource == .micAndProgram {
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Toggle("Include PiP Audio", isOn:
                                        Binding(
                                            get: { productionManager.streamingViewModel.includePiPAudioInProgram },
                                            set: { productionManager.streamingViewModel.includePiPAudioInProgram = $0 }
                                        )
                                    )
                                    .toggleStyle(CheckboxToggleStyle())
                                    .font(.caption2)
                                    
                                    HStack(spacing: 6) {
                                        Text("A/V Sync:")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text(String(format: "%+.1f ms", productionManager.streamingViewModel.avSyncOffsetMs))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .help("Positive = video leading audio")
                                        Spacer()
                                    }
                                }
                                .padding(.top, 2)
                            }
                        }
                        .padding(.vertical, 2)
                        
                        Button(action: {
                            Task {
                                await toggleStreaming()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: productionManager.streamingViewModel.isPublishing ? "stop.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 14))
                                Text(productionManager.streamingViewModel.isPublishing ? "Stop Streaming" : "Start Streaming")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(productionManager.streamingViewModel.isPublishing ? Color.red : Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: selectedPlatform) { _, newValue in
            switch newValue {
            case "Twitch":
                rtmpURL = "rtmp://live.twitch.tv/app"
            case "YouTube":
                rtmpURL = "rtmp://a.rtmp.youtube.com/live2"
            case "Facebook":
                rtmpURL = "rtmp://live-api-s.facebook.com:80/rtmp/"
            default:
                break
            }
        }
    }
    
    private func toggleStreaming() async {
        if productionManager.streamingViewModel.isPublishing {
            await productionManager.streamingViewModel.stop()
        } else {
            do {
                try await productionManager.streamingViewModel.start(rtmpURL: rtmpURL, streamKey: streamKey)
            } catch {
            }
        }
    }
}

struct StudioSelectorSheet: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Select Studio")
                .font(.title2)
                .fontWeight(.semibold)
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ForEach(productionManager.availableStudios, id: \.id) { studio in
                    Button(action: {
                        productionManager.loadStudio(studio)
                        dismiss()
                    }) {
                        VStack {
                            Rectangle()
                                .fill(Color.blue.opacity(0.1))
                                .frame(height: 80)
                                .overlay(
                                    Image(systemName: studio.icon)
                                        .font(.largeTitle)
                                        .foregroundColor(.blue)
                                )
                                .liquidGlassMonitor(borderColor: TahoeDesign.Colors.preview, cornerRadius: TahoeDesign.CornerRadius.lg, glowIntensity: 0.4, isActive: true)
                            Text(studio.name)
                                .font(.headline)
                            Text(studio.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(width: 600, height: 400)
    }
}

#Preview {
    ContentView()
}