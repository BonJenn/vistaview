//
//  TahoeDesignSystem.swift
//  Vistaview
//
//  macOS 26 Tahoe Liquid Glass Design System
//  Preserves all app functionality while enhancing visual aesthetics
//

import SwiftUI

// MARK: - Tahoe Design Constants

struct TahoeDesign {
    
    // MARK: - Colors
    struct Colors {
        // Glass tints for different contexts
        static let glassTint = Color.white.opacity(0.1)
        static let glassAccent = Color.accentColor.opacity(0.15)
        static let glassBorder = Color.white.opacity(0.2)
        
        // Status colors with glass tinting
        static let previewGlass = Color.yellow.opacity(0.12)
        static let programGlass = Color.red.opacity(0.12)
        static let liveGlass = Color.green.opacity(0.12)
        static let virtualGlass = Color.blue.opacity(0.12)
        
        // Surface colors
        static let surfaceUltraLight = Color.white.opacity(0.03)
        static let surfaceLight = Color.white.opacity(0.05)
        static let surfaceMedium = Color.white.opacity(0.08)
        static let surfaceHeavy = Color.white.opacity(0.12)
        
        // Accent colors
        static let preview = Color.yellow
        static let program = Color.red
        static let live = Color.green
        static let virtual = Color.blue
        static let accent = Color.accentColor
    }
    
    // MARK: - Materials
    struct Materials {
        static let ultraThin = Material.ultraThinMaterial
        static let thin = Material.thinMaterial
        static let regular = Material.regularMaterial
        static let thick = Material.thickMaterial
        static let ultraThick = Material.ultraThickMaterial
    }
    
    // MARK: - Spacing
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }
    
    // MARK: - Corner Radius
    struct CornerRadius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 20
        static let continuous: CGFloat = 16 // For continuous corner radius
    }
    
    // MARK: - Shadow
    struct Shadow {
        static let light = (color: Color.black.opacity(0.05), radius: CGFloat(2), x: CGFloat(0), y: CGFloat(1))
        static let medium = (color: Color.black.opacity(0.08), radius: CGFloat(6), x: CGFloat(0), y: CGFloat(3))
        static let heavy = (color: Color.black.opacity(0.12), radius: CGFloat(12), x: CGFloat(0), y: CGFloat(6))
        static let dramatic = (color: Color.black.opacity(0.2), radius: CGFloat(20), x: CGFloat(0), y: CGFloat(10))
    }
}

// MARK: - Liquid Glass View Modifiers

struct LiquidGlassPanel: ViewModifier {
    let material: Material
    let cornerRadius: CGFloat
    let borderOpacity: Double
    let shadowIntensity: ShadowIntensity
    let padding: EdgeInsets?
    
    enum ShadowIntensity {
        case none, light, medium, heavy, dramatic
        
        var shadow: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
            switch self {
            case .none: return (Color.clear, 0, 0, 0)
            case .light: return TahoeDesign.Shadow.light
            case .medium: return TahoeDesign.Shadow.medium
            case .heavy: return TahoeDesign.Shadow.heavy
            case .dramatic: return TahoeDesign.Shadow.dramatic
            }
        }
    }
    
    init(
        material: Material = .regularMaterial,
        cornerRadius: CGFloat = TahoeDesign.CornerRadius.lg,
        borderOpacity: Double = 0.15,
        shadowIntensity: ShadowIntensity = .medium,
        padding: EdgeInsets? = nil
    ) {
        self.material = material
        self.cornerRadius = cornerRadius
        self.borderOpacity = borderOpacity
        self.shadowIntensity = shadowIntensity
        self.padding = padding
    }
    
    func body(content: Content) -> some View {
        let paddedContent = padding != nil ? AnyView(content.padding(padding!)) : AnyView(content)
        let shadow = shadowIntensity.shadow
        
        return paddedContent
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(material)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(.white.opacity(borderOpacity), lineWidth: 0.5)
                    )
                    .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
            )
    }
}

