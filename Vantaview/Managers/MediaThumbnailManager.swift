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
        
        print("🖼️ ThumbnailManager: Getting thumbnail for: \(mediaFile.name)")
        
        // Return cached thumbnail if available
        if let cachedThumbnail = thumbnailCache[cacheKey] {
            print("✅ ThumbnailManager: Found cached thumbnail for: \(mediaFile.name)")
            return cachedThumbnail
        }
        
        print("🔄 ThumbnailManager: Generating new thumbnail for: \(mediaFile.name)")
        
        // Generate new thumbnail
        let thumbnail = await generateThumbnail(for: mediaFile)
        
        // Cache the result
        if let thumbnail = thumbnail {
            thumbnailCache[cacheKey] = thumbnail
            print("✅ ThumbnailManager: Successfully generated and cached thumbnail for: \(mediaFile.name)")
        } else {
            print("❌ ThumbnailManager: Failed to generate thumbnail for: \(mediaFile.name)")
        }
        
        return thumbnail
    }
    
    private func generateThumbnail(for mediaFile: MediaFile) async -> NSImage? {
        // FIXED: Start accessing security-scoped resource
        guard mediaFile.url.startAccessingSecurityScopedResource() else {
            print("❌ ThumbnailManager: Failed to access security-scoped resource for: \(mediaFile.name)")
            return generatePlaceholderThumbnail(for: mediaFile.fileType)
        }
        
        defer {
            mediaFile.url.stopAccessingSecurityScopedResource()
        }
        
        print("🔓 ThumbnailManager: Security access granted for: \(mediaFile.name)")
        
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
        print("🎬 ThumbnailManager: Generating video thumbnail from: \(url.lastPathComponent)")
        
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = thumbnailSize
        
        do {
            // First check if the asset is readable
            let duration = try await asset.load(.duration)
            let isPlayable = try await asset.load(.isPlayable)
            
            print("🎬 ThumbnailManager: Asset duration: \(CMTimeGetSeconds(duration))s, playable: \(isPlayable)")
            
            if !isPlayable {
                print("❌ ThumbnailManager: Asset is not playable")
                return generatePlaceholderThumbnail(for: .video)
            }
            
            // Generate thumbnail at 1 second, or 10% through the video, whichever is smaller
            let thumbnailTime = min(CMTime(seconds: 1, preferredTimescale: 600), 
                                   CMTime(seconds: CMTimeGetSeconds(duration) * 0.1, preferredTimescale: 600))
            
            let result = try await imageGenerator.image(at: thumbnailTime)
            let cgImage = result.image
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            
            print("✅ ThumbnailManager: Successfully generated video thumbnail")
            return nsImage
        } catch {
            print("❌ ThumbnailManager: Failed to generate video thumbnail: \(error)")
            return generatePlaceholderThumbnail(for: .video)
        }
    }
    
    private func generateImageThumbnail(from url: URL) -> NSImage? {
        print("🖼️ ThumbnailManager: Generating image thumbnail from: \(url.lastPathComponent)")
        
        guard let nsImage = NSImage(contentsOf: url) else {
            print("❌ ThumbnailManager: Failed to load image from URL")
            return generatePlaceholderThumbnail(for: .image)
        }
        
        print("📏 ThumbnailManager: Original image size: \(nsImage.size)")
        
        // Resize image to thumbnail size
        let thumbnailImage = NSImage(size: thumbnailSize)
        thumbnailImage.lockFocus()
        nsImage.draw(in: NSRect(origin: .zero, size: thumbnailSize))
        thumbnailImage.unlockFocus()
        
        print("✅ ThumbnailManager: Successfully generated image thumbnail")
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