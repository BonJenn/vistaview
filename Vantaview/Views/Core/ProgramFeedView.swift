import SwiftUI
import MetalKit
import Metal

@MainActor
struct ProgramFeedView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    
    private let renderer: ProgramRenderer
    private let device: MTLDevice
    
    init(productionManager: UnifiedProductionManager) {
        self.productionManager = productionManager
        self.device = productionManager.effectManager.metalDevice
        self.renderer = ProgramRenderer(device: device)
    }
    
    var body: some View {
        MetalVideoView(textureSupplier: { renderer.currentTexture }, preferredFPS: 60, device: device)
            .contentShape(Rectangle())
            .onTapGesture {
                Task { @MainActor in
                    productionManager.routeProgramToPreview()
                }
            }
            .task {
                await MainActor.run {
                    productionManager.bindProgramOutput(to: renderer)
                    productionManager.ensureProgramRunning()
                }
            }
            .onChange(of: productionManager.selectedProgramCameraID) { _, _ in
                Task { @MainActor in
                    productionManager.rebindProgram(to: productionManager.selectedProgramCameraID, renderer: renderer)
                }
            }
    }
}