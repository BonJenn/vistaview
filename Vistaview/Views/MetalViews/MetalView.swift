import SwiftUI
import MetalKit

struct MetalView: NSViewRepresentable {
    var isPreview: Bool
    var blurAmount: Float
    var isBlurEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        if isPreview {
            let renderer = PreviewRenderer(
                mtkView: mtkView,
                blurEnabled: blurAmount > 0,
                blurAmount: blurAmount
            )
            context.coordinator.previewRenderer = renderer
            mtkView.delegate = renderer
        } else {
            let renderer = MainRenderer(
                mtkView: mtkView,
                blurEnabled: blurAmount > 0,
                blurAmount: blurAmount
            )
            context.coordinator.mainRenderer = renderer
            mtkView.delegate = renderer
        }

        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        if isPreview {
            context.coordinator.previewRenderer?.updateBlur(
                blurEnabled: isBlurEnabled,
                blurAmount: blurAmount
            )
        } else {
            context.coordinator.mainRenderer?.updateBlur(
                blurEnabled: isBlurEnabled,
                blurAmount: blurAmount
            )
        }
    }

    class Coordinator {
        var previewRenderer: PreviewRenderer?
        var mainRenderer: MainRenderer?
    }
}
