import SwiftUI

struct SingleLightView: View {
    @Environment(\.singleLightStoreFactory) private var singleLightStoreFactory
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let deviceId: DeviceIdentifier

    @State private var draftNormalizedLevel: Double?

    var body: some View {
        WithStoreView(
            store: singleLightStoreFactory.make(deviceId: deviceId)
        ) { store in
            GeometryReader { proxy in
                let availableWidth = max(
                    proxy.size.width - (Self.controlContainerHorizontalPadding * 2),
                    0
                )
                let usesVerticalLayout = dynamicTypeSize.isAccessibilitySize
                    || availableWidth < Self.minimumHorizontalLayoutWidth
                let horizontalGap = max(
                    (availableWidth - Self.gaugeDiameter - Self.colorControlWidth) / 3,
                    Self.minimumHorizontalGap
                )

                controlContent(
                    store: store,
                    usesVerticalLayout: usesVerticalLayout,
                    horizontalGap: horizontalGap
                )
                .padding(.horizontal, Self.controlContainerHorizontalPadding)
                .padding(.vertical, Self.controlContainerVerticalPadding)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
                .glassCard(
                    cornerRadius: Self.controlContainerCornerRadius,
                    interactive: true,
                    tone: .controlInset
                )
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement(children: .contain)
            .onDisappear {
                draftNormalizedLevel = nil
            }
        }
        .id(deviceId.storageKey)
    }

    @ViewBuilder
    private func gaugeAndPowerControl(store: SingleLightStore) -> some View {
        ZStack {
            LightGaugeControl(
                colorScheme: colorScheme,
                normalizedValue: draftNormalizedLevel ?? store.displayedNormalizedLevel,
                isOn: store.displayedIsOn,
                isEnabled: store.isInteractionEnabled,
                onValueChanged: { draftNormalizedLevel = $0 },
                onEditingEnded: { normalizedValue in
                    draftNormalizedLevel = nil
                    store.send(.levelWasCommitted(normalizedValue))
                }
            )

            LightPowerButton(
                isOn: store.displayedIsOn,
                isEnabled: store.isInteractionEnabled
            ) {
                store.send(.powerWasToggled)
            }
        }
    }

    private static let gaugeDiameter: CGFloat = 86
    private static let colorControlWidth: CGFloat = 60
    private static let colorControlHeight: CGFloat = 100
    private static let expandedColorControlHeight: CGFloat = 72
    private static let minimumHorizontalGap: CGFloat = 6
    private static let minimumHorizontalLayoutWidth: CGFloat =
        gaugeDiameter + colorControlWidth + (minimumHorizontalGap * 3)
    private static let verticalSpacing: CGFloat = 12
    private static let verticalHorizontalPadding: CGFloat = 8
    private static let controlContainerHorizontalPadding: CGFloat = 10
    private static let controlContainerVerticalPadding: CGFloat = 10
    private static let controlContainerCornerRadius: CGFloat = 18

    @ViewBuilder
    private func controlContent(
        store: SingleLightStore,
        usesVerticalLayout: Bool,
        horizontalGap: CGFloat
    ) -> some View {
        if usesVerticalLayout {
            VStack(spacing: Self.verticalSpacing) {
                gaugeAndPowerControl(store: store)
                    .frame(width: Self.gaugeDiameter, height: Self.gaugeDiameter)

                LightColorPresetPicker(
                    selectedPreset: store.selectedPreset,
                    isEnabled: store.isColorInteractionEnabled,
                    style: .expanded,
                    onPresetSelected: { store.send(.presetWasSelected($0)) }
                )
                .frame(maxWidth: .infinity)
                .frame(height: Self.expandedColorControlHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, Self.verticalHorizontalPadding)
        } else {
            HStack(alignment: .center, spacing: horizontalGap) {
                gaugeAndPowerControl(store: store)
                    .frame(width: Self.gaugeDiameter, height: Self.gaugeDiameter)

                LightColorPresetPicker(
                    selectedPreset: store.selectedPreset,
                    isEnabled: store.isColorInteractionEnabled,
                    style: .compact,
                    onPresetSelected: { store.send(.presetWasSelected($0)) }
                )
                .frame(width: Self.colorControlWidth, height: Self.colorControlHeight)
            }
            .padding(.horizontal, horizontalGap)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct LightGaugeControl: View {
    let colorScheme: ColorScheme
    let normalizedValue: Double
    let isOn: Bool
    let isEnabled: Bool
    let onValueChanged: (Double) -> Void
    let onEditingEnded: (Double) -> Void

    var body: some View {
        let clampedNormalizedValue = min(max(normalizedValue, 0), 1)
        let progress = CGFloat(clampedNormalizedValue)
        let angle = Self.startAngle + (Self.sweepAngle * clampedNormalizedValue)
        let radius = Self.diameter * 0.5 - Self.lineWidth * 0.5
        let percentage = Int((clampedNormalizedValue * 100).rounded())

        GeometryReader { proxy in
            ZStack {
                GaugeArc(progress: 1)
                    .stroke(trackColor, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))

                GaugeArc(progress: progress)
                    .stroke(
                        isOn ? Self.onGradient : Self.offGradient,
                        style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round)
                    )

                Circle()
                    .fill(.white)
                    .overlay {
                        Circle()
                            .strokeBorder(AppColors.midnight.opacity(0.18), lineWidth: 1)
                    }
                    .frame(width: Self.handleSize, height: Self.handleSize)
                    .offset(x: radius)
                    .rotationEffect(.degrees(angle))
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled else { return }
                        onValueChanged(normalizedValue(for: value.location, in: proxy.size))
                    }
                    .onEnded { value in
                        guard isEnabled else { return }
                        onEditingEnded(normalizedValue(for: value.location, in: proxy.size))
                    }
            )
        }
        .opacity(isEnabled ? 1 : 0.65)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Light brightness")
        .accessibilityValue("\(percentage)%")
    }

    private func normalizedValue(for location: CGPoint, in size: CGSize) -> Double {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let dx = location.x - center.x
        let dy = center.y - location.y
        let angle = atan2(dy, dx) * 180 / .pi
        let clampedAngle: Double

        if angle > 150 {
            clampedAngle = Self.maximumAngle
        } else if angle < -150 {
            clampedAngle = Self.minimumAngle
        } else {
            clampedAngle = angle
        }

        let progress = min(max((clampedAngle - Self.minimumAngle) / Self.sweepAngle, 0), 1)
        return 1 - progress
    }

    private var trackColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.26) : AppColors.cloud.opacity(0.95)
    }

