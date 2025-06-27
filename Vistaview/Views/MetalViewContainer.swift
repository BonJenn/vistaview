import SwiftUI

struct MetalViewContainer: View {
    var width: CGFloat
    var height: CGFloat
    var blurEnabled: Bool
    var blurAmount: Float

    var body: some View {
        MetalView(
            blurEnabled: blurEnabled,
            blurAmount: blurAmount
        )
        .frame(width: width, height: height)
    }
}
