//
//  VirtualProductionCommands.swift
//  Vantaview - Keyboard Commands for Virtual Production
//

import SwiftUI

struct VirtualProductionCommands: Commands {
    var body: some Commands {
        CommandMenu("Virtual Studio") {
            Button("Toggle Command Palette") {
                NotificationCenter.default.post(name: .toggleCommandPalette, object: nil)
            }
            .keyboardShortcut("k", modifiers: .command)
            
            Divider()
            
            Button("Toggle Tools Panel") {
                NotificationCenter.default.post(name: .toggleLeftPanel, object: nil)
            }
            .keyboardShortcut("1", modifiers: .command)
            
            Button("Toggle Properties Panel") {
                NotificationCenter.default.post(name: .toggleRightPanel, object: nil)
            }
            .keyboardShortcut("2", modifiers: .command)
            
            Divider()
            
            Button("Select Tool") {
                // Handle tool selection
            }
            .keyboardShortcut(.tab)
            
            Button("LED Wall Tool") {
                // Handle LED wall tool
            }
            .keyboardShortcut("l")
            
            Button("Camera Tool") {
                // Handle camera tool
            }
            .keyboardShortcut("c")
        }
    }
}