    private static let diameter: CGFloat = 86
    private static let lineWidth: CGFloat = 11
    private static let handleSize: CGFloat = 20
    private static let minimumAngle: Double = -150
    private static let maximumAngle: Double = 150
    private static let startAngle: Double = minimumAngle
    private static let sweepAngle: Double = 300

    private static let onGradient = AngularGradient(
        colors: [Color.yellow, AppColors.ember, Color.yellow],
        center: .center
    )

    private static let offGradient = AngularGradient(
        colors: [Color.white.opacity(0.5), Color.white.opacity(0.2)],
        center: .center
    )
}

private struct LightColorPresetPicker: View {
    enum Style {
        case compact
        case expanded

        var horizontalSpacing: CGFloat { 4 }

        var verticalSpacing: CGFloat {
            switch self {
            case .compact:
                return 4
            case .expanded:
                return 6
            }
        }

        var swatchSize: CGSize {
            switch self {
            case .compact:
                return CGSize(width: 26, height: 20)
            case .expanded:
                return CGSize(width: 32, height: 28)
            }
        }

        var containerPadding: EdgeInsets {
            switch self {
            case .compact:
                return EdgeInsets(top: 4, leading: 2, bottom: 4, trailing: 2)
            case .expanded:
                return EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0)
            }
        }

