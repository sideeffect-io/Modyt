import SwiftUI

struct HeatPumpView: View {
    @Environment(\.heatPumpStoreFactory) private var heatPumpStoreFactory

    let identifier: DeviceIdentifier
    @State private var pendingPulseOn = false
    @State private var pendingSpinOn = false

    var body: some View {
        WithStoreView(factory: { heatPumpStoreFactory.make(identifier) }) { store in
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

                    ZStack {
                        HStack(spacing: 0) {
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
                            .frame(maxWidth: .infinity, alignment: .leading)

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
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 12, height: 12)
                                .opacity(0)
                                .accessibilityHidden(true)

                            Text(store.setPoint, format: .number.precision(.fractionLength(1)))
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 12, height: 12)
                                .opacity(store.isSetPointBeingSet ? 1 : 0)
                                .rotationEffect(.degrees(pendingSpinOn ? 360 : 0))
                                .accessibilityHidden(true)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(store.isSetPointBeingSet ? AppColors.ember : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            Capsule()
                                .fill(
                                    AppColors.ember.opacity(
                                        store.isSetPointBeingSet
                                        ? (pendingPulseOn ? 0.22 : 0.10)
                                        : 0
                                    )
                                )
                                .scaleEffect(store.isSetPointBeingSet && pendingPulseOn ? 1.03 : 1)
                        }
                        .allowsHitTesting(false)
                        .onAppear {
                            updatePendingAnimation(isPending: store.isSetPointBeingSet)
                        }
                        .onChange(of: store.isSetPointBeingSet) { _, isPending in
                            updatePendingAnimation(isPending: isPending)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Heat pump target value")
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func updatePendingAnimation(isPending: Bool) {
        if isPending {
            pendingPulseOn = false
            pendingSpinOn = false

            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pendingPulseOn = true
            }

            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                pendingSpinOn = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                pendingPulseOn = false
                pendingSpinOn = false
            }
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

    private static let minimumTouchTarget: CGFloat = 44

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .bold, design: .rounded))
                .frame(width: size, height: size)
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
                .frame(
                    width: max(size, Self.minimumTouchTarget),
                    height: max(size, Self.minimumTouchTarget)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
