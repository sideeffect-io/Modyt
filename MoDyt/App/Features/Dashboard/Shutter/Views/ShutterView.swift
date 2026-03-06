import SwiftUI

struct ShutterView: View {
    @Environment(\.shutterStoreDependencies) private var shutterStoreDependencies

    let deviceIds: [DeviceIdentifier]

    @State private var animatedCheckTarget: Int?
    @State private var lastAnimatedTarget: Int?
    @State private var shutterIconOpacity: Double = 1
    @State private var checkmarkOpacity: Double = 0
    @State private var checkAnimationTask: Task<Void, Never>?

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
                    isDimmed: store.isGaugeDimmed,
                    showsMovingOutline: store.isMovingInApp
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
            .onChange(of: store.movingTarget) { _, movingTarget in
                playCheckAnimation(for: movingTarget)
            }
            .onDisappear {
                checkAnimationTask?.cancel()
                checkAnimationTask = nil
                resetCheckAnimationState()
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
        let isMoving = movingTarget == preset.rawValue
        let isSelected = target == preset.rawValue || isMoving
        let displaysCheckmark = isMoving && animatedCheckTarget == preset.rawValue

        return Button {
            action()
        } label: {
            ZStack {
                ShutterPresetIcon(openPercentage: preset.rawValue)
                    .opacity(displaysCheckmark ? shutterIconOpacity : 1)
                    .padding(4)

                if displaysCheckmark {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(red: 0.21, green: 0.78, blue: 0.42))
                        .opacity(checkmarkOpacity)
                }
            }
            .opacity(isSelected ? 1 : 0.86)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .accessibilityLabel(preset.accessibilityLabel)
        .accessibilityHint("Set shutter target")
    }

    private func playCheckAnimation(for movingTarget: Int?) {
        guard let movingTarget else {
            checkAnimationTask?.cancel()
            checkAnimationTask = nil
            resetCheckAnimationState()
            return
        }

        guard lastAnimatedTarget != movingTarget else { return }

        checkAnimationTask?.cancel()
        checkAnimationTask = nil

        lastAnimatedTarget = movingTarget
        animatedCheckTarget = movingTarget
        shutterIconOpacity = 1
        checkmarkOpacity = 0

        withAnimation(.easeInOut(duration: 0.18)) {
            shutterIconOpacity = 0
            checkmarkOpacity = 1
        }

        checkAnimationTask = Task { @MainActor [movingTarget] in
            do {
                try await Task.sleep(for: .milliseconds(520))
            } catch {
                return
            }

            guard animatedCheckTarget == movingTarget else { return }

            withAnimation(.easeInOut(duration: 0.24)) {
                shutterIconOpacity = 1
                checkmarkOpacity = 0
            }

            do {
                try await Task.sleep(for: .milliseconds(220))
            } catch {
                return
            }

            guard animatedCheckTarget == movingTarget else { return }
            animatedCheckTarget = nil
        }
    }

    private func resetCheckAnimationState() {
        animatedCheckTarget = nil
        lastAnimatedTarget = nil
        shutterIconOpacity = 1
        checkmarkOpacity = 0
    }
}

private struct ShutterLinearGauge: View {
    let position: Int
    let isDimmed: Bool
    let showsMovingOutline: Bool

    @State private var movingDashPhase: CGFloat = 0

    private static let outlineLineWidth: CGFloat = 1.3
    private static let movingSegmentRatio: CGFloat = 0.16
    private static let fillGradient = LinearGradient(
        colors: [
            Color(red: 0.05, green: 0.50, blue: 0.78),
            Color(red: 0.27, green: 0.67, blue: 0.90),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    private static let movingOutlineGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.95),
            Color(red: 0.25, green: 0.80, blue: 0.58),
            Color.white.opacity(0.9),
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
            let perimeter = outlinePerimeter(for: proxy.size)
            let trackShape = Capsule(style: .continuous)

            ZStack(alignment: .leading) {
                trackShape
                    .fill(Color.primary.opacity(0.08))

                trackShape
                    .fill(Self.fillGradient)
                    .opacity(fillOpacity)
                    .frame(width: fillWidth)
                    .animation(.easeInOut(duration: 0.26), value: clampedPosition)
            }
            .clipShape(trackShape.inset(by: Self.outlineLineWidth / 2))
            .overlay {
                trackShape
                    .stroke(Color.primary.opacity(0.82), lineWidth: Self.outlineLineWidth)
            }
            .overlay {
                if showsMovingOutline, perimeter > 0 {
                    trackShape
                        .stroke(
                            Self.movingOutlineGradient,
                            style: movingOutlineStrokeStyle(for: perimeter)
                        )
                        .opacity(0.98)
                }
            }
            .onAppear {
                updateOutlineAnimation(isMoving: showsMovingOutline, perimeter: perimeter)
            }
            .onChange(of: showsMovingOutline) { _, isMoving in
                updateOutlineAnimation(isMoving: isMoving, perimeter: perimeter)
            }
            .onChange(of: perimeter) { _, newPerimeter in
                guard showsMovingOutline else { return }
                updateOutlineAnimation(isMoving: true, perimeter: newPerimeter)
            }
        }
    }

    private func movingOutlineStrokeStyle(for perimeter: CGFloat) -> StrokeStyle {
        let segmentLength = max(perimeter * Self.movingSegmentRatio, 14)
        let dashGap = max(perimeter * 2, segmentLength + 1)
        return StrokeStyle(
            lineWidth: Self.outlineLineWidth + 0.85,
            lineCap: .round,
            lineJoin: .round,
            dash: [segmentLength, dashGap],
            dashPhase: movingDashPhase
        )
    }

    private func outlinePerimeter(for size: CGSize) -> CGFloat {
        let width = max(size.width, 0)
        let height = max(size.height, 0)
        guard width > 0, height > 0 else { return 0 }
        let straightSection = max(width - height, 0)
        let radius = height / 2
        return (2 * straightSection) + (2 * .pi * radius)
    }

    private func updateOutlineAnimation(isMoving: Bool, perimeter: CGFloat) {
        if isMoving, perimeter > 0 {
            movingDashPhase = 0
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                movingDashPhase = -perimeter
            }
            return
        }
        movingDashPhase = 0
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