        var rows: [[LightColorPreset.Kind]] {
            switch self {
            case .compact:
                return [
                    [.red, .cyan],
                    [.pink, .green],
                    [.violet, .yellow],
                    [.blue, .orange],
                ]
            case .expanded:
                return [
                    [.red, .pink, .violet, .blue],
                    [.cyan, .green, .yellow, .orange],
                ]
            }
        }
    }

    let selectedPreset: LightColorPreset?
    let isEnabled: Bool
    let style: Style
    let onPresetSelected: (LightColorPreset) -> Void

    private let calibration = DrivingLightColorDescriptor.packedXYCalibration

    var body: some View {
        let presets = calibration.presets
        let presetsByKind = Dictionary(uniqueKeysWithValues: presets.map { ($0.kind, $0) })
        let selectedPresetKind = selectedPreset?.kind

        Grid(horizontalSpacing: style.horizontalSpacing, verticalSpacing: style.verticalSpacing) {
            ForEach(Array(style.rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(row, id: \.self) { presetKind in
                        if let preset = presetsByKind[presetKind] {
                            LightColorPresetSwatch(
                                preset: preset,
                                swatchSize: style.swatchSize,
                                isSelected: selectedPresetKind == preset.kind,
                                isEnabled: isEnabled
                            ) {
                                onPresetSelected(preset)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(style.containerPadding)
        .opacity(isEnabled ? 1 : 0.62)
        .sensoryFeedback(.selection, trigger: selectedPresetKind)
        .accessibilityElement(children: .contain)
    }
}

private struct LightColorPresetSwatch: View {
    let preset: LightColorPreset
    let swatchSize: CGSize
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(swatchFill)
                .overlay {
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                }
                .overlay {
                    if isSelected {
                        ZStack {
                            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                                .strokeBorder(.white.opacity(0.96), lineWidth: 2)

                            RoundedRectangle(cornerRadius: Self.cornerRadius - 1, style: .continuous)
                                .strokeBorder(AppColors.midnight.opacity(0.22), lineWidth: 1)
                                .padding(1.5)

                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.32), radius: 1, x: 0, y: 1)
                        }
                    }
                }
                .frame(width: swatchSize.width, height: swatchSize.height)
                .shadow(
                    color: isSelected ? swatchFill.opacity(0.28) : .clear,
                    radius: isSelected ? 6 : 0,
                    x: 0,
                    y: 2
                )
                .scaleEffect(isSelected ? 1 : 0.96)
                .animation(.spring(response: 0.24, dampingFraction: 0.8), value: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(preset.title)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityHint("Sets the light color")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var swatchFill: Color {
        Color(
            red: preset.displayRGB.red,
            green: preset.displayRGB.green,
            blue: preset.displayRGB.blue
        )
        .opacity(isEnabled ? 1 : 0.92)
    }

    private static let cornerRadius: CGFloat = 8
}

private struct LightPowerButton: View {
    let isOn: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(buttonBackground)
                Circle()
                    .strokeBorder(borderColor, lineWidth: 1.2)
                Image(systemName: "power")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(symbolColor)
            }
            .frame(width: Self.buttonSize, height: Self.buttonSize)
            .shadow(
                color: shadowColor,
                radius: 6,
                x: 0,
                y: 2
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.65)
        .accessibilityLabel(isOn ? "Turn lights off" : "Turn lights on")
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private var buttonBackground: LinearGradient {
        LinearGradient(
            colors: isOn
                ? [Color.yellow.opacity(0.42), AppColors.ember.opacity(0.26)]
                : [Color.blue.opacity(0.38), Color.blue.opacity(0.24)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderColor: Color {
        isOn ? AppColors.ember.opacity(0.55) : .blue.opacity(0.55)
    }

    private var symbolColor: Color {
        isOn ? AppColors.ember.opacity(0.95) : .blue.opacity(0.9)
    }

    private var shadowColor: Color {
        isOn ? AppColors.ember.opacity(0.28) : .blue.opacity(0.28)
    }

    private static let buttonSize: CGFloat = 40
}

private struct GaugeArc: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clampedProgress = min(max(progress, 0), 1)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.5 - Self.lineWidth * 0.5
        let startAngle = Angle.degrees(Self.startAngle)
        let endAngle = Angle.degrees(Self.startAngle + Self.sweepAngle * Double(clampedProgress))

        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }

    private static let lineWidth: CGFloat = 11
    private static let startAngle: Double = -150
    private static let sweepAngle: Double = 300
}

#if DEBUG
#Preview("Compact Red") {
    PreviewSingleLightCard(
        normalizedColor: 1.0,
        isColorEnabled: true,
        dynamicTypeSize: .large
    )
}

#Preview("Compact Disabled") {
    PreviewSingleLightCard(
        normalizedColor: 0.88,
        isColorEnabled: false,
        dynamicTypeSize: .large
    )
}

#Preview("Accessibility Layout") {
    PreviewSingleLightCard(
        normalizedColor: 0.46,
        isColorEnabled: true,
        dynamicTypeSize: .accessibility3
    )
}

private struct PreviewSingleLightCard: View {
    let normalizedColor: Double
    let isColorEnabled: Bool
    let dynamicTypeSize: DynamicTypeSize

    private let deviceId = DeviceIdentifier(deviceId: 10, endpointId: 1)

    var body: some View {
        SingleLightView(deviceId: deviceId)
            .environment(
                \.singleLightStoreFactory,
                 .init(make: { _ in
                     makePreviewStore(
                        deviceId: deviceId,
                        normalizedColor: normalizedColor,
                        isColorEnabled: isColorEnabled
                    )
                })
            )
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .padding(16)
            .frame(width: 180, height: 180)
            .glassCard(cornerRadius: 22)
            .padding()
            .background(AppColors.midnight.opacity(0.16))
    }
}

@MainActor
private func makePreviewStore(
    deviceId: DeviceIdentifier,
    normalizedColor: Double,
    isColorEnabled: Bool
) -> SingleLightStore {
    let store = SingleLightStore(
        deviceId: deviceId,
        observeLight: .init(
            observeLight: {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        ),
        sendCommand: .init(
            sendCommand: { _ in }
        )
    )

    let selectedPreset = DrivingLightColorDescriptor.packedXYCalibration.nearestPreset(for: normalizedColor)

    store.send(
        .gatewayDescriptorWasReceived(
            DrivingLightControlDescriptor(
                powerKey: "on",
                levelKey: "level",
                isOn: true,
                level: 64,
                range: 0...100,
                color: isColorEnabled && selectedPreset != nil
                    ? DrivingLightColorDescriptor(
                        key: "colorXY",
                        modeKey: nil,
                        modeValue: nil,
                        temperatureKey: "miredTemperatureW",
                        value: Double(selectedPreset?.packedXY ?? 0),
                        range: 0...4_294_967_294
                    )
                    : nil
            )
        )
    )

    return store
}
#endif
