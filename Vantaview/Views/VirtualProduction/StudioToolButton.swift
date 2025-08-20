//
//  StudioToolButton.swift
//  Vistaview
//

import SwiftUI

struct StudioToolButton: View {
    let tool: StudioToolType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: tool.icon)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? .white : .primary)
                
                VStack(spacing: 2) {
                    Text(tool.rawValue)
                        .font(.caption)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    Text(tool.shortcut)
                        .font(.caption2)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.blue : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .help("\(tool.rawValue) (\(tool.shortcut))")
    }
}