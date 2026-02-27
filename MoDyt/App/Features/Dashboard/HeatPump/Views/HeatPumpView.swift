import SwiftUI

struct HeatPumpView: View {
    @Environment(\.heatPumpStoreFactory) private var heatPumpStoreFactory

    let uniqueId: String

    var body: some View {
        WithStoreView(factory: { heatPumpStoreFactory.make(uniqueId) }) { store in
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(store.temperature, format: .number.precision(.fractionLength(1)))
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .monospacedDigit()

                        Text(store.unitSymbol)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel("Current heat pump value")

                    HStack(spacing: 12) {
                        SetPointButton(
                            systemImage: "minus",
                            tint: Color(red: 0.24, green: 0.56, blue: 0.98),
                            size: 30,
                            iconSize: 14,
                            accessibilityLabel: "Decrease target value",
                            action: {
                                store.send(.newSetPointWasReceived(store.setPoint - 0.5))
                            }
                        )

                        Text(store.setPoint, format: .number.precision(.fractionLength(1)))
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()

                        SetPointButton(
                            systemImage: "plus",
                            tint: Color(red: 0.95, green: 0.34, blue: 0.32),
                            size: 30,
                            iconSize: 14,
                            accessibilityLabel: "Increase target value",
                            action: {
                                store.send(.newSetPointWasReceived(store.setPoint + 0.5))
                            }
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Heat pump target value")
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct SetPointButton: View {
    let systemImage: String
    let tint: Color
    let size: CGFloat
    let iconSize: CGFloat
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .bold, design: .rounded))
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint.opacity(0.96))
        .background {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.26), tint.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    Circle()
                        .strokeBorder(tint.opacity(0.52), lineWidth: 0.9)
                }
        }
        .shadow(color: tint.opacity(0.24), radius: 5, x: 0, y: 2)
        .accessibilityLabel(accessibilityLabel)
    }
}
