# Multiview Performance Safeguards

- Single Decode Principle:
  - Tiles do not create feeds for the devices currently selected as Program or Preview to avoid concurrent capture sessions on the same camera.
  - Further consolidation to a shared capture hub can be added to route frames to Program/Preview/Tiles from a single session.

- Downscaled Rendering:
  - Tiles render NSImage snapshots already throttled to ~30fps by CameraFeed’s converter.
  - Tiles are displayed at small sizes (Adaptive grid), using .interpolation(.none) and SwiftUI scaling to avoid extra resampling cost on CPU.

- Frame Skipping:
  - CameraFeed already throttles preview image updates via imageUpdateInterval = 1/30 sec and skips frames under load.

- Non-blocking UI:
  - All capture, decoding, and image conversion are off-main in actors/tasks. UI is @MainActor only.
  - AsyncSequence drives streams; cancellation is propagated via Task.checkCancellation.

- Drawer Lifecycle:
  - Feeds start only when the drawer opens and stop when closed, minimizing background workload.

- Hotkeys / Input:
  - Handled locally in the drawer’s view; no global event taps or locks.

- Future Improvement:
  - Introduce a shared CaptureHub actor to multiplex a single AVCaptureSession per device to Program, Preview, and Multiview tiles via AsyncStreams for true “single decode.”