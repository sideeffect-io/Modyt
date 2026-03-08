import SwiftUI
#if os(iOS)
import UIKit
#endif

private func performWithoutAnimation(_ updates: () -> Void) {
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction) {
        updates()
    }
}

struct ShutterView: View {
    @Environment(\.shutterStoreDependencies) private var shutterStoreDependencies
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let deviceIds: [DeviceIdentifier]

    @State private var acknowledgedPreset: Int?
    @State private var acknowledgementStrength: CGFloat = 0
    @State private var acknowledgementTask: Task<Void, Never>?

    private static let targetAccent = Color(red: 0.08, green: 0.51, blue: 0.80)
    private static let quietSelectedFillOpacity: CGFloat = 0.30
    private static let quietSelectedStrokeOpacity: CGFloat = 0.62
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

    var body: some View {
        WithStoreView(
            store: ShutterStore(
                dependencies: shutterStoreDependencies,
                deviceIds: normalizedDeviceIds
            ),
        ) { store in
            VStack(spacing: 10) {
                ShutterLinearGauge(
                    gaugePosition: store.gaugePosition,
                    movingTarget: store.movingTarget,
                    isMoving: store.isMoving,
                    isDimmed: store.isGaugeDimmed
                )
                .frame(height: 24)
                .accessibilityLabel("Current shutter position")
                .accessibilityValue("\(store.gaugePosition) percent")

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(ShutterPreset.allCases) { preset in
                        presetButton(
                            preset: preset,
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
        movingTarget: Int?,
        action: @escaping () -> Void
    ) -> some View {
        let isSelected = movingTarget == preset.rawValue
        let isAcknowledging = acknowledgedPreset == preset.rawValue
        let fillOpacity = isSelected ? Self.quietSelectedFillOpacity : 0
        let strokeOpacity = isSelected ? Self.quietSelectedStrokeOpacity : 0
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
                    .fill(Self.targetAccent.opacity(Double(fillOpacity)))
                    .padding(Self.targetTileInset)

                RoundedRectangle(cornerRadius: Self.targetTileCornerRadius, style: .continuous)
                    .stroke(
                        Self.targetAccent.opacity(Double(strokeOpacity)),
                        lineWidth: isSelected || isAcknowledging ? 1.15 : 0
                    )
                    .padding(Self.targetTileInset)

                ShutterPresetIcon(openPercentage: preset.rawValue)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 5)
            }
            .shadow(
                color: Self.targetAccent.opacity(Double((isSelected ? 0.18 : 0) + (0.12 * acknowledgementStrength))),
                radius: isSelected || isAcknowledging ? 6 : 0,
                x: 0,
                y: 2
            )
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
            withAnimation(.easeOut(duration: 0.42)) {
                acknowledgementStrength = 0
            }
        }

        let acknowledgedValue = preset.rawValue
        acknowledgementTask = Task { @MainActor [acknowledgedValue] in
            if !accessibilityReduceMotion {
                do {
                    try await Task.sleep(for: .milliseconds(520))
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
    @Environment(\.colorScheme) private var colorScheme

    let gaugePosition: Int
    let movingTarget: Int?
    let isMoving: Bool
    let isDimmed: Bool

    @State private var displayedGaugePosition: Int
    @State private var retainedDestinationGaugePosition: Int?
    @State private var fadingDestinationMarkerOpacity: CGFloat
    @State private var isSuppressingLiveGaugeSync = false
    @State private var completionAnimationID = 0

    private static let outlineLineWidth: CGFloat = 1.3
    private static let progressFillColor = Color(red: 53 / 255, green: 104 / 255, blue: 154 / 255)
        .opacity(0.4)
    private static let positionMarkerColor = Color(red: 53 / 255, green: 104 / 255, blue: 154 / 255)
    private static let positionMarkerWidth: CGFloat = 12
    private static let destinationMarkerWidth: CGFloat = 7
    private static let destinationMarkerBaseOpacity: CGFloat = 0.7
    private static let completionAnimation = Animation.easeInOut(duration: 0.82)

    init(
        gaugePosition: Int,
        movingTarget: Int?,
        isMoving: Bool,
        isDimmed: Bool
    ) {
        self.gaugePosition = gaugePosition
        self.movingTarget = movingTarget
        self.isMoving = isMoving
        self.isDimmed = isDimmed

        let initialGaugePosition = Self.clampGaugePosition(gaugePosition)
        let initialDestinationGaugePosition = isMoving
            ? movingTarget.map(ShutterPositionMapper.gaugePosition(from:)).map(Self.clampGaugePosition)
            : nil

        _displayedGaugePosition = State(initialValue: initialGaugePosition)
        _retainedDestinationGaugePosition = State(initialValue: initialDestinationGaugePosition)
        _fadingDestinationMarkerOpacity = State(initialValue: 0)
    }

    private var clampedPosition: Int {
        Self.clampGaugePosition(gaugePosition)
    }

    private var renderedGaugePosition: Int {
        return displayedGaugePosition
    }

    private var destinationMarkerColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var destinationMarkerStrokeColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.22)
    }

    private var renderedDestinationGaugePosition: Int? {
        retainedDestinationGaugePosition.map(Self.clampGaugePosition)
    }

    private static func clampGaugePosition(_ value: Int) -> Int {
        min(max(value, 0), ShutterPositionMapper.maximumGaugePosition)
    }

    private func destinationGaugePosition(for target: Int?) -> Int? {
        target.map(ShutterPositionMapper.gaugePosition(from:))
            .map(Self.clampGaugePosition)
    }

    private func completionGaugePosition(for destinationGaugePosition: Int?) -> Int {
        destinationGaugePosition ?? clampedPosition
    }

    private func syncInitialPresentationState() {
        performWithoutAnimation {
            displayedGaugePosition = clampedPosition
            retainedDestinationGaugePosition = isMoving ? destinationGaugePosition(for: movingTarget) : nil
            fadingDestinationMarkerOpacity = 0
            isSuppressingLiveGaugeSync = isMoving
            completionAnimationID = 0
        }
    }

    private func handleMovingChange(_ moving: Bool) {
        if moving {
            performWithoutAnimation {
                displayedGaugePosition = clampedPosition
                retainedDestinationGaugePosition = destinationGaugePosition(for: movingTarget)
                fadingDestinationMarkerOpacity = 0
                isSuppressingLiveGaugeSync = true
                completionAnimationID += 1
            }
            return
        }

        let destinationGaugePositionForCompletion = retainedDestinationGaugePosition
        let completionGaugePosition = completionGaugePosition(for: destinationGaugePositionForCompletion)
        let completionRunID = self.completionAnimationID + 1
        performWithoutAnimation {
            fadingDestinationMarkerOpacity = destinationGaugePositionForCompletion == nil ? 0 : Self.destinationMarkerBaseOpacity
            isSuppressingLiveGaugeSync = true
            self.completionAnimationID = completionRunID
        }

        withAnimation(
            Self.completionAnimation,
            completionCriteria: .logicallyComplete
        ) {
            displayedGaugePosition = completionGaugePosition
            fadingDestinationMarkerOpacity = 0
        } completion: {
            guard self.completionAnimationID == completionRunID else { return }

            performWithoutAnimation {
                retainedDestinationGaugePosition = nil
                fadingDestinationMarkerOpacity = 0
                isSuppressingLiveGaugeSync = false
            }
        }
    }

    private func handleMovingTargetChange(_ target: Int?) {
        guard isMoving else { return }
        performWithoutAnimation {
            retainedDestinationGaugePosition = destinationGaugePosition(for: target)
            fadingDestinationMarkerOpacity = 0
        }
    }

    private func handleGaugePositionChange(_ position: Int) {
        let clampedPosition = Self.clampGaugePosition(position)

        guard !isMoving else { return }
        guard !isSuppressingLiveGaugeSync else { return }

        performWithoutAnimation {
            displayedGaugePosition = clampedPosition
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 0)
            let maximumGaugePosition = CGFloat(ShutterPositionMapper.maximumGaugePosition)
            let progress = CGFloat(renderedGaugePosition) / maximumGaugePosition
            let fillWidth = width * progress
            let displayedFillWidth = fillWidth > 0 ? max(fillWidth, Self.positionMarkerWidth) : 0
            let trackShape = Capsule(style: .continuous)
            let clippedTrackShape = trackShape.inset(by: Self.outlineLineWidth / 2)
            let markerOffset = min(
                max(displayedFillWidth - Self.positionMarkerWidth, 0),
                max(width - Self.positionMarkerWidth, 0)
            )
            let destinationMarkerOffset = renderedDestinationGaugePosition.map { destinationGaugePosition in
                let destinationProgress = CGFloat(destinationGaugePosition) / maximumGaugePosition
                let destinationFillWidth = width * destinationProgress
                let displayedDestinationFillWidth = destinationFillWidth > 0
                    ? max(destinationFillWidth, Self.destinationMarkerWidth)
                    : 0
                return min(
                    max(displayedDestinationFillWidth - Self.destinationMarkerWidth, 0),
                    max(width - Self.destinationMarkerWidth, 0)
                )
            }

            ZStack(alignment: .leading) {
                trackShape
                    .fill(Color.primary.opacity(isDimmed ? 0.08 : 0.1))

                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Self.progressFillColor)
                        .frame(width: displayedFillWidth)

                    Rectangle()
                        .fill(Self.positionMarkerColor)
                        .frame(width: Self.positionMarkerWidth)
                        .shadow(color: Self.positionMarkerColor.opacity(0.28), radius: 2, x: 0, y: 0)
                        .offset(x: markerOffset)

                    if let destinationMarkerOffset {
                        ShutterDestinationMarkerView(
                            color: destinationMarkerColor,
                            strokeColor: destinationMarkerStrokeColor,
                            width: Self.destinationMarkerWidth,
                            isPulsing: isMoving,
                            pulseKey: retainedDestinationGaugePosition,
                            restingOpacity: Self.destinationMarkerBaseOpacity,
                            fadeOpacity: fadingDestinationMarkerOpacity
                        )
                            .offset(x: destinationMarkerOffset)
                            .zIndex(1)
                    }
                }
            }
            .clipShape(clippedTrackShape)
            .overlay {
                trackShape
                    .stroke(Color.primary.opacity(0.82), lineWidth: Self.outlineLineWidth)
            }
        }
        .onAppear(perform: syncInitialPresentationState)
        .onChange(of: isMoving) { _, moving in
            handleMovingChange(moving)
        }
        .onChange(of: movingTarget) { _, target in
            handleMovingTargetChange(target)
        }
        .onChange(of: gaugePosition) { _, position in
            handleGaugePositionChange(position)
        }
    }
}