struct LiquidGlassButton: ButtonStyle {
    let material: Material
    let accentColor: Color
    let cornerRadius: CGFloat
    let size: ButtonSize
    
    enum ButtonSize {
        case small, medium, large
        
        var padding: EdgeInsets {
            switch self {
            case .small: return EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            case .medium: return EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
            case .large: return EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
            }
        }
        
        var font: Font {
            switch self {
            case .small: return .caption
            case .medium: return .callout
            case .large: return .body
            }
        }
    }
    
    init(
        material: Material = .thinMaterial,
        accentColor: Color = .accentColor,
        cornerRadius: CGFloat = TahoeDesign.CornerRadius.md,
        size: ButtonSize = .medium
    ) {
        self.material = material
        self.accentColor = accentColor
        self.cornerRadius = cornerRadius
        self.size = size
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .fontWeight(.medium)
            .padding(size.padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(material)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(accentColor.opacity(configuration.isPressed ? 0.3 : 0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(accentColor.opacity(0.3), lineWidth: 0.5)
                    )
                    .shadow(
                        color: .black.opacity(0.08),
                        radius: configuration.isPressed ? 2 : 4,
                        x: 0,
                        y: configuration.isPressed ? 1 : 2
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - View Extensions

extension View {
    func liquidGlassPanel(
        material: Material = .regularMaterial,
        cornerRadius: CGFloat = TahoeDesign.CornerRadius.lg,
        borderOpacity: Double = 0.15,
        shadowIntensity: LiquidGlassPanel.ShadowIntensity = .medium,
        padding: EdgeInsets? = nil
    ) -> some View {
        modifier(LiquidGlassPanel(
            material: material,
            cornerRadius: cornerRadius,
            borderOpacity: borderOpacity,
            shadowIntensity: shadowIntensity,
            padding: padding
        ))
    }
    
    func liquidGlassMonitor(
        borderColor: Color = .white,
        cornerRadius: CGFloat = TahoeDesign.CornerRadius.lg,
        glowIntensity: Double = 0.3,
        isActive: Bool = true
    ) -> some View {
        background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: isActive ? 2 : 1)
                    .shadow(
                        color: borderColor.opacity(isActive ? glowIntensity : glowIntensity * 0.3),
                        radius: isActive ? 8 : 4,
                        x: 0,
                        y: 0
                    )
            )
            .shadow(
                color: .black.opacity(0.2),
                radius: 12,
                x: 0,
                y: 6
            )
    }
    
    func statusIndicator(
        color: Color,
        isActive: Bool = true
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: TahoeDesign.CornerRadius.sm, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: TahoeDesign.CornerRadius.sm, style: .continuous)
                        .fill(color.opacity(isActive ? 0.2 : 0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: TahoeDesign.CornerRadius.sm, style: .continuous)
                        .stroke(color.opacity(isActive ? 0.4 : 0.12), lineWidth: 0.5)
                )
        )
        .shadow(
            color: color.opacity(isActive ? 0.2 : 0.05),
            radius: 3,
            x: 0,
            y: 1
        )
    }
}

// MARK: - Animation Presets

struct TahoeAnimations {
    static let standardEasing = Animation.easeInOut(duration: 0.3)
    static let quickEasing = Animation.easeInOut(duration: 0.15)
    static let slowEasing = Animation.easeInOut(duration: 0.5)
    
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let bouncy = Animation.spring(response: 0.3, dampingFraction: 0.6)
    static let smooth = Animation.spring(response: 0.6, dampingFraction: 1.0)
    
    // Specialized animations for UI interactions
    static let buttonPress = Animation.easeInOut(duration: 0.1)
    static let panelSlide = Animation.spring(response: 0.5, dampingFraction: 0.8)
    static let statusChange = Animation.easeInOut(duration: 0.25)
}
