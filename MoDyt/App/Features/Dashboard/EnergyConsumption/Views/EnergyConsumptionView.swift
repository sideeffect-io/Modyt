import SwiftUI

struct EnergyConsumptionView: View {
    @Environment(\.energyConsumptionStoreFactory) private var energyConsumptionStoreFactory

    let uniqueId: String

    var body: some View {
        WithStoreView(factory: { energyConsumptionStoreFactory.make(uniqueId) }) { store in
            energyContent(descriptor: store.descriptor)
        }
    }

    private func energyContent(descriptor: EnergyConsumptionDescriptor?) -> some View {
        let normalizedValue = descriptor?.normalizedValue ?? 0
        let valueLabel = descriptor.map { formattedValue($0.value) } ?? "--"
        let unitLabel = descriptor?.unitSymbol ?? "kWh"

        return HStack(alignment: .center, spacing: 12) {
            EnergyConsumptionGauge(normalizedValue: normalizedValue)
                .frame(width: 60, height: 60)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(valueLabel)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(unitLabel)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Energy consumption")
        .accessibilityValue(accessibilityValue(descriptor: descriptor))
    }

    private func formattedValue(_ value: Double) -> String {
        if value >= 100 {
            return value.formatted(.number.precision(.fractionLength(0)))
        }
        return value.formatted(.number.precision(.fractionLength(1)))
    }

    private func accessibilityValue(descriptor: EnergyConsumptionDescriptor?) -> String {
        guard let descriptor else { return "Unavailable" }
        let valueLabel = descriptor.value.formatted(.number.precision(.fractionLength(0...1)))
        return "\(valueLabel) \(descriptor.unitSymbol)"
    }
}

private struct EnergyConsumptionGauge: View {
    @Environment(\.colorScheme) private var colorScheme

    let normalizedValue: Double

    var body: some View {
        let progress = CGFloat(min(max(normalizedValue, 0), 1))
        let angle = Self.startAngle + Self.sweepAngle * Double(progress)
        let radius = Self.diameter * 0.5 - Self.lineWidth * 0.5

        ZStack {
            EnergyArc(progress: 1)
                .stroke(trackColor, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))

            EnergyArc(progress: progress)
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
            .init(color: .green, location: 0),
            .init(color: .yellow, location: 0.5),
            .init(color: .orange, location: 0.75),
            .init(color: .red, location: 1)
        ]),
        center: .center,
        startAngle: .degrees(startAngle),
        endAngle: .degrees(startAngle + sweepAngle)
    )
}

private struct EnergyArc: Shape {
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
