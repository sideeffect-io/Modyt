import SwiftUI

struct SunlightView: View {
    @Environment(\.sunlightStoreFactory) private var sunlightStoreFactory

    let uniqueId: String

    var body: some View {
        WithStoreView(factory: { sunlightStoreFactory.make(uniqueId) }) { store in
            sunlightContent(descriptor: store.descriptor)
        }
    }

    private func sunlightContent(descriptor: SunlightDescriptor?) -> some View {
        let normalizedValue = descriptor?.normalizedValue ?? 0
        let valueLabel = descriptor.map { Int($0.value.rounded()).formatted() } ?? "--"
        let unitLabel = descriptor?.unitSymbol ?? "W/m2"

        return HStack(alignment: .center, spacing: 12) {
            SunlightGauge(normalizedValue: normalizedValue)
                .frame(width: 60, height: 60)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(valueLabel)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(unitLabel)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sunlight")
        .accessibilityValue(accessibilityValue(descriptor: descriptor))
    }

    private func accessibilityValue(descriptor: SunlightDescriptor?) -> String {
        guard let descriptor else { return "Unavailable" }
        let valueLabel = descriptor.value.formatted(.number.precision(.fractionLength(0)))
        return "\(valueLabel) \(descriptor.unitSymbol)"
    }
}

private struct SunlightGauge: View {
    @Environment(\.colorScheme) private var colorScheme

    let normalizedValue: Double

    var body: some View {
        let progress = CGFloat(min(max(normalizedValue, 0), 1))
        let angle = Self.startAngle + Self.sweepAngle * Double(progress)
        let radius = Self.diameter * 0.5 - Self.lineWidth * 0.5

        ZStack {
            SunlightArc(progress: 1)
                .stroke(trackColor, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))

            SunlightArc(progress: progress)
                .stroke(Self.gaugeGradient, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))

            Circle()
                .fill(.white)
                .overlay {
                    Circle()
                        .strokeBorder(AppColors.midnight.opacity(0.2), lineWidth: 1)
                }
                .frame(width: Self.handleSize, height: Self.handleSize)
                .offset(x: radius)
                .rotationEffect(.degrees(angle))
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .rotationEffect(.degrees(-90))
    }

    private var trackColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.24) : AppColors.cloud.opacity(0.95)
    }

    private static let diameter: CGFloat = 60
    private static let lineWidth: CGFloat = 8
    private static let handleSize: CGFloat = 12
    private static let startAngle: Double = -150
    private static let sweepAngle: Double = 300

    private static let gaugeGradient = AngularGradient(
        gradient: Gradient(stops: [
            .init(color: .cyan, location: 0),
            .init(color: .yellow, location: 0.5),
            .init(color: .red, location: 1)
        ]),
        center: .center,
        startAngle: .degrees(startAngle),
        endAngle: .degrees(startAngle + sweepAngle)
    )
}

private struct SunlightArc: Shape {
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
