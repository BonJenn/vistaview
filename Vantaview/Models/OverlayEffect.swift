import Foundation
import SwiftUI
import Metal

protocol OverlayEffect: AnyObject, Identifiable {
    var id: UUID { get }
    var name: String { get set }
    var isEnabled: Bool { get set }
    var zIndex: Int { get set }

    var centerNorm: CGPoint { get set }
    var sizeNorm: CGSize { get set }
    var rotationDegrees: Float { get set }
    var opacity: Float { get set }

    func currentTexture(device: MTLDevice) -> MTLTexture?
    func markNeedsRedraw()
    func updateForOutputSize(_ size: CGSize)
}

final class TextOverlayEffect: OverlayEffect, ObservableObject {
    let id = UUID()
    @Published var name: String = "Text"
    @Published var isEnabled: Bool = true
    @Published var zIndex: Int = 100

    @Published var centerNorm: CGPoint = CGPoint(x: 0.5, y: 0.1)
    @Published var sizeNorm: CGSize = CGSize(width: 0.5, height: 0.12)
    @Published var rotationDegrees: Float = 0
    @Published var opacity: Float = 1.0

    @Published var text: String = "Your Text"
    @Published var fontName: String = "HelveticaNeue-Bold"
    @Published var fontSize: CGFloat = 72
    @Published var textColor: Color = .white
    @Published var shadow: Bool = true

    private var cachedTexture: MTLTexture?
    private var cachedSignature: String = ""
    private var lastOutputSize: CGSize = .zero

    func updateForOutputSize(_ size: CGSize) {
        lastOutputSize = size
    }

    func markNeedsRedraw() {
        cachedSignature = ""
    }

    func currentTexture(device: MTLDevice) -> MTLTexture? {
        let sig = "\(text)|\(fontName)|\(fontSize)|\(textColor.description)|\(shadow)|\(Int(lastOutputSize.width))x\(Int(lastOutputSize.height))"
        if sig != cachedSignature {
            cachedSignature = sig
            cachedTexture = OverlayTextRenderer.makeTexture(
                device: device,
                text: text,
                fontName: fontName,
                fontSize: fontSize,
                color: textColor,
                shadow: shadow
            )
        }
        return cachedTexture
    }
}

final class CountdownOverlayEffect: OverlayEffect, ObservableObject {
    let id = UUID()
    @Published var name: String = "Countdown"
    @Published var isEnabled: Bool = true
    @Published var zIndex: Int = 200

    @Published var centerNorm: CGPoint = CGPoint(x: 0.5, y: 0.1)
    @Published var sizeNorm: CGSize = CGSize(width: 0.6, height: 0.14)
    @Published var rotationDegrees: Float = 0
    @Published var opacity: Float = 1.0

    @Published var prefix: String = ""
    @Published var suffix: String = ""
    @Published var fontName: String = "HelveticaNeue-Bold"
    @Published var fontSize: CGFloat = 80
    @Published var textColor: Color = .white
    @Published var shadow: Bool = true

    @Published var totalSeconds: Int = 10
    @Published private(set) var remaining: TimeInterval = 0
    private var timer: Timer?

    private var cachedTexture: MTLTexture?
    private var cachedSignature: String = ""
    private var lastOutputSize: CGSize = .zero

    func start() {
        timer?.invalidate()
        remaining = TimeInterval(max(0, totalSeconds))
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] t in
            guard let self else { return }
            self.remaining -= 0.1
            if self.remaining <= 0 {
                self.remaining = 0
                t.invalidate()
            }
            self.markNeedsRedraw()
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        remaining = 0
        markNeedsRedraw()
    }

    func formatted() -> String {
        let t = max(0, Int(round(remaining)))
        let m = t / 60
        let s = t % 60
        let body = String(format: "%02d:%02d", m, s)
        return "\(prefix)\(body)\(suffix)"
    }

    func updateForOutputSize(_ size: CGSize) {
        lastOutputSize = size
    }

    func markNeedsRedraw() {
        cachedSignature = ""
    }

    func currentTexture(device: MTLDevice) -> MTLTexture? {
        let text = formatted()
        let sig = "\(text)|\(fontName)|\(fontSize)|\(textColor.description)|\(shadow)|\(Int(lastOutputSize.width))x\(Int(lastOutputSize.height))"
        if sig != cachedSignature {
            cachedSignature = sig
            cachedTexture = OverlayTextRenderer.makeTexture(
                device: device,
                text: text,
                fontName: fontName,
                fontSize: fontSize,
                color: textColor,
                shadow: shadow
            )
        }
        return cachedTexture
    }
}