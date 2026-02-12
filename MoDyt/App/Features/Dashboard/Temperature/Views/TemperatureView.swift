import SwiftUI

struct TemperatureView: View {
    @Environment(\.temperatureStoreFactory) private var temperatureStoreFactory

    let uniqueId: String

    var body: some View {
        WithStoreView(factory: { temperatureStoreFactory.make(uniqueId) }) { store in
            valueContent(descriptor: store.descriptor)
        }
    }

    @ViewBuilder
    private func valueContent(descriptor: TemperatureDescriptor?) -> some View {
        if let descriptor {
            VStack(spacing: 10) {
                valueLabel(descriptor: descriptor)

                if let battery = BatteryPresentation(status: descriptor.batteryStatus) {
                    HStack(spacing: 6) {
                        Image(systemName: battery.symbolName)
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                        Text(battery.label)
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(battery.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.17), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Temperature")
            .accessibilityValue(accessibilityValue(for: descriptor))
        } else {
            Text("--")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel("Temperature unavailable")
        }
    }

    private func valueLabel(descriptor: TemperatureDescriptor) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(descriptor.value, format: .number.precision(.fractionLength(1)))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()

            if let unitSymbol = descriptor.unitSymbol {
                Text(unitSymbol)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func accessibilityValue(for descriptor: TemperatureDescriptor) -> String {
        let valueText = descriptor.value.formatted(.number.precision(.fractionLength(1)))
        var parts = [valueText]

        if let unitSymbol = descriptor.unitSymbol {
            parts.append(unitSymbol)
        }

        if let battery = BatteryPresentation(status: descriptor.batteryStatus) {
            parts.append(battery.label)
        }

        return parts.joined(separator: ", ")
    }
}

private struct BatteryPresentation {
    let label: String
    let symbolName: String
    let tint: Color

    init?(status: BatteryStatusDescriptor?) {
        guard let status else { return nil }

        if let level = status.normalizedBatteryLevel {
            let roundedLevel = Int(level.rounded())
            label = "Battery \(roundedLevel)%"
            symbolName = Self.symbolName(for: level)
            tint = roundedLevel <= 20 ? .orange : AppColors.cloud
            return
        }

        guard let hasBatteryIssue = status.batteryDefect else { return nil }
        label = hasBatteryIssue ? "Battery low" : "Battery OK"
        symbolName = hasBatteryIssue ? "battery.25" : "battery.100"
        tint = hasBatteryIssue ? .orange : AppColors.cloud
    }

    private static func symbolName(for level: Double) -> String {
        switch level {
        case 76...:
            return "battery.100"
        case 51...:
            return "battery.75"
        case 26...:
            return "battery.50"
        default:
            return "battery.25"
        }
    }
}
