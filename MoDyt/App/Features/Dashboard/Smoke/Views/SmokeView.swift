import SwiftUI

struct SmokeView: View {
    @Environment(\.smokeStoreFactory) private var smokeStoreFactory

    let uniqueId: String

    var body: some View {
        WithStoreView(factory: { smokeStoreFactory.make(uniqueId) }) { store in
            smokeContent(descriptor: store.descriptor)
        }
    }

    private func smokeContent(descriptor: SmokeDetectorDescriptor?) -> some View {
        let state = SmokeState(descriptor: descriptor)

        return VStack(spacing: 12) {
            HStack(spacing: 8) {
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

            if let battery = BatteryPresentation(descriptor: descriptor) {
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
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Smoke detector")
        .accessibilityValue(accessibilityValue(descriptor: descriptor))
    }

    private func accessibilityValue(descriptor: SmokeDetectorDescriptor?) -> String {
        let state = SmokeState(descriptor: descriptor)
        var parts: [String] = [state.title, state.detail]
        if let battery = BatteryPresentation(descriptor: descriptor) {
            parts.append(battery.label)
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
    let label: String
    let symbolName: String
    let tint: Color

    init?(descriptor: SmokeDetectorDescriptor?) {
        guard let descriptor else { return nil }

        if let level = descriptor.normalizedBatteryLevel {
            let roundedLevel = Int(level.rounded())
            label = "Battery \(roundedLevel)%"
            symbolName = Self.symbolName(for: level)
            tint = roundedLevel <= 20 ? .orange : AppColors.cloud
            return
        }

        guard let hasBatteryIssue = descriptor.batteryDefect else { return nil }
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
