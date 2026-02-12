import SwiftUI

struct SmokeView: View {
    @Environment(\.smokeStoreFactory) private var smokeStoreFactory
    @Environment(\.colorScheme) private var colorScheme

    let uniqueId: String

    var body: some View {
        WithStoreView(factory: { smokeStoreFactory.make(uniqueId) }) { store in
            smokeContent(descriptor: store.descriptor)
        }
    }

    private func smokeContent(descriptor: SmokeDetectorDescriptor?) -> some View {
        let state = SmokeState(descriptor: descriptor)
        let battery = BatteryPresentation(descriptor: descriptor)

        return HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(state.tint.opacity(0.2))
                Circle()
                    .strokeBorder(state.tint.opacity(0.45), lineWidth: 1)
                Image(systemName: state.symbolName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(state.tint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(state.tint)

                Text(state.detail)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
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
        .accessibilityLabel("Smoke detector")
        .accessibilityValue(accessibilityValue(descriptor: descriptor))
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

    private func accessibilityValue(descriptor: SmokeDetectorDescriptor?) -> String {
        let state = SmokeState(descriptor: descriptor)
        var parts: [String] = [state.title, state.detail]
        if let battery = BatteryPresentation(descriptor: descriptor) {
            parts.append(battery.accessibilityLabel)
        }
        return parts.joined(separator: ", ")
    }
}

private struct SmokeState {
    let title: String
    let detail: String
    let symbolName: String
    let tint: Color

    init(descriptor: SmokeDetectorDescriptor?) {
        guard let descriptor else {
            title = "--"
            detail = "Status unavailable"
            symbolName = "questionmark.circle.fill"
            tint = .secondary
            return
        }

        if descriptor.smokeDetected {
            title = "NOT OK"
            detail = "Smoke alert"
            symbolName = "flame.fill"
            tint = .red
            return
        }

        if descriptor.hasBatteryIssue {
            title = "NOT OK"
            detail = "Battery issue"
            symbolName = "exclamationmark.triangle.fill"
            tint = .orange
            return
        }

        title = "OK"
        detail = "No smoke"
        symbolName = "checkmark.shield.fill"
        tint = .green
    }
}

private struct BatteryPresentation {
    let isOk: Bool
    let accessibilityLabel: String
    let batterySymbolName: String
    let statusSymbolName: String

    init?(descriptor: SmokeDetectorDescriptor?) {
        guard let descriptor else { return nil }
        guard let isBatteryOk = Self.isBatteryOk(descriptor: descriptor) else { return nil }
        isOk = isBatteryOk
        accessibilityLabel = isBatteryOk ? "Battery OK" : "Battery low"
        batterySymbolName = isBatteryOk ? "battery.100" : "battery.25"
        statusSymbolName = isBatteryOk ? "checkmark" : "xmark"
    }

    private static func isBatteryOk(descriptor: SmokeDetectorDescriptor) -> Bool? {
        if descriptor.batteryDefect == true {
            return false
        }

        if let level = descriptor.normalizedBatteryLevel {
            return level > 20
        }

        if let batteryDefect = descriptor.batteryDefect {
            return !batteryDefect
        }

        return nil
    }
}
