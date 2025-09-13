import SwiftUI
#if os(macOS)
import AppKit
#endif

extension Color {
    func toRGBA() -> RGBAColor? {
        #if os(macOS)
        let ns = NSColor(self)
        guard let converted = ns.usingColorSpace(.deviceRGB) else { return nil }
        return RGBAColor(
            r: Double(converted.redComponent),
            g: Double(converted.greenComponent),
            b: Double(converted.blueComponent),
            a: Double(converted.alphaComponent)
        )
        #else
        return nil
        #endif
    }
}