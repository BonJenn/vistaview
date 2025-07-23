//
//  ObjectPropertiesView.swift
//  Vistaview
//

import SwiftUI
import SceneKit

struct ObjectPropertiesView: View {
    @ObservedObject var object: StudioObject
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Object Info Header
            HStack {
                Image(systemName: object.type.icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Object Name", text: $object.name)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.headline)
                    
                    Text(object.type.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // Basic Transform Properties
            VStack(alignment: .leading, spacing: 12) {
                Text("Transform")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                // Position
                VStack(alignment: .leading, spacing: 8) {
                    Text("Position")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        VStack {
                            Text("X")
                                .font(.caption2)
                                .foregroundColor(.red)
                            TextField("X", value: Binding(
                                get: { Double(object.position.x) },
                                set: { newValue in
                                    object.position.x = CGFloat(newValue)
                                    object.updateNodeTransform()
                                }
                            ), format: .number.precision(.fractionLength(2)))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.caption)
                        }
                        
                        VStack {
                            Text("Y")
                                .font(.caption2)
                                .foregroundColor(.green)
                            TextField("Y", value: Binding(
                                get: { Double(object.position.y) },
                                set: { newValue in
                                    object.position.y = CGFloat(newValue)
                                    object.updateNodeTransform()
                                }
                            ), format: .number.precision(.fractionLength(2)))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.caption)
                        }
                        
                        VStack {
                            Text("Z")
                                .font(.caption2)
                                .foregroundColor(.blue)
                            TextField("Z", value: Binding(
                                get: { Double(object.position.z) },
                                set: { newValue in
                                    object.position.z = CGFloat(newValue)
                                    object.updateNodeTransform()
                                }
                            ), format: .number.precision(.fractionLength(2)))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.caption)
                        }
                    }
                }
            }
            
            Spacer()
        }
    }
}