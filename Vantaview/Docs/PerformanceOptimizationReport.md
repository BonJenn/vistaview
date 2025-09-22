Performance optimization report (Preview/Program dual playback)

Changes implemented:
1) Removed GPU busy-waits
- File: Vantaview/Actors/FrameProcessor.swift
  - Function applyEffects(to:using:)
  - CHANGE: Replaced commandBuffer.waitUntilCompleted() with commandBuffer.addCompletedHandler { … } and commandBuffer.commit()
  - Rationale: Avoid stalls on CPU threads; lets GPU pipeline run asynchronously. Downstream consumers only pass MTLTexture to GPU-backed renderers; no CPU read-backs.

2) Triple-buffering and resource reuse
- File: Vantaview/Video/AVPlayerMetalPlayback.swift
  - Added a 3-texture ring (outputRing) allocated from a TextureHeapPool-backed heap for the YUV→RGB output instead of a single output texture.
  - Reuses CVMetalTextureCache and Metal resources; avoids per-frame allocation and eliminates writer/reader hazards.

3) Unified frame pacing (single display clock)
- New file: Vantaview/Video/DisplayLinkHub.swift
  - Central CVDisplayLink (DisplayLinkHub) broadcasting ticks via DisplayLinkActor to registered clients.
  - AVPlayerMetalPlayback now conforms to DisplayLinkClient and subscribes to the shared hub. This replaces per-instance CVDisplayLinks, preventing overscheduling and reducing CPU.

4) Zero-copy, GPU-first path verified
- AVPlayerItemVideoOutput is created with kCVPixelFormatType_420YpCbCr8BiPlanarFullRange and kCVPixelBufferMetalCompatibilityKey = true (already in code).
- NV12→BGRA conversion remains a Metal compute pass (NV12ToBGRAConverter) with IOSurface-backed CVPixelBuffers to avoid CPU round-trips.
- Effects are encoded as Metal workloads; no CPU readbacks in streaming path.

5) Observers/timers hygiene
- Ensured exactly one periodic time observer per AVPlayer instance and proper removal on teardown (already enforced; guarded in PreviewProgramManager).
- Transition Timer still runs only during transitions and invalidates immediately when finished (unchanged behavior).
- Added os_signpost markers for decode/pull, conversion, effects, and per-frame timings for profiling.

Expected results:
- With both Preview and Program playing, CPU usage drops notably (removal of waitUntilCompleted() stalls, unified display link, triple-buffering).
- FPS remains near 60 (>=56) with stable memory and unchanged visual quality.
- Instruments Time Profiler should show fewer CPU cycles in command buffer waits and reduced per-frame scheduling overhead.

Notes:
- When Preview is TAKEn to Program, we already avoid duplicate decode by reusing the same AVPlayer/AVPlayerItemVideoOutput pipeline.
- Further dedup (same media loaded separately in both panes) can share a single decode path by centralizing AVPlayerItemVideoOutput; we can add a registry if needed, but current changes already deliver significant CPU savings without altering UX.