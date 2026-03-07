import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ShutterView: View {
    @Environment(\.shutterStoreDependencies) private var shutterStoreDependencies
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let deviceIds: [DeviceIdentifier]

    @State private var acknowledgedPreset: Int?
    @State private var acknowledgementStrength: CGFloat = 0
    @State private var acknowledgementTask: Task<Void, Never>?

    private static let targetAccent = Color(red: 0.08, green: 0.51, blue: 0.80)
    private static let quietSelectedFillOpacity: CGFloat = 0.22
    private static let quietSelectedStrokeOpacity: CGFloat = 0.46
    private static let acknowledgementFillBoost: CGFloat = 0.12
    private static let acknowledgementStrokeBoost: CGFloat = 0.18
    private static let targetTileCornerRadius: CGFloat = 8
    private static let targetTileHorizontalInset: CGFloat = 2
    private static let targetTileVerticalInset: CGFloat = 1

    private var normalizedDeviceIds: [DeviceIdentifier] {
        deviceIds.uniquePreservingOrder()
    }

    private var storeIdentity: String {
        normalizedDeviceIds.map(\.storageKey).joined(separator: "|")
    }

    var body: some View {
        WithStoreView(
            store: ShutterStore(
                dependencies: shutterStoreDependencies,
                deviceIds: normalizedDeviceIds
            ),
        ) { store in
            VStack(spacing: 10) {
                ShutterLinearGauge(
                    position: store.gaugePosition,
                    isDimmed: store.isGaugeDimmed
                )
                .frame(height: 24)
                .accessibilityLabel("Current shutter position")
                .accessibilityValue("\(store.gaugePosition) percent")

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(ShutterPreset.allCases) { preset in
                        presetButton(
                            preset: preset,
                            target: store.target,
                            movingTarget: store.movingTarget
                        ) {
                            store.send(.targetWasSetInApp(target: preset.rawValue))
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .glassCard(cornerRadius: 18, interactive: true, tone: .inset)
            .onDisappear {
                resetAcknowledgement()
            }
        }
        .id(storeIdentity)
    }

    private func presetButton(
        preset: ShutterPreset,
        target: Int?,
        movingTarget: Int?,
        action: @escaping () -> Void
    ) -> some View {
        let isSelected = target == preset.rawValue || movingTarget == preset.rawValue
        let isAcknowledging = acknowledgedPreset == preset.rawValue
        let fillOpacity = (isSelected ? Self.quietSelectedFillOpacity : 0)
            + (isAcknowledging ? Self.acknowledgementFillBoost * acknowledgementStrength : 0)
        let strokeOpacity = (isSelected ? Self.quietSelectedStrokeOpacity : 0)
            + (isAcknowledging ? Self.acknowledgementStrokeBoost * acknowledgementStrength : 0)
        let highlightScale = isAcknowledging && !accessibilityReduceMotion
            ? 1 + (0.015 * acknowledgementStrength)
            : 1

        return Button {
            acknowledgeTap(for: preset)
            action()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Self.targetTileCornerRadius, style: .continuous)
                    .fill(Self.targetAccent.opacity(Double(fillOpacity)))
                    .padding(.horizontal, Self.targetTileHorizontalInset)
                    .padding(.vertical, Self.targetTileVerticalInset)

                RoundedRectangle(cornerRadius: Self.targetTileCornerRadius, style: .continuous)
                    .stroke(
                        Self.targetAccent.opacity(Double(strokeOpacity)),
                        lineWidth: isSelected || isAcknowledging ? 1.15 : 0
                    )
                    .padding(.horizontal, Self.targetTileHorizontalInset)
                    .padding(.vertical, Self.targetTileVerticalInset)

                ShutterPresetIcon(openPercentage: preset.rawValue)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 5)
            }
            .shadow(
                color: Self.targetAccent.opacity(Double((isSelected ? 0.10 : 0) + (0.16 * acknowledgementStrength))),
                radius: isSelected || isAcknowledging ? 5 : 0,
                x: 0,
                y: 2
            )
            .scaleEffect(highlightScale)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .opacity(isSelected ? 1 : 0.88)
        }
        .buttonStyle(ShutterPresetButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel(preset.accessibilityLabel)
        .accessibilityHint("Set shutter target")
        .accessibilityValue(isSelected ? "Selected target" : "Available target")
    }

    private func acknowledgeTap(for preset: ShutterPreset) {
#if os(iOS)
        let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
        feedbackGenerator.impactOccurred(intensity: 0.7)
#endif

        acknowledgementTask?.cancel()
        acknowledgedPreset = preset.rawValue

        var instantTransaction = Transaction(animation: nil)
        instantTransaction.disablesAnimations = true
        withTransaction(instantTransaction) {
            acknowledgementStrength = accessibilityReduceMotion ? 0 : 1
        }

        if !accessibilityReduceMotion {
            withAnimation(.easeOut(duration: 0.18)) {
                acknowledgementStrength = 0
            }
        }

        let acknowledgedValue = preset.rawValue
        acknowledgementTask = Task { @MainActor [acknowledgedValue] in
            if !accessibilityReduceMotion {
                do {
                    try await Task.sleep(for: .milliseconds(220))
                } catch {
                    return
                }
            }

            guard acknowledgedPreset == acknowledgedValue else { return }
            acknowledgedPreset = nil
            acknowledgementTask = nil
        }
    }

    private func resetAcknowledgement() {
        acknowledgementTask?.cancel()
        acknowledgementTask = nil
        acknowledgedPreset = nil
        acknowledgementStrength = 0
    }
}

private struct ShutterPresetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct ShutterLinearGauge: View {
    let position: Int
    let isDimmed: Bool

    private static let outlineLineWidth: CGFloat = 1.3
    private static let fillGradient = LinearGradient(
        colors: [
            Color(red: 0.05, green: 0.50, blue: 0.78),
            Color(red: 0.27, green: 0.67, blue: 0.90),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    private var clampedPosition: Int {
        min(max(position, 0), 100)
    }

    private var fillOpacity: Double {
        isDimmed ? 0.6 : 1
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 0)
            let progress = CGFloat(clampedPosition) / 100
            let fillWidth = width * progress
            let trackShape = Capsule(style: .continuous)

            ZStack(alignment: .leading) {
                trackShape
                    .fill(Color.primary.opacity(0.08))

                trackShape
                    .fill(Self.fillGradient)
                    .opacity(fillOpacity)
                    .frame(width: fillWidth)
            }
            .clipShape(trackShape.inset(by: Self.outlineLineWidth / 2))
            .overlay {
                trackShape
                    .stroke(Color.primary.opacity(0.82), lineWidth: Self.outlineLineWidth)
            }
        }
    }
}

private struct ShutterPresetIcon: View {
    let openPercentage: Int

    private var closedRatio: CGFloat {
        let clampedOpen = CGFloat(min(max(openPercentage, 0), 100))
        return 1 - (clampedOpen / 100)
    }

    var body: some View {
        GeometryReader { proxy in
            let innerInset: CGFloat = 3
            let innerWidth = max(proxy.size.width - (innerInset * 2), 0)
            let innerHeight = max(proxy.size.height - (innerInset * 2), 0)
            let curtainHeight = innerHeight * closedRatio

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(0.8), lineWidth: 1.25)
                }
                .overlay(alignment: .top) {
                    if curtainHeight > 0.5 {
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.primary.opacity(0.08))

                            let linePitch: CGFloat = 4
                            let lineCount = max(Int((curtainHeight / linePitch).rounded(.up)), 1)

                            VStack(spacing: max(linePitch - 1.2, 1)) {
                                ForEach(0..<lineCount, id: \.self) { _ in
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.9))
                                        .frame(height: 1.2)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 1)
                        }
                        .frame(width: innerWidth, height: curtainHeight, alignment: .top)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(.top, innerInset)
                    }
                }
        }
    }
}
