import Foundation
import SwiftUI
import AVFoundation

@MainActor
final class MultiviewViewModel: ObservableObject {
    struct Tile: Identifiable, Hashable, Sendable {
        let id: String
        let deviceID: String
        let name: String
    }
    
    @Published var isOpen: Bool = false
    @Published var isPoppedOut: Bool = false
    @Published var drawerHeight: CGFloat = 180.0
    @Published var tiles: [Tile] = []
    @Published private var feeds: [String: CameraFeed] = [:]
    
    private(set) weak var productionManager: UnifiedProductionManager?
    
    private var deviceChangeTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    
    init(productionManager: UnifiedProductionManager) {
        self.productionManager = productionManager
        deviceChangeTask = Task { [weak self] in
            guard let self, let dm = await self.productionManager?.deviceManager else { return }
            let stream = await dm.deviceChangeNotifications()
            for await _ in stream {
                try? Task.checkCancellation()
                await self.refreshDevices()
            }
        }
        Task { [weak self] in
            await self?.refreshDevices()
        }
    }
    
    deinit {
        deviceChangeTask?.cancel()
        refreshTask?.cancel()
        deviceChangeTask = nil
        refreshTask = nil
    }
    
    func refreshDevices() async {
        guard let pm = productionManager else { return }
        do {
            let (cams, _) = try await pm.deviceManager.discoverDevices()
            let items = cams.map { cam in
                Tile(id: cam.id, deviceID: cam.deviceID, name: cam.displayName)
            }
            tiles = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
        }
    }
    
    func setOpen(_ open: Bool) async {
        isOpen = open
        if open {
            await startThumbnailFeedsIfNeeded()
        } else {
            // KEEP FEEDS RUNNING so left panel remains live
        }
    }
    
    func toggleOpen() async {
        await setOpen(!isOpen)
    }
    
    func popOut() {
        guard let pm = productionManager else { return }
        MultiviewWindowController.shared.show(with: pm, viewModel: self)
        isPoppedOut = true
    }
    
    func closePopOut() {
        MultiviewWindowController.shared.close()
        isPoppedOut = false
    }
    
    func imageForTile(_ tile: Tile) -> NSImage? {
        if let feed = feeds[tile.deviceID] {
            return feed.previewNSImage
        }
        return nil
    }
    
    func feed(for tile: Tile) -> CameraFeed? {
        return feeds[tile.deviceID]
    }
    
    func isProgram(_ tile: Tile) -> Bool {
        guard let pm = productionManager else { return false }
        return pm.selectedProgramCameraID == tile.deviceID
    }
    
    func isPreview(_ tile: Tile) -> Bool {
        guard let pm = productionManager else { return false }
        if pm.selectedPreviewCameraID == tile.deviceID { return true }
        if case .camera(let feed) = pm.previewProgramManager.previewSource {
            return feed.device.deviceID == tile.deviceID
        }
        return false
    }
    
    func click(_ tile: Tile) async {
        guard let pm = productionManager else { return }
        if let feed = await ensureFeed(for: tile.deviceID) {
            await MainActor.run {
                pm.previewProgramManager.loadToPreview(.camera(feed))
            }
            return
        }
        do {
            _ = try await pm.deviceManager.discoverDevices(forceRefresh: true)
            if let feed = await ensureFeed(for: tile.deviceID) {
                await MainActor.run {
                    pm.previewProgramManager.loadToPreview(.camera(feed))
                }
            }
        } catch {
        }
    }
    
    func doubleClick(_ tile: Tile) async {
        await click(tile)
        await take()
    }
    
    func optionClick(_ tile: Tile) async {
        guard let pm = productionManager else { return }
        await pm.switchProgram(to: tile.deviceID)
    }
    
    func take() async {
        guard let pm = productionManager else { return }
        pm.previewProgramManager.take()
    }
    
    func dissolve() async {
        guard let pm = productionManager else { return }
        pm.previewProgramManager.transition(duration: 1.0)
    }
    
    func hotkeySelect(index: Int) async {
        guard index > 0 else { return }
        guard index <= tiles.count else { return }
        let tile = tiles[index - 1]
        await click(tile)
    }
    
    private func ensureFeed(for deviceID: String) async -> CameraFeed? {
        if let f = feeds[deviceID] { return f }
        guard let pm = productionManager else { return nil }
        if let existing = pm.cameraFeedManager.activeFeeds.first(where: { $0.deviceInfo.deviceID == deviceID }) {
            feeds[deviceID] = existing
            return existing
        }
        if let info = await pm.deviceManager.getCameraDevice(by: deviceID) {
            if let started = await pm.cameraFeedManager.startFeed(for: info) {
                feeds[deviceID] = started
                return started
            }
        }
        return nil
    }
    
    private func startThumbnailFeedsIfNeeded() async {
        guard let pm = productionManager else { return }
        for tile in tiles {
            if feeds[tile.deviceID] != nil { continue }
            if let existing = pm.cameraFeedManager.activeFeeds.first(where: { $0.deviceInfo.deviceID == tile.deviceID }) {
                feeds[tile.deviceID] = existing
                continue
            }
            if let info = await pm.deviceManager.getCameraDevice(by: tile.deviceID) {
                _ = await pm.cameraFeedManager.startFeed(for: info)
                if let f = pm.cameraFeedManager.activeFeeds.first(where: { $0.deviceInfo.deviceID == tile.deviceID }) {
                    feeds[tile.deviceID] = f
                }
            }
        }
    }
}