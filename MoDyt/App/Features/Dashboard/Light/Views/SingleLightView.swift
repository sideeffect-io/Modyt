import SwiftUI

struct SingleLightView: View {
    @Environment(\.singleLightStoreFactory) private var singleLightStoreFactory
    @Environment(\.colorScheme) private var colorScheme

    let deviceId: DeviceIdentifier

    @State private var draftNormalizedLevel: Double?
    @State private var draftNormalizedColor: Double?

    var body: some View {
        WithStoreView(
            store: singleLightStoreFactory.make(deviceId: deviceId)
        ) { store in
            GeometryReader { proxy in
                let horizontalGap = max(
                    (proxy.size.width - Self.gaugeDiameter - Self.colorControlWidth) / 3,
                    0
                )

                HStack(alignment: .center, spacing: horizontalGap) {
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
                            store.send(.powerWasSet(!store.displayedIsOn))
                        }
                    }
                    .frame(width: Self.gaugeDiameter, height: Self.gaugeDiameter)

                    LightColorSpectrumControl(
                        colorScheme: colorScheme,
                        normalizedValue: draftNormalizedColor ?? store.displayedNormalizedColor,
                        isEnabled: store.isColorInteractionEnabled,
                        onValueChanged: { draftNormalizedColor = $0 },
                        onEditingEnded: { normalizedValue in
                            draftNormalizedColor = nil
                            store.send(.colorWasCommitted(normalizedValue))
                        }
                    )
                    .frame(width: Self.colorControlWidth, height: Self.colorControlHeight)
                }
                .padding(.horizontal, horizontalGap)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement(children: .contain)
            .onDisappear {
                draftNormalizedLevel = nil
                draftNormalizedColor = nil
            }
        }
        .id(deviceId.storageKey)
    }

    private static let gaugeDiameter: CGFloat = 86
    private static let colorControlWidth: CGFloat = 18
    private static let colorControlHeight: CGFloat = 100
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

private struct LightColorSpectrumControl: View {
    let colorScheme: ColorScheme
    let normalizedValue: Double
    let isEnabled: Bool
    let onValueChanged: (Double) -> Void
    let onEditingEnded: (Double) -> Void

    var body: some View {
        let clampedNormalizedValue = min(max(normalizedValue, 0), 1)

        GeometryReader { proxy in
            let markerOffset = markerOffset(
                for: clampedNormalizedValue,
                in: proxy.size.height
            )

            ZStack {
                Capsule(style: .continuous)
                    .fill(trackBackground)

                Capsule(style: .continuous)
                    .fill(Self.spectrumGradient)
                    .padding(3)

                Circle()
                    .fill(selectedColor(for: clampedNormalizedValue))
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.92), lineWidth: 2)
                    }
                    .frame(width: Self.handleSize, height: Self.handleSize)
                    .shadow(color: selectedColor(for: clampedNormalizedValue).opacity(0.32), radius: 8, x: 0, y: 2)
                    .shadow(color: .black.opacity(0.16), radius: 3, x: 0, y: 1)
                    .offset(y: markerOffset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
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
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Light color")
        .accessibilityValue("\(Int((clampedNormalizedValue * 100).rounded()))%")
        .accessibilityHint(isEnabled ? "Adjust the light color" : "Color control unavailable")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }

            let delta: Double
            switch direction {
            case .increment:
                delta = 0.05
            case .decrement:
                delta = -0.05
            @unknown default:
                delta = 0
            }
            guard delta != 0 else { return }

            let adjustedValue = min(max(clampedNormalizedValue + delta, 0), 1)
            onEditingEnded(adjustedValue)
        }
    }

    private func normalizedValue(for location: CGPoint, in size: CGSize) -> Double {
        let availableHeight = max(size.height - (Self.trackInset * 2), 1)
        let clampedY = min(max(location.y - Self.trackInset, 0), availableHeight)
        return 1 - Double(clampedY / availableHeight)
    }

    private func markerOffset(for normalizedValue: Double, in height: CGFloat) -> CGFloat {
        let availableHeight = max(height - (Self.trackInset * 2), 1)
        let y = (1 - CGFloat(normalizedValue)) * availableHeight
        return (y + Self.trackInset) - (height * 0.5)
    }

    private func selectedColor(for normalizedValue: Double) -> Color {
        Color(
            hue: normalizedValue,
            saturation: isEnabled ? 0.86 : 0.14,
            brightness: isEnabled ? 1 : 0.9
        )
    }

    private var trackBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.18)
            : Color.white.opacity(0.6)
    }

    private static let trackInset: CGFloat = 10
    private static let handleSize: CGFloat = 18
    private static let spectrumGradient = LinearGradient(
        gradient: Gradient(stops: [
            .init(color: .red, location: 0.00),
            .init(color: .pink, location: 0.12),
            .init(color: .purple, location: 0.24),
            .init(color: .blue, location: 0.40),
            .init(color: .cyan, location: 0.54),
            .init(color: .green, location: 0.68),
            .init(color: .yellow, location: 0.82),
            .init(color: .orange, location: 0.92),
            .init(color: .red, location: 1.00),
        ]),
        startPoint: .top,
        endPoint: .bottom
    )
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
