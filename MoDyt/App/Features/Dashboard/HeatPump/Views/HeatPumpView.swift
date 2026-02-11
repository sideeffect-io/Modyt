import SwiftUI

struct HeatPumpView: View {
    @Environment(\.heatPumpStoreFactory) private var heatPumpStoreFactory

    let uniqueId: String

    var body: some View {
        WithStoreView(factory: { heatPumpStoreFactory.make(uniqueId) }) { store in
            content(store: store)
        }
    }

    @ViewBuilder
    private func content(store: HeatPumpStore) -> some View {
        if let descriptor = store.descriptor,
           descriptor.canAdjustSetpoint,
           let setpoint = descriptor.setpoint {
            HeatPumpSetpointControl(
                setpoint: setpoint,
                range: descriptor.setpointRange,
                step: descriptor.setpointStep,
                unitSymbol: descriptor.unitSymbol ?? descriptor.temperature?.unitSymbol,
                ambientTemperature: descriptor.temperature,
                onCommit: { target in
                    store.setSetpoint(target)
                },
                onIncrement: {
                    store.incrementSetpoint()
                },
                onDecrement: {
                    store.decrementSetpoint()
                }
            )
            .frame(maxWidth: .infinity, alignment: .center)
        } else if let descriptor = store.descriptor {
            readOnlyContent(for: descriptor)
        } else {
            Text("--")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel("Heat pump unavailable")
        }
    }

