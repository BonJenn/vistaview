import Foundation
import CoreVideo

protocol DisplayLinkClient: AnyObject {
    func displayTick(hostTime: UInt64)
}

final class WeakClientBox {
    weak var value: (any DisplayLinkClient)?
    init(_ value: any DisplayLinkClient) { self.value = value }
}

actor DisplayLinkActor {
    static let shared = DisplayLinkActor()
    
    private var clients: [UUID: WeakClientBox] = [:]
    
    func register(_ client: any DisplayLinkClient) -> UUID {
        let id = UUID()
        clients[id] = WeakClientBox(client)
        return id
    }
    
    func unregister(_ id: UUID) {
        clients[id] = nil
    }
    
    func broadcast(hostTime: UInt64) {
        for (id, box) in clients {
            if let client = box.value {
                client.displayTick(hostTime: hostTime)
            } else {
                clients[id] = nil
            }
        }
    }
}

final class DisplayLinkHub {
    static let shared = DisplayLinkHub()
    
    private var displayLink: CVDisplayLink?
    private final class CallbackBox { }
    private var box = CallbackBox()
    
    private init() {
        var link: CVDisplayLink?
        if CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess, let link {
            self.displayLink = link
            let userPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(box).toOpaque())
            CVDisplayLinkSetOutputCallback(link, { (_, _, outputTime, _, _, user) -> CVReturn in
                guard user != nil else { return kCVReturnSuccess }
                let hostTime = outputTime.pointee.hostTime
                Task.detached(priority: .userInitiated) {
                    await DisplayLinkActor.shared.broadcast(hostTime: hostTime)
                }
                return kCVReturnSuccess
            }, userPtr)
        }
    }
    
    deinit {
        if let link = displayLink {
            CVDisplayLinkSetOutputCallback(link, { _,_,_,_,_,_ in kCVReturnSuccess }, nil)
            if CVDisplayLinkIsRunning(link) {
                CVDisplayLinkStop(link)
            }
        }
        displayLink = nil
    }
    
    func ensureRunning() {
        if let link = displayLink, !CVDisplayLinkIsRunning(link) {
            CVDisplayLinkStart(link)
        }
    }
    
    func stop() {
        if let link = displayLink, CVDisplayLinkIsRunning(link) {
            CVDisplayLinkStop(link)
        }
    }
}