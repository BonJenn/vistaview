//
//  MediaThumbnailManager.swift
//  Vistaview
//
//  Manager for generating and caching media thumbnails
//

import Foundation
import AVFoundation
import CoreGraphics
import AppKit
import SwiftUI

@MainActor
class MediaThumbnailManager: ObservableObject {
    private var thumbnailCache: [String: NSImage] = [:]
    private let thumbnailSize = CGSize(width: 120, height: 68) // 16:9 aspect ratio
    
    /// Get or generate thumbnail for a media file
    func getThumbnail(for mediaFile: MediaFile) async -> NSImage? {
        let cacheKey = mediaFile.url.absoluteString
        
        // Return cached thumbnail if available
        if let cachedThumbnail = thumbnailCache[cacheKey] {
            return cachedThumbnail
        }
        
        // Generate new thumbnail
        let thumbnail = await generateThumbnail(for: mediaFile)
        
        // Cache the result
        if let thumbnail = thumbnail {
            thumbnailCache[cacheKey] = thumbnail
        }
        
        return thumbnail
    }
    
    private func generateThumbnail(for mediaFile: MediaFile) async -> NSImage? {
        switch mediaFile.fileType {
        case .video:
            return await generateVideoThumbnail(from: mediaFile.url)
        case .image:
            return generateImageThumbnail(from: mediaFile.url)
        case .audio:
            return generateAudioThumbnail()
        }
    }
    
    private func generateVideoThumbnail(from url: URL) async -> NSImage? {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = thumbnailSize
        
        do {
            let cgImage = try await imageGenerator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            return nsImage
        } catch {
            print("Failed to generate video thumbnail: \(error)")
            return generatePlaceholderThumbnail(for: .video)
        }
    }
    
    private func generateImageThumbnail(from url: URL) -> NSImage? {
        guard let nsImage = NSImage(contentsOf: url) else {
            return generatePlaceholderThumbnail(for: .image)
        }
        
        // Resize image to thumbnail size
        let thumbnailImage = NSImage(size: thumbnailSize)
        thumbnailImage.lockFocus()
        nsImage.draw(in: NSRect(origin: .zero, size: thumbnailSize))
        thumbnailImage.unlockFocus()
        
        return thumbnailImage
    }
    
    private func generateAudioThumbnail() -> NSImage? {
        return generatePlaceholderThumbnail(for: .audio)
    }
    
    private func generatePlaceholderThumbnail(for fileType: MediaFile.MediaFileType) -> NSImage {
        let image = NSImage(size: thumbnailSize)
        image.lockFocus()
        
        // Background
        let backgroundColor = NSColor.systemGray.withAlphaComponent(0.3)
        backgroundColor.set()
        NSRect(origin: .zero, size: thumbnailSize).fill()
        
        // Icon
        let iconName = fileType.icon
        if let icon = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
            let iconSize: CGFloat = 32
            let iconRect = NSRect(
                x: (thumbnailSize.width - iconSize) / 2,
                y: (thumbnailSize.height - iconSize) / 2,
                width: iconSize,
                height: iconSize
            )
            
            icon.draw(in: iconRect)
        }
        
        image.unlockFocus()
        return image
    }
    
    /// Clear thumbnail cache to free memory
    func clearCache() {
        thumbnailCache.removeAll()
    }
    
    /// Remove specific thumbnail from cache
    func removeThumbnail(for mediaFile: MediaFile) {
        let cacheKey = mediaFile.url.absoluteString
        thumbnailCache.removeValue(forKey: cacheKey)
    }
}