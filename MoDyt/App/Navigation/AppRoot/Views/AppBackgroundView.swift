import SwiftUI

struct AppBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    private struct BackgroundBlob: Identifiable {
        let id: Int
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
        let blur: CGFloat
        let opacity: Double
        let blendMode: BlendMode
    }

    private struct NoiseDot: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
        let radius: CGFloat
        let opacity: Double
    }

    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &*= 6364136223846793005
            state &+= 1
            return state
        }
    }

    private static let noiseDots: [NoiseDot] = {
        var rng = SeededGenerator(seed: 0xC0FFEE)
        return (0..<140).map { index in
            NoiseDot(
                id: index,
                x: CGFloat.random(in: 0...1, using: &rng),
                y: CGFloat.random(in: 0...1, using: &rng),
                radius: CGFloat.random(in: 0.0015...0.0045, using: &rng),
                opacity: Double.random(in: 0.15...0.45, using: &rng)
            )
        }
    }()

    private var blobs: [BackgroundBlob] {
        colorScheme == .dark ? darkBlobs : lightBlobs
    }

    private var gradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.03, green: 0.04, blue: 0.06),
                Color(red: 0.07, green: 0.09, blue: 0.14),
                Color(red: 0.1, green: 0.18, blue: 0.24)
            ]
        }

        return [
            Color(red: 0.84, green: 0.88, blue: 0.93),
            Color(red: 0.68, green: 0.76, blue: 0.85),
            Color(red: 0.81, green: 0.71, blue: 0.62)
        ]
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)

                ForEach(blobs) { blob in
                    Circle()
                        .fill(blob.color)
                        .frame(width: blob.radius * 2, height: blob.radius * 2)
                        .position(
                            x: proxy.size.width * blob.x,
                            y: proxy.size.height * blob.y
                        )
                        .blur(radius: blob.blur)
                        .opacity(blob.opacity)
                        .blendMode(blob.blendMode)
                }

                if colorScheme != .dark {
                    LinearGradient(
                        colors: [
                            Color(red: 0.11, green: 0.14, blue: 0.18).opacity(0.16),
                            Color(red: 0.12, green: 0.16, blue: 0.20).opacity(0.10),
                            Color(red: 0.22, green: 0.16, blue: 0.11).opacity(0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.multiply)

                    Color(red: 0.08, green: 0.10, blue: 0.14)
                        .opacity(0.06)
                        .blendMode(.multiply)
                }

                if colorScheme == .dark {
                    Canvas { context, size in
                        for dot in Self.noiseDots {
                            let radius = min(size.width, size.height) * dot.radius
                            let rect = CGRect(
                                x: size.width * dot.x,
                                y: size.height * dot.y,
                                width: radius,
                                height: radius
                            )
                            context.fill(
                                Path(ellipseIn: rect),
                                with: .color(.white.opacity(dot.opacity))
                            )
                        }
                    }
                    .blendMode(.overlay)
                    .opacity(0.18)
                }
            }
            .ignoresSafeArea()
        }
    }

    private let lightBlobs: [BackgroundBlob] = [
        BackgroundBlob(
            id: 0,
            color: AppColors.sunrise,
            radius: 220,
            x: 0.15,
            y: 0.18,
            blur: 40,
            opacity: 0.68,
            blendMode: .softLight
        ),
        BackgroundBlob(
            id: 1,
            color: AppColors.aurora,
            radius: 260,
            x: 0.85,
            y: 0.12,
            blur: 55,
            opacity: 0.42,
            blendMode: .overlay
        ),
        BackgroundBlob(
            id: 2,
            color: AppColors.cloud,
            radius: 320,
            x: 0.25,
            y: 0.75,
            blur: 60,
            opacity: 0.52,
            blendMode: .softLight
        ),
        BackgroundBlob(
            id: 3,
            color: AppColors.ember,
            radius: 240,
            x: 0.8,
            y: 0.8,
            blur: 70,
            opacity: 0.34,
            blendMode: .overlay
        )
    ]

    private let darkBlobs: [BackgroundBlob] = [
        BackgroundBlob(
            id: 0,
            color: AppColors.aurora,
            radius: 300,
            x: 0.18,
            y: 0.22,
            blur: 70,
            opacity: 0.5,
            blendMode: .screen
        ),
        BackgroundBlob(
            id: 1,
            color: AppColors.ember,
            radius: 260,
            x: 0.88,
            y: 0.2,
            blur: 70,
            opacity: 0.45,
            blendMode: .screen
        ),
        BackgroundBlob(
            id: 2,
            color: Color(red: 0.16, green: 0.24, blue: 0.32),
            radius: 420,
            x: 0.2,
            y: 0.82,
            blur: 90,
            opacity: 0.55,
            blendMode: .plusLighter
        ),
        BackgroundBlob(
            id: 3,
            color: Color(red: 0.09, green: 0.14, blue: 0.2),
            radius: 460,
            x: 0.82,
            y: 0.78,
            blur: 100,
            opacity: 0.6,
            blendMode: .plusLighter
        )
    ]
}
