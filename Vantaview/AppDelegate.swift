//
//  AppDelegate.swift
//  Vantaview
//
//  Created by Vantaview on 12/19/24.
//

import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    var urlHandler: ((URL) -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 AppDelegate finished launching")
        AppDelegate.shared = self

        // Register for URL events
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        print("✅ URL event handler registered in AppDelegate")
    }

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        print("📨 handleGetURLEvent called in AppDelegate!")
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else {
            print("❌ Failed to extract URL from event")
            return
        }
        print("🔗 Got URL from event: \(urlString)")

        if let url = URL(string: urlString) {
            print("✅ URL parsed successfully, calling handler")
            urlHandler?(url)
        } else {
            print("❌ Failed to create URL from string")
        }
    }
}
