import Foundation
import AVFoundation

public actor CameraCaptureSession {
    private var session: AVCaptureSession?
    private var deviceInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var delegateProxy: DelegateProxy?
    
    private var continuation: AsyncStream<CMSampleBuffer>.Continuation?
    private var streamStorage: AsyncStream<CMSampleBuffer>?
    
    public init() { }
    
    public func start(cameraID: String) async throws {
        try Task.checkCancellation()
        try await stop()
        
        let s = AVCaptureSession()
        s.beginConfiguration()
        
        let device = AVCaptureDevice.devices(for: .video).first(where: { $0.uniqueID == cameraID })
        guard let captureDevice = device else {
            throw NSError(domain: "CameraCaptureSession", code: -1, userInfo: [NSLocalizedDescriptionKey: "Camera not found"])
        }
        
        let input = try AVCaptureDeviceInput(device: captureDevice)
        if s.canAddInput(input) { s.addInput(input) } else {
            throw NSError(domain: "CameraCaptureSession", code: -2, userInfo: [NSLocalizedDescriptionKey: "Cannot add input"])
        }
        
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        
        let proxy = DelegateProxy()
        output.setSampleBufferDelegate(proxy, queue: delegateQueue)
        if s.canAddOutput(output) { s.addOutput(output) } else {
            throw NSError(domain: "CameraCaptureSession", code: -3, userInfo: [NSLocalizedDescriptionKey: "Cannot add output"])
        }
        
        if let connection = output.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }
        
        s.commitConfiguration()
        
        let (stream, cont) = AsyncStream<CMSampleBuffer>.makeStream()
        self.streamStorage = stream
        self.continuation = cont
        self.delegateProxy = proxy
        self.session = s
        self.deviceInput = input
        self.videoOutput = output
        
        // Make closures hop back into the actor before touching actor-isolated state
        proxy.yield = { [weak self] sb in
            guard let self else { return }
            Task { await self.emit(sb) }
        }
        proxy.onError = { [weak self] error in
            guard let self else { return }
            Task { await self.finishStream() }
        }
        
        s.startRunning()
    }
    
    public func stop() async {
        session?.stopRunning()
        session = nil
        deviceInput = nil
        videoOutput = nil
        delegateProxy = nil
        continuation?.finish()
        continuation = nil
        streamStorage = nil
    }
    
    public func sampleBuffers() -> AsyncStream<CMSampleBuffer> {
        if let streamStorage { return streamStorage }
        let (stream, cont) = AsyncStream<CMSampleBuffer>.makeStream()
        self.streamStorage = stream
        self.continuation = cont
        return stream
    }
    
    // MARK: - Actor-isolated helpers
    
    private func emit(_ sb: CMSampleBuffer) {
        continuation?.yield(sb)
    }
    
    private func finishStream() {
        continuation?.finish()
    }
    
    // MARK: - Delegate queue
    
    nonisolated private var delegateQueue: DispatchQueue {
        DispatchQueue(label: "app.vantaview.camera.delegate", qos: .userInitiated)
    }
}

private final class DelegateProxy: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var yield: @Sendable (CMSampleBuffer) -> Void = { _ in }
    var onError: @Sendable (Error) -> Void = { _ in }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        yield(sampleBuffer)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    }
}