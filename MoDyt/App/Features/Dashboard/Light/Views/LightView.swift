import SwiftUI

struct LightView: View {
    @Environment(\.lightStoreDependencies) private var lightStoreDependencies
    @Environment(\.colorScheme) private var colorScheme

    let identifier: DeviceIdentifier

    init(identifier: DeviceIdentifier) {
        self.identifier = identifier
    }

    var body: some View {
        WithStoreView(
            store: LightStore(
                identifier: identifier,
                dependencies: lightStoreDependencies
            )
        ) { _ in
            HStack(alignment: .center, spacing: 14) {
                LightGaugeView(colorScheme: colorScheme)
                    .frame(width: 86, height: 86)
                    .frame(maxWidth: .infinity, alignment: .center)

                PowerClusterView()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement(children: .contain)
        }
    }
}

private struct LightGaugeView: View {
    let colorScheme: ColorScheme

    private let normalizedValue = 0.0
    private let isOn = false

    var body: some View {
        let progress = CGFloat(normalizedValue)
        let angle = Self.startAngle + (Self.sweepAngle * normalizedValue)
        let radius = Self.diameter * 0.5 - Self.lineWidth * 0.5
        let percentage = Int((normalizedValue * 100).rounded())

        ZStack {
            GaugeArc(progress: 1)
                .stroke(trackColor, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))

            GaugeArc(progress: progress)
                .stroke(
                    isOn ? Self.onGradient : Self.offGradient,
                    style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round)
                )

            Circle()
                .fill(.white)
                .overlay {
                    Circle()
                        .strokeBorder(AppColors.midnight.opacity(0.18), lineWidth: 1)
                }
                .frame(width: Self.handleSize, height: Self.handleSize)
                .offset(x: radius)
                .rotationEffect(.degrees(angle))
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)

            VStack(spacing: 2) {
                Image(systemName: isOn ? "lightbulb.max.fill" : "lightbulb.slash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("\(percentage)")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .monospacedDigit()
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Light brightness")
        .accessibilityValue("\(percentage)%")
    }

    private var trackColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.26) : AppColors.cloud.opacity(0.95)
    }

    private static let diameter: CGFloat = 86
    private static let lineWidth: CGFloat = 11
    private static let handleSize: CGFloat = 20
    private static let startAngle: Double = -150
    private static let sweepAngle: Double = 300

    private static let onGradient = AngularGradient(
        colors: [Color.yellow, AppColors.ember, Color.yellow],
        center: .center
    )

    private static let offGradient = AngularGradient(
        colors: [Color.white.opacity(0.5), Color.white.opacity(0.2)],
        center: .center
    )
}

private struct PowerClusterView: View {
    private let isOn = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Self.buttonBackground)
                Circle()
                    .strokeBorder(.blue.opacity(0.55), lineWidth: 1.2)
                Image(systemName: "power")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.blue.opacity(0.9))
            }
            .frame(width: 48, height: 48)
            .shadow(
                color: .blue.opacity(0.28),
                radius: 6,
                x: 0,
                y: 2
            )
            .accessibilityLabel(isOn ? "Turn lights off" : "Turn lights on")
            .accessibilityValue(isOn ? "On" : "Off")

            Text("Power")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private static let buttonBackground = LinearGradient(
        colors: [Color.blue.opacity(0.38), Color.blue.opacity(0.24)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct GaugeArc: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clampedProgress = min(max(progress, 0), 1)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.5 - Self.lineWidth * 0.5
        let startAngle = Angle.degrees(Self.startAngle)
        let endAngle = Angle.degrees(Self.startAngle + Self.sweepAngle * Double(clampedProgress))

        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }

    private static let lineWidth: CGFloat = 11
    private static let startAngle: Double = -150
    private static let sweepAngle: Double = 300
}
