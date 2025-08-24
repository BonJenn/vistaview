//
//  OverlayTextRenderer.swift
//  Vantaview
//

import Foundation
import Metal
import CoreText
import CoreGraphics
import AppKit
import SwiftUI

final class OverlayTextRenderer {
    static func makeTexture(
        device: MTLDevice,
        text: String,
        fontName: String,
        fontSize: CGFloat,
        color: Color,
        shadow: Bool
    ) -> MTLTexture? {
        
        // Convert SwiftUI Color to NSColor
        let nsColor = NSColor(color)
        
        // Create font
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        
        // Calculate text size
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: nsColor
        ]
        
        // Add shadow if needed
        if shadow {
            let shadowObject = NSShadow()
            shadowObject.shadowOffset = NSSize(width: 2, height: -2)
            shadowObject.shadowBlurRadius = 4
            shadowObject.shadowColor = NSColor.black.withAlphaComponent(0.5)
            attributes[.shadow] = shadowObject
        }
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        
        guard textSize.width > 0 && textSize.height > 0 else { return nil }
        
        // Add padding for shadow
        let padding: CGFloat = shadow ? 8 : 2
        let width = Int(ceil(textSize.width + padding * 2))
        let height = Int(ceil(textSize.height + padding * 2))
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        // Clear the context
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        
        // Flip coordinate system for correct text orientation
        context.textMatrix = .identity
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        
        // Draw text with padding offset
        let line = CTLineCreateWithAttributedString(attributedString)
        context.textPosition = CGPoint(x: padding, y: padding)
        CTLineDraw(line, context)
        
        // Create Metal texture from bitmap data
        guard let data = context.data else { return nil }
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead]
        
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else { return nil }
        
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: width * 4
        )
        
        return texture
    }
}