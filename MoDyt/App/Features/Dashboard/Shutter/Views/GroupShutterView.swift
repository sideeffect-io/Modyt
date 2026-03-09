import SwiftUI
#if os(iOS)
import UIKit
#endif

struct GroupShutterView: View {
    @Environment(\.groupShutterStoreDependencies) private var groupShutterStoreDependencies
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let deviceIds: [DeviceIdentifier]

    @State private var acknowledgedPreset: Int?
    @State private var acknowledgementStrength: CGFloat = 0
    @State private var acknowledgementTask: Task<Void, Never>?

    private static let targetAccent = Color(red: 0.08, green: 0.51, blue: 0.80)
    private static let acknowledgementBloomOpacity: CGFloat = 0.34
    private static let acknowledgementBloomScale: CGFloat = 0.14
    private static let acknowledgementBloomBlur: CGFloat = 5
    private static let targetTileCornerRadius: CGFloat = 8
    private static let targetTileInset: CGFloat = 1

    private var normalizedDeviceIds: [DeviceIdentifier] {
        deviceIds.uniquePreservingOrder()
    }

    private var storeIdentity: String {
        normalizedDeviceIds.map(\.storageKey).joined(separator: "|")
    }

    private var badgeTitle: String {
        let count = normalizedDeviceIds.count
        if count == 1 {
            return "Group · 1 shutter"
        }
        return "Group · \(count) shutters"
    }

    private var acknowledgementTitle: String {
        let count = normalizedDeviceIds.count
        if count == 1 {
            return "Command sent"
        }
        return "Sent to \(count) shutters"
    }

    private var isShowingAcknowledgement: Bool {
        acknowledgedPreset != nil
    }

    var body: some View {
        WithStoreView(
            store: GroupShutterStore(
                dependencies: groupShutterStoreDependencies,
                deviceIds: normalizedDeviceIds
            ),
        ) { store in
            VStack(alignment: .leading, spacing: 12) {
                groupBadge

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(ShutterPreset.allCases) { preset in
                        presetButton(preset: preset) {
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

    private var groupBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: isShowingAcknowledgement ? "checkmark.seal.fill" : "square.stack.3d.up.fill")
                .contentTransition(.symbolEffect(.replace))

            Text(isShowingAcknowledgement ? acknowledgementTitle : badgeTitle)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .font(.system(.caption2, design: .rounded).weight(.semibold))
        .foregroundStyle(isShowingAcknowledgement ? Color.green : .secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(
            Capsule(style: .continuous)
                .fill(
                    isShowingAcknowledgement
                    ? Color.green.opacity(0.16)
                    : Color.primary.opacity(0.08)
                )
        )
        .overlay {
            Capsule(style: .continuous)
                .stroke(
                    isShowingAcknowledgement
                    ? Color.green.opacity(0.28)
                    : Color.primary.opacity(0.10),
                    lineWidth: 1
                )
        }
        .animation(.easeInOut(duration: 0.22), value: isShowingAcknowledgement)
        .accessibilityLabel("Shutter group control")
        .accessibilityValue(
            isShowingAcknowledgement
            ? acknowledgementTitle
            : "\(normalizedDeviceIds.count) shutters"
        )
    }

    private func presetButton(
        preset: ShutterPreset,
        action: @escaping () -> Void
    ) -> some View {
        let isAcknowledging = acknowledgedPreset == preset.rawValue
        let bloomOpacity = isAcknowledging ? Self.acknowledgementBloomOpacity * acknowledgementStrength : 0
        let bloomScale = accessibilityReduceMotion
            ? 1
            : 1 + (Self.acknowledgementBloomScale * acknowledgementStrength)
        let bloomBlur = accessibilityReduceMotion
            ? 0
            : Self.acknowledgementBloomBlur * acknowledgementStrength

        return Button {
            acknowledgeTap(for: preset)
            action()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Self.targetTileCornerRadius, style: .continuous)
                    .stroke(Self.targetAccent.opacity(Double(bloomOpacity)), lineWidth: 2.2)
                    .padding(Self.targetTileInset)
                    .scaleEffect(bloomScale)
                    .blur(radius: bloomBlur)

                RoundedRectangle(cornerRadius: Self.targetTileCornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.02))
                    .padding(Self.targetTileInset)

                RoundedRectangle(cornerRadius: Self.targetTileCornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    .padding(Self.targetTileInset)

                ShutterPresetIcon(openPercentage: preset.rawValue)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 5)
            }
            .shadow(
                color: Self.targetAccent.opacity(Double(0.12 * acknowledgementStrength)),
                radius: isAcknowledging ? 6 : 0,
                x: 0,
                y: 2
            )
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .opacity(0.88)
        }
        .buttonStyle(ShutterPresetButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel(preset.accessibilityLabel)
        .accessibilityHint("Send shutter target to the full group")
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
            withAnimation(.easeOut(duration: 0.42)) {
                acknowledgementStrength = 0
            }
        }

        let acknowledgedValue = preset.rawValue
        acknowledgementTask = Task { @MainActor [acknowledgedValue] in
            if !accessibilityReduceMotion {
                do {
                    try await Task.sleep(for: .milliseconds(900))
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
