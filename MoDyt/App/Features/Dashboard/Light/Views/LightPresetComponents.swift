import SwiftUI

struct LightPresetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct LightPresetIcon: View {
    let preset: LightPreset

    private var fillRatio: CGFloat {
        switch preset {
        case .on:
            return 1
        case .half:
            return 0.58
        case .off:
            return 0
        }
    }

    private var accentColor: Color {
        switch preset {
        case .on:
            return AppColors.ember
        case .half:
            return AppColors.ember.opacity(0.8)
        case .off:
            return Color.primary.opacity(0.55)
        }
    }

    private var fillGradient: LinearGradient {
        switch preset {
        case .on:
            LinearGradient(
                colors: [Color.yellow.opacity(0.96), accentColor.opacity(0.84)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .half:
            LinearGradient(
                colors: [
                    Color.yellow.opacity(0.99),
                    Color.yellow.opacity(0.90),
                    accentColor.opacity(0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .off:
            LinearGradient(
                colors: [Color.clear, Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var rayOpacity: Double {
        switch preset {
        case .on:
            return 1
        case .half:
            return 0.55
        case .off:
            return 0
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let neckRect = CGRect(
                x: size.width * 0.39,
                y: size.height * 0.54,
                width: size.width * 0.22,
                height: size.height * 0.10
            )
            let baseRect = CGRect(
                x: size.width * 0.34,
                y: size.height * 0.64,
                width: size.width * 0.32,
                height: size.height * 0.14
            )

            ZStack {
                LightBulbRaysShape()
                    .stroke(accentColor.opacity(rayOpacity), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))

                LightBulbGlassShape()
                    .fill(Color.primary.opacity(0.05))

                if fillRatio > 0 {
                    LightBulbGlassShape()
                        .fill(fillGradient)
                        .mask {
                            GeometryReader { maskProxy in
                                VStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    Rectangle()
                                        .frame(height: maskProxy.size.height * fillRatio)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                }

                LightBulbGlassShape()
                    .stroke(Color.primary.opacity(0.88), lineWidth: 1.35)

                RoundedRectangle(cornerRadius: neckRect.width * 0.28, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: neckRect.width, height: neckRect.height)
                    .offset(y: size.height * 0.25)
                    .overlay {
                        RoundedRectangle(cornerRadius: neckRect.width * 0.28, style: .continuous)
                            .stroke(Color.primary.opacity(0.70), lineWidth: 1.1)
                            .frame(width: neckRect.width, height: neckRect.height)
                            .offset(y: size.height * 0.25)
                    }

                RoundedRectangle(cornerRadius: baseRect.width * 0.18, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: baseRect.width, height: baseRect.height)
                    .offset(y: size.height * 0.38)
                    .overlay {
                        RoundedRectangle(cornerRadius: baseRect.width * 0.18, style: .continuous)
                            .stroke(Color.primary.opacity(0.70), lineWidth: 1.1)
                            .frame(width: baseRect.width, height: baseRect.height)
                            .offset(y: size.height * 0.38)
                    }

                VStack(spacing: 2.5) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.52))
                    Rectangle()
                        .fill(Color.primary.opacity(0.52))
                }
                .frame(width: baseRect.width * 0.56, height: baseRect.height * 0.42)
                .offset(y: size.height * 0.38)

                LightBulbFilamentShape()
                    .stroke(accentColor, style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round))
                    .opacity(preset == .off ? 0.45 : 1)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct LightBulbGlassShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let bulbRect = CGRect(
            x: rect.minX + w * 0.26,
            y: rect.minY + h * 0.06,
            width: w * 0.48,
            height: h * 0.54
        )
        let neckWidth = w * 0.22
        let neckHeight = h * 0.10
        let neckRect = CGRect(
            x: rect.midX - neckWidth * 0.5,
            y: bulbRect.maxY - neckHeight * 0.25,
            width: neckWidth,
            height: neckHeight
        )

        var path = Path()
        path.addEllipse(in: bulbRect)
        path.addRoundedRect(
            in: neckRect,
            cornerSize: CGSize(width: neckWidth * 0.28, height: neckWidth * 0.28)
        )
        return path
    }
}

private struct LightBulbFilamentShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let centerX = rect.midX
        let topY = rect.minY + h * 0.30
        let midY = rect.minY + h * 0.42
        let bottomY = rect.minY + h * 0.53

        var path = Path()
        path.move(to: CGPoint(x: centerX - w * 0.09, y: topY))
        path.addLine(to: CGPoint(x: centerX - w * 0.03, y: midY))
        path.addLine(to: CGPoint(x: centerX + w * 0.03, y: midY))
        path.addLine(to: CGPoint(x: centerX + w * 0.09, y: topY))
        path.move(to: CGPoint(x: centerX - w * 0.05, y: bottomY))
        path.addLine(to: CGPoint(x: centerX - w * 0.03, y: midY))
        path.move(to: CGPoint(x: centerX + w * 0.05, y: bottomY))
        path.addLine(to: CGPoint(x: centerX + w * 0.03, y: midY))
        return path
    }
}

private struct LightBulbRaysShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let center = CGPoint(x: rect.midX, y: rect.minY + h * 0.33)

        let rays: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0, -h * 0.20, 0, -h * 0.32),
            (-w * 0.18, -h * 0.12, -w * 0.28, -h * 0.19),
            (w * 0.18, -h * 0.12, w * 0.28, -h * 0.19),
            (-w * 0.24, h * 0.02, -w * 0.34, h * 0.02),
            (w * 0.24, h * 0.02, w * 0.34, h * 0.02),
        ]

        var path = Path()
        for ray in rays {
            path.move(to: CGPoint(x: center.x + ray.0, y: center.y + ray.1))
            path.addLine(to: CGPoint(x: center.x + ray.2, y: center.y + ray.3))
        }
        return path
    }
}
