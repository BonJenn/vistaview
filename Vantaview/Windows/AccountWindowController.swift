//
//  AccountWindowController.swift
//  Vantaview
//
//  Created by Vantaview on 12/19/24.
//

import Cocoa
import SwiftUI

class AccountWindowController: NSWindowController {
    private static var shared: AccountWindowController?

    static func show(licenseManager: LicenseManager, authManager: AuthenticationManager) {
        // If window already exists, bring it to front
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        // Create new window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Account"
        window.center()
        window.isReleasedWhenClosed = false

        // Create window controller
        let controller = AccountWindowController(window: window)
        controller.contentViewController = NSHostingController(
            rootView: AccountView(licenseManager: licenseManager)
                .environmentObject(authManager)
                .frame(minWidth: 500, minHeight: 400)
        )

        // Store reference and show
        shared = controller
        controller.showWindow(nil)

        // Clean up when window closes
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            AccountWindowController.shared = nil
        }
    }
}
