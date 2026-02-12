import SwiftUI

struct TemperatureView: View {
    @Environment(\.temperatureStoreFactory) private var temperatureStoreFactory
    @Environment(\.colorScheme) private var colorScheme

    let uniqueId: String

    var body: some View {
        WithStoreView(factory: { temperatureStoreFactory.make(uniqueId) }) { store in
            valueContent(descriptor: store.descriptor)
        }
    }

    @ViewBuilder
    private func valueContent(descriptor: TemperatureDescriptor?) -> some View {
        if let descriptor {
            let battery = BatteryPresentation(status: descriptor.batteryStatus)
            valueLabel(descriptor: descriptor)
                .padding(.bottom, battery == nil ? 0 : 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .overlay(alignment: .bottomTrailing) {
                    if let battery {
                        batteryPill(for: battery)
                            .padding(.trailing, 4)
                            .padding(.bottom, 2)
                    }
                }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Temperature")
            .accessibilityValue(accessibilityValue(for: descriptor))
        } else {
            Text("--")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .accessibilityLabel("Temperature unavailable")
        }
    }

    private func batteryPill(for battery: BatteryPresentation) -> some View {
        HStack(spacing: 4) {
            Image(systemName: battery.batterySymbolName)
            Image(systemName: battery.statusSymbolName)
        }
        .font(.system(.caption2, design: .rounded).weight(.bold))
        .foregroundStyle(batteryForegroundColor(for: battery))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(batteryPillBackgroundColor, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(batteryPillBorderColor, lineWidth: 0.8)
        }
    }

    private var batteryPillBackgroundColor: Color {
        colorScheme == .dark ? .white.opacity(0.17) : AppColors.slate.opacity(0.14)
    }

    private var batteryPillBorderColor: Color {
        colorScheme == .dark ? .white.opacity(0.14) : AppColors.slate.opacity(0.26)
    }

    private func batteryForegroundColor(for battery: BatteryPresentation) -> Color {
        if battery.isOk {
            return colorScheme == .dark ? AppColors.cloud : AppColors.slate
        }

        return colorScheme == .dark ? .orange : AppColors.ember
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
            parts.append(battery.accessibilityLabel)
        }

        return parts.joined(separator: ", ")
    }
}

private struct BatteryPresentation {
    let isOk: Bool
    let accessibilityLabel: String
    let batterySymbolName: String
    let statusSymbolName: String

    init?(status: BatteryStatusDescriptor?) {
        guard let status else { return nil }
        guard let isBatteryOk = Self.isBatteryOk(status: status) else { return nil }
        isOk = isBatteryOk
        accessibilityLabel = isBatteryOk ? "Battery OK" : "Battery low"
        batterySymbolName = isBatteryOk ? "battery.100" : "battery.25"
        statusSymbolName = isBatteryOk ? "checkmark" : "xmark"
    }

    private static func isBatteryOk(status: BatteryStatusDescriptor) -> Bool? {
        if status.batteryDefect == true {
            return false
        }

        if let level = status.normalizedBatteryLevel {
            return level > 20
        }

        if let batteryDefect = status.batteryDefect {
            return !batteryDefect
        }

        return nil
    }
}
