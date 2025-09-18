import Foundation
import AVFoundation
import AppKit
import os

actor MediaManager {
    private let logger = Logger(subsystem: "app.vantaview.project", category: "MediaManager")
    private let fileManager = FileManager.default
    
    // Background processing
    private var copyOperations: [UUID: Task<Void, Error>] = [:]
    private var thumbnailGenerationTasks: [UUID: Task<Void, Never>] = [:]
    
    // MARK: - Media Import
    
    func importMedia(
        from sourceURLs: [URL],
        to projectState: ProjectState,
        mediaPolicy: ProjectManifest.MediaPolicy,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> [ProjectMediaReference] {
        guard let projectURL = await projectState.projectURL else {
            throw MediaError.noProjectURL
        }
        
        logger.info("Importing \(sourceURLs.count) media files with policy: \(mediaPolicy.rawValue)")
        
        let mediaDirectory = projectURL.appendingPathComponent("media")
        var importedReferences: [ProjectMediaReference] = []
        
        let totalFiles = sourceURLs.count
        var processedFiles = 0
        
        for sourceURL in sourceURLs {
            do {
                try Task.checkCancellation()
                
                let reference = try await importSingleMediaFile(
                    from: sourceURL,
                    to: mediaDirectory,
                    mediaPolicy: mediaPolicy
                )
                
                importedReferences.append(reference)
                
                // Generate thumbnail in background
                thumbnailGenerationTasks[reference.id] = Task.detached(priority: .utility) {
                    await self.generateThumbnail(for: reference, projectURL: projectURL)
                }
                
                processedFiles += 1
                await MainActor.run {
                    progressHandler(Double(processedFiles) / Double(totalFiles))
                }
                
            } catch {
                logger.error("Failed to import \(sourceURL.lastPathComponent): \(error.localizedDescription)")
                // Continue with other files
            }
        }
        
        // Add references to project
        for reference in importedReferences {
            await projectState.addMediaReference(reference)
        }
        
        logger.info("Imported \(importedReferences.count) media files successfully")
        return importedReferences
    }
    
    private func importSingleMediaFile(
        from sourceURL: URL,
        to mediaDirectory: URL,
        mediaPolicy: ProjectManifest.MediaPolicy
    ) async throws -> ProjectMediaReference {
        let fileName = sourceURL.lastPathComponent
        let mediaType = determineMediaType(from: sourceURL)
        
        var reference = ProjectMediaReference(
            originalPath: sourceURL.path,
            fileName: fileName,
            mediaType: mediaType,
            isLinked: mediaPolicy == .link
        )
        
        switch mediaPolicy {
        case .copy:
            // Copy file to project media directory
            let destinationURL = mediaDirectory.appendingPathComponent(fileName)
            
            // Handle filename conflicts
            let finalDestinationURL = try await resolveFileNameConflict(destinationURL)
            let finalFileName = finalDestinationURL.lastPathComponent
            
            try await copyFile(from: sourceURL, to: finalDestinationURL)
            
            reference.fileName = finalFileName
            reference.relativePath = "media/\(finalFileName)"
            
        case .link:
            // Create file bookmark for external reference
            let bookmarkData = try sourceURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            
            reference.fileBookmark = bookmarkData
            reference.absolutePath = sourceURL.path
        }
        
        // Extract metadata
        try await extractMediaMetadata(for: &reference, from: sourceURL)
        
        return reference
    }
    
    // MARK: - Media Resolution
    
    func resolveMediaReference(_ reference: ProjectMediaReference, projectURL: URL) async -> URL? {
        if reference.isLinked {
            // Try to resolve bookmark first
            if let bookmarkData = reference.fileBookmark {
                do {
                    var isStale = false
                    let resolvedURL = try URL(
                        resolvingBookmarkData: bookmarkData,
                        options: .withSecurityScope,
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )
                    
                    if !isStale && fileManager.fileExists(atPath: resolvedURL.path) {
                        return resolvedURL
                    }
                } catch {
                    logger.warning("Failed to resolve bookmark for \(reference.fileName): \(error.localizedDescription)")
                }
            }
            
            // Fall back to absolute path
            if let absolutePath = reference.absolutePath,
               fileManager.fileExists(atPath: absolutePath) {
                return URL(fileURLWithPath: absolutePath)
            }
            
        } else {
            // For copied files, use relative path
            if let relativePath = reference.relativePath {
                let url = projectURL.appendingPathComponent(relativePath)
                if fileManager.fileExists(atPath: url.path) {
                    return url
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Media Relink
    
    func relinkMedia(_ reference: ProjectMediaReference, to newURL: URL) async throws -> ProjectMediaReference {
        logger.info("Relinking media: \(reference.fileName)")
        
        var updatedReference = reference
        
        // Create new bookmark
        let bookmarkData = try newURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        
        updatedReference.fileBookmark = bookmarkData
        updatedReference.absolutePath = newURL.path
        updatedReference.lastModified = Date()
        
        // Update metadata
        try await extractMediaMetadata(for: &updatedReference, from: newURL)
        
        return updatedReference
    }
    
    // MARK: - Collect All Media
    
    func collectAllMedia(for projectState: ProjectState) async throws {
        guard let projectURL = await projectState.projectURL else {
            throw MediaError.noProjectURL
        }
        
        logger.info("Collecting all media into project")
        
        let mediaDirectory = projectURL.appendingPathComponent("media")
        let mediaReferences = await projectState.mediaReferences
        
        for reference in mediaReferences where reference.isLinked {
            guard let sourceURL = await resolveMediaReference(reference, projectURL: projectURL) else {
                logger.warning("Cannot resolve linked media: \(reference.fileName)")
                continue
            }
            
            do {
                let destinationURL = mediaDirectory.appendingPathComponent(reference.fileName)
                let finalDestinationURL = try await resolveFileNameConflict(destinationURL)
                
                try await copyFile(from: sourceURL, to: finalDestinationURL)
                
                // Update reference to be copied instead of linked
                await projectState.updateMediaReference(reference.id) { ref in
                    ref.isLinked = false
                    ref.relativePath = "media/\(finalDestinationURL.lastPathComponent)"
                    ref.absolutePath = nil
                    ref.fileBookmark = nil
                    ref.fileName = finalDestinationURL.lastPathComponent
                }
                
            } catch {
                logger.error("Failed to collect media \(reference.fileName): \(error.localizedDescription)")
            }
        }
        
        // Update manifest media policy
        await MainActor.run {
            projectState.manifest.mediaPolicy = .copy
            projectState.markUnsaved()
        }
    }
    
    // MARK: - Thumbnail Generation
    
    private func generateThumbnail(for reference: ProjectMediaReference, projectURL: URL) async {
        guard let mediaURL = await resolveMediaReference(reference, projectURL: projectURL) else {
            return
        }
        
        let thumbnailsDirectory = projectURL.appendingPathComponent("thumbnails")
        let thumbnailURL = thumbnailsDirectory.appendingPathComponent("\(reference.id.uuidString).png")
        
        do {
            let thumbnail: NSImage?
            
            switch reference.mediaType {
            case .video:
                thumbnail = try await generateVideoThumbnail(from: mediaURL)
            case .image:
                thumbnail = try await generateImageThumbnail(from: mediaURL)
            case .audio:
                thumbnail = try await generateAudioThumbnail(from: mediaURL)
            }
            
            if let thumbnail = thumbnail {
                let pngData = thumbnail.pngData
                try pngData?.write(to: thumbnailURL)
                
                // Update reference with thumbnail path
                // Note: In practice, you'd update this through the project state
                logger.debug("Generated thumbnail for \(reference.fileName)")
            }
            
        } catch {
            logger.error("Failed to generate thumbnail for \(reference.fileName): \(error.localizedDescription)")
        }
    }
    
    private func generateVideoThumbnail(from url: URL) async throws -> NSImage? {
        return try await withCheckedThrowingContinuation { continuation in
            let asset = AVAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            
            let time = CMTime(seconds: 1.0, preferredTimescale: 600)
            
            imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let image = image {
                    let nsImage = NSImage(cgImage: image, size: NSSize(width: 320, height: 180))
                    continuation.resume(returning: nsImage)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func generateImageThumbnail(from url: URL) async throws -> NSImage? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        
        let thumbnailSize = NSSize(width: 320, height: 180)
        let thumbnail = NSImage(size: thumbnailSize)
        
        thumbnail.lockFocus()
        defer { thumbnail.unlockFocus() }
        
        let aspectRatio = image.size.width / image.size.height
        let thumbnailAspectRatio = thumbnailSize.width / thumbnailSize.height
        
        var drawRect: NSRect
        if aspectRatio > thumbnailAspectRatio {
            let scaledHeight = thumbnailSize.width / aspectRatio
            let yOffset = (thumbnailSize.height - scaledHeight) / 2
            drawRect = NSRect(x: 0, y: yOffset, width: thumbnailSize.width, height: scaledHeight)
        } else {
            let scaledWidth = thumbnailSize.height * aspectRatio
            let xOffset = (thumbnailSize.width - scaledWidth) / 2
            drawRect = NSRect(x: xOffset, y: 0, width: scaledWidth, height: thumbnailSize.height)
        }
        
        image.draw(in: drawRect)
        
        return thumbnail
    }
    
    private func generateAudioThumbnail(from url: URL) async throws -> NSImage? {
        // Generate a waveform thumbnail
        let thumbnail = NSImage(size: NSSize(width: 320, height: 180))
        
        thumbnail.lockFocus()
        defer { thumbnail.unlockFocus() }
        
        // Draw a placeholder waveform
        NSColor.systemBlue.setFill()
        let rect = NSRect(origin: .zero, size: thumbnail.size)
        rect.fill()
        
        // Draw waveform pattern
        NSColor.white.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 2.0
        
        let centerY = rect.height / 2
        path.move(to: NSPoint(x: 0, y: centerY))
        
        for x in stride(from: 0, to: rect.width, by: 4) {
            let amplitude = sin(x * 0.1) * 20 + Double.random(in: -10...10)
            path.line(to: NSPoint(x: x, y: centerY + amplitude))
        }
        
        path.stroke()
        
        return thumbnail
    }
    
    // MARK: - File Operations
    
    private func copyFile(from sourceURL: URL, to destinationURL: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    try self.fileManager.copyItem(at: sourceURL, to: destinationURL)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func resolveFileNameConflict(_ url: URL) async throws -> URL {
        var counter = 1
        var resolvedURL = url
        
        while fileManager.fileExists(atPath: resolvedURL.path) {
            let nameWithoutExtension = url.deletingPathExtension().lastPathComponent
            let pathExtension = url.pathExtension
            let directory = url.deletingLastPathComponent()
            
            let newName = "\(nameWithoutExtension)_\(counter).\(pathExtension)"
            resolvedURL = directory.appendingPathComponent(newName)
            counter += 1
        }
        
        return resolvedURL
    }
    
    // MARK: - Metadata Extraction
    
    private func extractMediaMetadata(for reference: inout ProjectMediaReference, from url: URL) async throws {
        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        
        reference.fileSize = Int64(resourceValues.fileSize ?? 0)
        reference.lastModified = resourceValues.contentModificationDate ?? Date()
        
        if reference.mediaType == .video || reference.mediaType == .audio {
            let asset = AVAsset(url: url)
            let duration = try await asset.load(.duration)
            reference.duration = CMTimeGetSeconds(duration)
        }
    }
    
    // MARK: - Utilities
    
    private func determineMediaType(from url: URL) -> ProjectMediaReference.MediaType {
        let pathExtension = url.pathExtension.lowercased()
        
        switch pathExtension {
        case "mp4", "mov", "avi", "mkv", "webm", "m4v":
            return .video
        case "mp3", "wav", "aac", "m4a", "flac":
            return .audio
        case "jpg", "jpeg", "png", "gif", "tiff", "bmp", "heic":
            return .image
        default:
            return .video // Default fallback
        }
    }
}

// MARK: - Supporting Types

enum MediaError: LocalizedError {
    case noProjectURL
    case unsupportedFormat(String)
    case copyFailed(String)
    case metadataExtractionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noProjectURL:
            return "No project URL specified"
        case .unsupportedFormat(let format):
            return "Unsupported media format: \(format)"
        case .copyFailed(let message):
            return "Failed to copy media: \(message)"
        case .metadataExtractionFailed(let message):
            return "Failed to extract metadata: \(message)"
        }
    }
}

// Extension for NSImage PNG conversion
extension NSImage {
    var pngData: Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .png, properties: [:])
    }
}