    @ViewBuilder
    private func readOnlyContent(for descriptor: ThermostatDescriptor) -> some View {
        if let temperature = descriptor.temperature {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(temperature.value, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if let unitSymbol = descriptor.unitSymbol ?? temperature.unitSymbol {
                    Text(unitSymbol)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Heat pump temperature")
        } else {
            Text("--")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel("Heat pump setpoint unavailable")
        }
    }
}

private struct HeatPumpSetpointControl: View {
    let setpoint: Double
    let range: ClosedRange<Double>
    let step: Double
    let unitSymbol: String?
    let ambientTemperature: TemperatureDescriptor?
    let onCommit: (Double) -> Void
    let onIncrement: () -> Void
    let onDecrement: () -> Void

    @State private var dragValue: Double?
    @State private var renderedValue: Double?

    var body: some View {
        let presentedValue = dragValue ?? renderedValue ?? setpoint
        let digits = Self.fractionDigits(for: step)

        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(presentedValue, format: .number.precision(.fractionLength(digits)))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())

                if let unitSymbol {
                    Text(unitSymbol)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            VStack(spacing: 4) {
                HStack(spacing: 10) {
                    SetpointBumpButton(
                        systemImage: "minus",
                        fillColor: Color(red: 0.18, green: 0.38, blue: 0.66).opacity(0.28),
                        strokeColor: .blue.opacity(0.52),
                        symbolColor: .blue.opacity(0.95),
                        accessibilityLabel: "Decrease setpoint",
                        action: {
                            dragValue = nil
                            onDecrement()
                        }
                    )

                    ThermalSetpointRail(
                        value: presentedValue,
                        range: range,
                        step: step,
                        onChange: { value in
                            let snapped = Self.resolveSetpoint(value, range: range, step: step)
                            guard dragValue == nil || abs((dragValue ?? snapped) - snapped) > 0.000_5 else { return }
                            dragValue = snapped
                            renderedValue = snapped
                        },
                        onCommit: { value in
                            let snapped = Self.resolveSetpoint(value, range: range, step: step)
                            dragValue = nil
                            renderedValue = snapped
                            onCommit(snapped)
                        }
                    )
                    .frame(maxWidth: .infinity)

                    SetpointBumpButton(
                        systemImage: "plus",
                        fillColor: AppColors.ember.opacity(0.26),
                        strokeColor: AppColors.ember.opacity(0.62),
                        symbolColor: AppColors.ember.opacity(0.95),
                        accessibilityLabel: "Increase setpoint",
                        action: {
                            dragValue = nil
                            onIncrement()
                        }
                    )
                }

                if let ambientTemperature {
                    HStack(spacing: 4) {
                        Image(systemName: "thermometer.medium")
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text("Room")
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(ambientTemperature.value, format: .number.precision(.fractionLength(1)))
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)

                        if let ambientUnit = ambientTemperature.unitSymbol ?? unitSymbol {
                            Text(ambientUnit)
                                .font(.system(.caption2, design: .rounded).weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityHidden(true)
                }
            }
            .offset(y: -3)
        }
        .onAppear {
            guard renderedValue == nil else { return }
            renderedValue = setpoint
        }
        .onChange(of: setpoint) { _, newValue in
            guard dragValue == nil else { return }
            let previous = renderedValue ?? newValue
            guard abs(previous - newValue) > 0.000_5 else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                renderedValue = newValue
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heat pump setpoint")
        .accessibilityValue(accessibilityValue(for: presentedValue))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                onIncrement()
            case .decrement:
                onDecrement()
            @unknown default:
                break
            }
        }
    }

    private func accessibilityValue(for value: Double) -> String {
        let digits = Self.fractionDigits(for: step)
        let valueText = value.formatted(.number.precision(.fractionLength(digits)))
        if let unitSymbol {
            return "\(valueText) \(unitSymbol)"
        }
        return valueText
    }

    private static func resolveSetpoint(
        _ value: Double,
        range: ClosedRange<Double>,
        step: Double
    ) -> Double {
        guard range.upperBound > range.lowerBound else { return range.lowerBound }
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let resolvedStep = max(step, 0.1)
        let snappedSteps = ((clamped - range.lowerBound) / resolvedStep).rounded()
        let snapped = range.lowerBound + snappedSteps * resolvedStep
        let bounded = min(max(snapped, range.lowerBound), range.upperBound)
        let digits = max(2, fractionDigits(for: resolvedStep))
        let factor = pow(10.0, Double(digits))
        return (bounded * factor).rounded() / factor
    }

    private static func fractionDigits(for step: Double) -> Int {
        guard step > 0 else { return 1 }
        var digits = 0
        var scaled = step
        while digits < 4 && abs(scaled.rounded() - scaled) > 0.000_001 {
            scaled *= 10
            digits += 1
        }
        return digits
    }
}

private struct SetpointBumpButton: View {
    let systemImage: String
    let fillColor: Color
    let strokeColor: Color
    let symbolColor: Color
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(symbolColor)
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(fillColor)
                        .overlay {
                            Circle()
                                .strokeBorder(strokeColor, lineWidth: 0.9)
                        }
                }
                .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ThermalSetpointRail: View {
    @Environment(\.colorScheme) private var colorScheme

    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let onChange: (Double) -> Void
    let onCommit: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let normalized = normalizedValue
            let knobCenterX = min(max(8, width * normalized), width - 8)
            let fillWidth = max(14, knobCenterX)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackGradient)
                    .frame(height: 10)
                    .overlay {
                        Capsule()
                            .strokeBorder(trackStroke, lineWidth: 0.8)
                    }

                Capsule()
                    .fill(fillGradient)
                    .frame(width: fillWidth, height: 10)
                    .animation(.easeInOut(duration: 0.16), value: fillWidth)

                Circle()
                    .fill(.white)
                    .overlay {
                        Circle()
                            .strokeBorder(AppColors.midnight.opacity(0.18), lineWidth: 0.8)
                    }
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.24), radius: 3, x: 0, y: 1)
                    .offset(x: knobCenterX - 9)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        onChange(setpointValue(for: gesture.location.x, width: width))
                    }
                    .onEnded { gesture in
                        onCommit(setpointValue(for: gesture.location.x, width: width))
                    }
            )
        }
        .frame(height: 28)
    }

    private var normalizedValue: CGFloat {
        guard range.upperBound > range.lowerBound else { return 0 }
        let normalized = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGFloat(min(max(normalized, 0), 1))
    }

    private func setpointValue(for x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return range.lowerBound }
        let normalized = min(max(Double(x / width), 0), 1)
        let rawValue = range.lowerBound + normalized * (range.upperBound - range.lowerBound)
        let resolvedStep = max(step, 0.1)
        let snapped = ((rawValue - range.lowerBound) / resolvedStep).rounded()
        return range.lowerBound + snapped * resolvedStep
    }

    private var trackGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    AppColors.cloud.opacity(0.32),
                    AppColors.mist.opacity(0.25)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        return LinearGradient(
            colors: [
                AppColors.slate.opacity(0.34),
                AppColors.cloud.opacity(0.48)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var trackStroke: Color {
        colorScheme == .dark
            ? .white.opacity(0.10)
            : .black.opacity(0.16)
    }

    private var fillGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.32, green: 0.67, blue: 0.97),
                AppColors.aurora.opacity(0.95),
                AppColors.ember.opacity(0.95)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
