// SPDX-License-Identifier: MPL-2.0

import SwiftUI

/// Design system tokens for consistent styling across the app.
public enum DesignTokens {
    /// Spacing scale based on 8pt grid
    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 24
        public static let xl: CGFloat = 32
        public static let xxl: CGFloat = 48
    }

    /// Corner radius scale
    public enum CornerRadius {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let circle: CGFloat = 999
    }

    /// Shadow tokens
    public enum Shadow {
        public static let sm = ShadowToken(radius: 2, x: 0, y: 1, opacity: 0.05)
        public static let md = ShadowToken(radius: 8, x: 0, y: 4, opacity: 0.08)
        public static let lg = ShadowToken(radius: 16, x: 0, y: 8, opacity: 0.12)
    }

    /// Animation durations
    public enum Animation {
        public static let fast: Double = 0.15
        public static let normal: Double = 0.25
        public static let slow: Double = 0.35
    }
}

/// Shadow token for consistent shadows
public struct ShadowToken: Sendable {
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat
    public let opacity: Double

    public init(radius: CGFloat, x: CGFloat, y: CGFloat, opacity: Double) {
        self.radius = radius
        self.x = x
        self.y = y
        self.opacity = opacity
    }
}

/// Typography scale
public enum Typography {
    public static let largeTitle = Font.largeTitle.weight(.bold)
    public static let title1 = Font.title.weight(.bold)
    public static let title2 = Font.title2.weight(.semibold)
    public static let title3 = Font.title3.weight(.semibold)
    public static let headline = Font.headline.weight(.semibold)
    public static let body = Font.body
    public static let callout = Font.callout
    public static let subheadline = Font.subheadline
    public static let footnote = Font.footnote
    public static let caption1 = Font.caption
    public static let caption2 = Font.caption2
}

/// Color palette - semantic colors for light/dark mode support
public enum AppColor {
    // Primary brand colors
    public static let primary = Color("Primary")
    public static let primaryVariant = Color("PrimaryVariant")
    public static let onPrimary = Color("OnPrimary")

    // Secondary colors
    public static let secondary = Color("Secondary")
    public static let secondaryVariant = Color("SecondaryVariant")
    public static let onSecondary = Color("OnSecondary")

    // Surface colors
    public static let surface = Color("Surface")
    public static let surfaceVariant = Color("SurfaceVariant")
    public static let onSurface = Color("OnSurface")
    public static let onSurfaceVariant = Color("OnSurfaceVariant")

    // Background colors
    public static let background = Color("Background")
    public static let onBackground = Color("OnBackground")

    // Error/Status colors
    public static let error = Color("Error")
    public static let onError = Color("OnError")
    public static let success = Color("Success")
    public static let warning = Color("Warning")
    public static let info = Color("Info")

    // Outline/Border
    public static let outline = Color("Outline")
    public static let outlineVariant = Color("OutlineVariant")

    // Separator
    public static let separator = Color("Separator")
}

/// Button style configuration
public enum ButtonStyleType {
    case primary
    case secondary
    case tertiary
    case destructive
    case outline
}

/// Standard button style
public struct StandardButtonStyle: ButtonStyle {
    public let type: ButtonStyleType
    public let isLoading: Bool

    public init(type: ButtonStyleType = .primary, isLoading: Bool = false) {
        self.type = type
        self.isLoading = isLoading
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.body.weight(.semibold))
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.md)
            .background(configuration.isPressed ? backgroundColor.opacity(0.8) : backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .shadow(
                color: shadowColor.opacity(shadowToken.opacity), radius: shadowToken.radius, x: shadowToken.x,
                y: shadowToken.y
            )
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: DesignTokens.Animation.fast), value: configuration.isPressed)
            .overlay {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(foregroundColor)
                }
            }
    }

    private var backgroundColor: Color {
        switch type {
        case .primary: return AppColor.primary
        case .secondary: return AppColor.secondary
        case .tertiary: return AppColor.surfaceVariant
        case .destructive: return AppColor.error
        case .outline: return .clear
        }
    }

    private var foregroundColor: Color {
        switch type {
        case .primary: return AppColor.onPrimary
        case .secondary: return AppColor.onSecondary
        case .tertiary: return AppColor.onSurface
        case .destructive: return AppColor.onError
        case .outline: return AppColor.primary
        }
    }

    private var borderColor: Color {
        switch type {
        case .outline: return AppColor.primary
        default: return .clear
        }
    }

    private var borderWidth: CGFloat {
        switch type {
        case .outline: return 1.5
        default: return 0
        }
    }

    private var shadowToken: ShadowToken {
        switch type {
        case .primary, .secondary, .destructive:
            return DesignTokens.Shadow.sm
        default:
            return DesignTokens.Shadow.sm
        }
    }

    private var shadowColor: Color {
        Color.black.opacity(shadowToken.opacity)
    }
}

/// Card style modifier
public struct CardStyle: ViewModifier {
    public let padding: CGFloat
    public let backgroundColor: Color
    public let cornerRadius: CGFloat
    public let shadow: ShadowToken

    public init(
        padding: CGFloat = DesignTokens.Spacing.md,
        backgroundColor: Color = AppColor.surface,
        cornerRadius: CGFloat = DesignTokens.CornerRadius.md,
        shadow: ShadowToken = DesignTokens.Shadow.sm
    ) {
        self.padding = padding
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
        self.shadow = shadow
    }

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(
                color: Color.black.opacity(shadow.opacity),
                radius: shadow.radius,
                x: shadow.x,
                y: shadow.y
            )
    }
}

/// Text field style
public struct StandardTextFieldStyle: TextFieldStyle {
    public let isError: Bool

    public init(isError: Bool = false) {
        self.isError = isError
    }

    public func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .font(Typography.body)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(AppColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md)
                    .stroke(isError ? AppColor.error : AppColor.outline, lineWidth: 1.5)
            )
    }
}

/// Divider style
public struct DividerStyle: ViewModifier {
    public let color: Color
    public let thickness: CGFloat

    public init(color: Color = AppColor.separator, thickness: CGFloat = 0.5) {
        self.color = color
        self.thickness = thickness
    }

    public func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
            Rectangle()
                .fill(color)
                .frame(height: thickness)
        }
    }
}

// MARK: - View Extensions

extension View {
    public func standardButton(style: ButtonStyleType = .primary, isLoading: Bool = false) -> some View {
        self.buttonStyle(StandardButtonStyle(type: style, isLoading: isLoading))
    }

    public func card(
        padding: CGFloat = DesignTokens.Spacing.md,
        backgroundColor: Color = AppColor.surface,
        cornerRadius: CGFloat = DesignTokens.CornerRadius.md,
        shadow: ShadowToken = DesignTokens.Shadow.sm
    ) -> some View {
        self.modifier(
            CardStyle(
                padding: padding,
                backgroundColor: backgroundColor,
                cornerRadius: cornerRadius,
                shadow: shadow
            )
        )
    }

    public func standardTextField(isError: Bool = false) -> some View {
        self.textFieldStyle(StandardTextFieldStyle(isError: isError))
    }

    public func divider(color: Color = AppColor.separator, thickness: CGFloat = 0.5) -> some View {
        self.modifier(DividerStyle(color: color, thickness: thickness))
    }

    public func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            if shouldShow {
                placeholder()
            }
            self
        }
    }
}
