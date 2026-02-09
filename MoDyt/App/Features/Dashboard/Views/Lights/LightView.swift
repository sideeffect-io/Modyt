import SwiftUI
import DeltaDoreClient

struct LightView: View {
    @Environment(\.lightStoreFactory) private var lightStoreFactory

    let uniqueId: String
    let device: DeviceRecord

    @State private var interactionNormalizedLevel: Double?

    var body: some View {
        WithStoreView(factory: { lightStoreFactory.make(uniqueId, device) }) { store in
            let descriptor = store.descriptor
            let displayedNormalized = interactionNormalizedLevel ?? descriptor.normalizedLevel
            let dialIsOn = descriptor.isOn || displayedNormalized > 0.001
            let displayedPercentage = Int((displayedNormalized * 100).rounded())
            let dialAnimation: Animation? = interactionNormalizedLevel == nil
                ? .easeInOut(duration: 0.24)
                : nil

            HStack(alignment: .center, spacing: 12) {
                CircularIntensityDial(
                    normalizedValue: displayedNormalized,
                    isOn: dialIsOn,
                    onChange: { normalized in
                        interactionNormalizedLevel = normalized
                    },
                    onCommit: { normalized in
                        interactionNormalizedLevel = nil
                        store.setLevelNormalized(normalized)
                    }
                )
                .frame(width: 80, height: 80)
                .animation(dialAnimation, value: displayedNormalized)
                .animation(dialAnimation, value: dialIsOn)

                VStack(spacing: 8) {
                    Button {
                        let targetNormalized = descriptor.isOn ? 0.0 : 1.0
                        interactionNormalizedLevel = nil
                        withAnimation(.easeInOut(duration: 0.24)) {
                            store.setLevelNormalized(targetNormalized)
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(powerButtonBackground(isOn: descriptor.isOn))
                            Circle()
                                .strokeBorder(.blue.opacity(descriptor.isOn ? 0.95 : 0.35), lineWidth: 1.2)
                            Image(systemName: "power")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(descriptor.isOn ? .white : .blue.opacity(0.85))
                        }
                        .frame(width: 48, height: 48)
                        .shadow(
                            color: .blue.opacity(descriptor.isOn ? 0.45 : 0.18),
                            radius: descriptor.isOn ? 8 : 4.5,
                            x: 0,
                            y: 2
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(descriptor.isOn ? "Turn lights off" : "Turn lights on")

                    Text(descriptor.isOn ? "On" : "Off")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Driving lights")
            .accessibilityValue("\(displayedPercentage) percent, \(descriptor.isOn ? "on" : "off")")
        }
    }

    private func powerButtonBackground(isOn: Bool) -> LinearGradient {
        if isOn {
            return LinearGradient(
                colors: [Color.blue.opacity(0.95), Color.blue.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [Color.blue.opacity(0.2), Color.blue.opacity(0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct CircularIntensityDial: View {
    @Environment(\.colorScheme) private var colorScheme

    let normalizedValue: Double
    let isOn: Bool
    let onChange: (Double) -> Void
    let onCommit: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let lineWidth = max(8, size * 0.13)
            let ringRadius = max(0, (size - lineWidth) * 0.5)
            let handleDiameter = max(20, lineWidth * 1.9)
            let activeSpan = max(0.55, 1 - dialGapFraction)
            let ringProgress = activeSpan * min(max(normalizedValue, 0), 1)
            let handleAngleDegrees = dialStartAngleDegrees + (ringProgress * 360)
            let value = min(max(normalizedValue, 0), 1)

            ZStack {
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: 0, to: activeSpan)
                    .stroke(
                        dialTrackColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(dialStartAngleDegrees))

                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: 0, to: ringProgress)
                    .stroke(
                        dialGradient(isOn: isOn),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(dialStartAngleDegrees))

                ZStack {
                    Circle()
                        .fill(.white)
                    Circle()
                        .strokeBorder(AppColors.midnight.opacity(0.18), lineWidth: 1)
                }
                .frame(width: handleDiameter, height: handleDiameter)
                .offset(x: ringRadius)
                .rotationEffect(.degrees(handleAngleDegrees))
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)

                VStack(spacing: 2) {
                    Image(systemName: isOn ? "lightbulb.max.fill" : "lightbulb.slash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("\(Int((value * 100).rounded()))")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .monospacedDigit()
                }
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        onChange(normalized(from: gesture.location, in: proxy.size))
                    }
                    .onEnded { gesture in
                        onCommit(normalized(from: gesture.location, in: proxy.size))
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func normalized(from location: CGPoint, in size: CGSize) -> Double {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let deltaX = location.x - center.x
        let deltaY = location.y - center.y
        let rawAngle = atan2(deltaY, deltaX)
        let rawDegrees = rawAngle * 180 / .pi
        let turn = (rawDegrees - dialStartAngleDegrees + 360).truncatingRemainder(dividingBy: 360) / 360
        let activeSpan = max(0.55, 1 - dialGapFraction)

        let clampedTurn: Double
        if turn <= activeSpan {
            clampedTurn = turn
        } else {
            let distanceToMax = turn - activeSpan
            let distanceToMin = 1 - turn
            clampedTurn = distanceToMax < distanceToMin ? activeSpan : 0
        }

        return min(max(clampedTurn / activeSpan, 0), 1)
    }

    private func dialGradient(isOn: Bool) -> AngularGradient {
        if isOn {
            return AngularGradient(
                colors: [Color.yellow, AppColors.ember, Color.yellow],
                center: .center
            )
        }
        return AngularGradient(
            colors: [Color.white.opacity(0.5), Color.white.opacity(0.2)],
            center: .center
        )
    }

    private var dialTrackColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.26)
            : AppColors.cloud.opacity(0.95)
    }

    private var dialGapFraction: Double { 0.16 }

    private var dialStartAngleDegrees: Double { -150 }
}
