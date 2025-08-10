import Foundation
import Metal

final class TextureHeapPool {
    private let device: MTLDevice
    private(set) var heap: MTLHeap?
    private var currentKey: String = ""
    
    init(device: MTLDevice) {
        self.device = device
    }
    
    func ensureHeap(width: Int, height: Int, pixelFormat: MTLPixelFormat, usage: MTLTextureUsage) {
        let key = "\(width)x\(height)-\(pixelFormat.rawValue)-\(usage.rawValue)"
        if key == currentKey, heap != nil { return }
        
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        desc.storageMode = .private
        desc.usage = usage
        
        let alignInfo = device.heapTextureSizeAndAlign(descriptor: desc)
        // Align the size up to the required alignment
        let alignment = max(alignInfo.align, 1)
        let alignedSize = ((alignInfo.size + alignment - 1) / alignment) * alignment
        
        let heapDesc = MTLHeapDescriptor()
        heapDesc.storageMode = .private
        heapDesc.size = alignedSize
        
        heap = device.makeHeap(descriptor: heapDesc)
        currentKey = key
    }
}