PropertySection(title: "Transform") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        // Position property
                                        HStack {
                                            Text("Position:")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.6))
                                                .frame(width: 60, alignment: .leading)
                                            
                                            let pos = firstSelected.position
                                            Text("(\(pos.x, specifier: "%.2f"), \(pos.y, specifier: "%.2f"), \(pos.z, specifier: "%.2f"))")
                                                .font(.caption.monospaced())
                                                .foregroundColor(.white.opacity(0.8))
                                            
                                            Spacer()
                                        }
                                        
                                        // Rotation property
                                        HStack {
                                            Text("Rotation:")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.6))
                                                .frame(width: 60, alignment: .leading)
                                            
                                            let rot = firstSelected.rotation
                                            let rotDeg = (rot.x * 180 / Float.pi, rot.y * 180 / Float.pi, rot.z * 180 / Float.pi)
                                            Text("(\(rotDeg.0, specifier: "%.1f")°, \(rotDeg.1, specifier: "%.1f")°, \(rotDeg.2, specifier: "%.1f")°)")
                                                .font(.caption.monospaced())
                                                .foregroundColor(.white.opacity(0.8))
                                            
                                            Spacer()
                                        }
                                        
                                        // Scale property
                                        HStack {
                                            Text("Scale:")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.6))
                                                .frame(width: 60, alignment: .leading)
                                            
                                            let scale = firstSelected.scale
                                            Text("(\(scale.x, specifier: "%.2f"), \(scale.y, specifier: "%.2f"), \(scale.z, specifier: "%.2f"))")
                                                .font(.caption.monospaced())
                                                .foregroundColor(.white.opacity(0.8))
                                            
                                            Spacer()
                                        }
                                    }
                                }
                                
                                PropertySection(title: "Object Info") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        // Name property
                                        HStack {
                                            Text("Name:")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.6))
                                                .frame(width: 60, alignment: .leading)
                                            
                                            Text(firstSelected.name)
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.8))
                                            
                                            Spacer()
                                        }
                                        
                                        // Type property
                                        HStack {
                                            Text("Type:")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.6))
                                                .frame(width: 60, alignment: .leading)
                                            
                                            HStack(spacing: 4) {
                                                Image(systemName: firstSelected.type.icon)
                                                    .foregroundColor(colorForObjectType(firstSelected.type))
                                                Text(firstSelected.type.name)
                                            }
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.8))
                                            
                                            Spacer()
                                        }
                                        
                                        // Visibility property
                                        HStack {
                                            Text("Visible:")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.6))
                                                .frame(width: 60, alignment: .leading)
                                            
                                            Image(systemName: firstSelected.isVisible ? "eye" : "eye.slash")
                                                .foregroundColor(firstSelected.isVisible ? .green : .red)
                                                .font(.caption)
                                            
                                            Spacer()
                                        }
                                        
                                        // Lock property
                                        HStack {
                                            Text("Locked:")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.6))
                                                .frame(width: 60, alignment: .leading)
                                            
                                            Image(systemName: firstSelected.isLocked ? "lock.fill" : "lock.open")
                                                .foregroundColor(firstSelected.isLocked ? .orange : .gray)
                                                .font(.caption)
                                            
                                            Spacer()
                                        }
                                    }
                                }