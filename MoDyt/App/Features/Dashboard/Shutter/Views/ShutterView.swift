import SwiftUI

struct ShutterView: View {
    @Environment(\.shutterStoreFactory) private var shutterStoreFactory

    let deviceIds: [DeviceIdentifier]

    var body: some View {
        WithStoreView(factory: { shutterStoreFactory.make(deviceIds) }) { store in
            VStack(spacing: 10) {
                ShutterLinearGauge(position: store.gaugePosition)
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
        }
        .id(deviceIds.hashValue)
    }

    private func presetButton(
        preset: ShutterPreset,
        target: Int?,
        movingTarget: Int?,
        action: @escaping () -> Void
    ) -> some View {
        let isMoving = movingTarget == preset.rawValue
        let isSelected = target == preset.rawValue || isMoving

        return Button {
            action()
        } label: {
            ZStack {
                if isMoving {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.primary)
                        .scaleEffect(0.9)
                } else {
                    ShutterPresetIcon(openPercentage: preset.rawValue)
                        .opacity(isSelected ? 1 : 0.86)
                        .padding(4)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .accessibilityLabel(preset.accessibilityLabel)
        .accessibilityHint("Set shutter target")
    }
}

private struct ShutterLinearGauge: View {
    let position: Int

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
                    .frame(width: fillWidth)
                    .animation(.easeInOut(duration: 0.22), value: clampedPosition)
            }
            .clipShape(trackShape.inset(by: Self.outlineLineWidth / 2))
            .overlay(
                trackShape
                    .stroke(Color.primary.opacity(0.7), lineWidth: Self.outlineLineWidth)
            )
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