private struct ShutterDestinationMarkerView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let color: Color
    let strokeColor: Color
    let width: CGFloat
    let isPulsing: Bool
    let pulseKey: Int?
    let restingOpacity: CGFloat
    let fadeOpacity: CGFloat

    @State private var pulseAtMinimumOpacity = false

    private static let minimumOpacity: CGFloat = 0.02
    private static let pulseAnimation = Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)
    private static let maximumGlowOpacity: CGFloat = 0.92
    private static let minimumGlowOpacity: CGFloat = 0.12
    private static let maximumGlowRadius: CGFloat = 9
    private static let minimumGlowRadius: CGFloat = 1.5

    private var pulseAnimationToken: String {
        "\(isPulsing)-\(pulseKey.map(String.init) ?? "nil")"
    }

    private var renderedOpacity: CGFloat {
        if isPulsing {
            if accessibilityReduceMotion {
                return restingOpacity
            }

            return pulseAtMinimumOpacity ? Self.minimumOpacity : restingOpacity
        }

        return fadeOpacity
    }

    private var renderedGlowOpacity: CGFloat {
        if isPulsing {
            if accessibilityReduceMotion {
                return 0
            }

            return pulseAtMinimumOpacity ? Self.minimumGlowOpacity : Self.maximumGlowOpacity
        }

        guard restingOpacity > 0 else { return 0 }
        return Self.maximumGlowOpacity * (fadeOpacity / restingOpacity)
    }

    private var renderedGlowRadius: CGFloat {
        if isPulsing {
            if accessibilityReduceMotion {
                return 0
            }

            return pulseAtMinimumOpacity ? Self.minimumGlowRadius : Self.maximumGlowRadius
        }

        guard restingOpacity > 0 else { return 0 }
        return Self.maximumGlowRadius * (fadeOpacity / restingOpacity)
    }

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: width)
            .overlay {
                Rectangle()
                    .stroke(strokeColor, lineWidth: 0.6)
            }
            .opacity(Double(renderedOpacity))
            .shadow(
                color: color.opacity(Double(renderedGlowOpacity)),
                radius: renderedGlowRadius,
                x: 0,
                y: 0
            )
            .task(id: pulseAnimationToken) {
                await restartPulseIfNeeded()
            }
    }

    @MainActor
    private func restartPulseIfNeeded() async {
        guard isPulsing else {
            performWithoutAnimation {
                pulseAtMinimumOpacity = false
            }
            return
        }

        guard !accessibilityReduceMotion else {
            performWithoutAnimation {
                pulseAtMinimumOpacity = false
            }
            return
        }

        performWithoutAnimation {
            pulseAtMinimumOpacity = false
        }

        await Task.yield()

        guard !Task.isCancelled else { return }

        withAnimation(Self.pulseAnimation) {
            pulseAtMinimumOpacity = true
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
