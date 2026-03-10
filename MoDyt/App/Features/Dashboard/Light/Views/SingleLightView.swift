import SwiftUI

struct SingleLightView: View {
    @Environment(\.singleLightStoreDependencies) private var singleLightStoreDependencies
    @Environment(\.colorScheme) private var colorScheme

    let deviceId: DeviceIdentifier

    @State private var draftNormalizedLevel: Double?

    var body: some View {
        WithStoreView(
            store: SingleLightStore(
                deviceId: deviceId,
                dependencies: singleLightStoreDependencies
            )
        ) { store in
            HStack(alignment: .center, spacing: 14) {
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
                    .frame(width: 86, height: 86)
                    .frame(maxWidth: .infinity, alignment: .center)

                PowerClusterView(
                    isOn: store.displayedIsOn,
                    isEnabled: store.isInteractionEnabled
                ) {
                    store.send(.powerWasSet(!store.displayedIsOn))
                }
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement(children: .contain)
            .onDisappear {
                draftNormalizedLevel = nil
            }
        }
        .id(deviceId.storageKey)
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

                VStack(spacing: 2) {
                    Image(systemName: isOn ? "lightbulb.max.fill" : "lightbulb.slash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text("\(percentage)")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .monospacedDigit()
                }
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

private struct PowerClusterView: View {
    let isOn: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(buttonBackground)
                    Circle()
                        .strokeBorder(borderColor, lineWidth: 1.2)
                    Image(systemName: "power")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(symbolColor)
                }
                .frame(width: 48, height: 48)
                .shadow(
                    color: shadowColor,
                    radius: 6,
                    x: 0,
                    y: 2
                )
                .accessibilityLabel(isOn ? "Turn lights off" : "Turn lights on")
                .accessibilityValue(isOn ? "On" : "Off")

                Text("Power")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.65)
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
