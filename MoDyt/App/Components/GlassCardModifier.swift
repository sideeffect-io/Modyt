import SwiftUI

enum GlassCardTone {
    case surface
    case inset
}

extension View {
    func glassCard(
        cornerRadius: CGFloat = 20,
        interactive: Bool = true,
        tone: GlassCardTone = .surface
    ) -> some View {
        modifier(
            FauxGlassCardModifier(
                cornerRadius: cornerRadius,
                interactive: interactive,
                tone: tone
            )
        )
    }
}

private struct FauxGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let interactive: Bool
    let tone: GlassCardTone

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                shape
                    .fill(materialStyle)
                    .overlay { shape.fill(baseTint) }
                    .overlay { shape.fill(topHighlight) }
                    .overlay { shape.fill(bottomVignette) }
                    .overlay {
                        shape.strokeBorder(
                            Color.white.opacity(colorScheme == .dark ? (tone == .inset ? 0.06 : 0.07) : (tone == .inset ? 0.12 : 0.24)),
                            lineWidth: tone == .inset ? 0.95 : 0.8
                        )
                    }
                    .overlay {
                        shape.strokeBorder(
                            Color.black.opacity(colorScheme == .dark ? (tone == .inset ? 0.30 : 0.17) : (tone == .inset ? 0.012 : 0.001)),
                            lineWidth: tone == .inset ? 0.8 : 0.5
                        )
                    }
                    .shadow(
                        color: Color.black.opacity(
                            colorScheme == .dark
                                ? (tone == .inset ? 0.0 : 0.24)
                                : (tone == .inset ? 0.012 : 0.045)
                        ),
                        radius: interactive
                            ? (tone == .inset ? (colorScheme == .dark ? 0 : 2.1) : (colorScheme == .dark ? 10 : 5.1))
                            : (colorScheme == .dark ? 0 : 2.2),
                        x: 0,
                        y: interactive
                            ? (tone == .inset ? (colorScheme == .dark ? 0 : 1.0) : (colorScheme == .dark ? 0 : 2.1))
                            : (colorScheme == .dark ? 0 : 1.0)
                    )
            }
    }

    private var baseTint: AnyShapeStyle {
        if colorScheme == .dark {
            if tone == .inset {
                return AnyShapeStyle(
                    Color(red: 0.055, green: 0.15, blue: 0.21)
                        .opacity(interactive ? 0.83 : 0.73)
                )
            }

            return AnyShapeStyle(
                Color(red: 0.075, green: 0.21, blue: 0.28)
                    .opacity(interactive ? 0.67 : 0.57)
            )
        }

        return AnyShapeStyle(
            Color(
                red: tone == .inset ? 0.91 : 1.0,
                green: tone == .inset ? 0.92 : 1.0,
                blue: tone == .inset ? 0.96 : 1.0
            )
            .opacity(interactive ? (tone == .inset ? 0.33 : 0.64) : (tone == .inset ? 0.29 : 0.58))
        )
    }

    private var topHighlight: AnyShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(
                Color.white.opacity(
                    tone == .inset ? (interactive ? 0.005 : 0.003) : (interactive ? 0.018 : 0.012)
                )
            )
        }

        return AnyShapeStyle(
            Color.white.opacity(tone == .inset ? 0.028 : 0.095)
        )
    }

    private var bottomVignette: AnyShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(
                Color.black.opacity(
                    tone == .inset ? (interactive ? 0.095 : 0.075) : (interactive ? 0.07 : 0.055)
                )
            )
        }

        return AnyShapeStyle(
            Color.black.opacity(tone == .inset ? 0.022 : 0.0)
        )
    }

    private var materialStyle: AnyShapeStyle {
        AnyShapeStyle(colorScheme == .dark ? .ultraThinMaterial : .thinMaterial)
    }
}
