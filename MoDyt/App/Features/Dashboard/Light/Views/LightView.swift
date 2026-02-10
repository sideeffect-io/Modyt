import SwiftUI

struct LightView: View {
    @Environment(\.lightStoreFactory) private var lightStoreFactory

    let uniqueId: String

    @State private var requestedPowerTarget: Double?

    var body: some View {
        WithStoreView(factory: { lightStoreFactory.make(uniqueId) }) { store in
            let descriptor = store.descriptor
            let powerIsOn = descriptor.isOn
            let percentage = Int((descriptor.normalizedLevel * 100).rounded())

            HStack(alignment: .center, spacing: 14) {
                GaugeControlView(
                    sourceNormalizedLevel: descriptor.normalizedLevel,
                    requestedTarget: $requestedPowerTarget,
                    onCommit: { normalized in
                        store.setLevelNormalized(normalized)
                    }
                )
                .frame(width: 86, height: 86)
                .frame(maxWidth: .infinity, alignment: .center)

                PowerClusterView(
                    onToggle: {
                        requestedPowerTarget = powerIsOn ? 0.0 : 1.0
                    }
                )
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Driving lights")
            .accessibilityValue("\(percentage) percent, \(powerIsOn ? "on" : "off")")
        }
    }
}

private struct GaugeControlView: View {
    let sourceNormalizedLevel: Double
    @Binding var requestedTarget: Double?
    let onCommit: (Double) -> Void

    @State private var dragValue: Double?
    @State private var renderedValue: Double = 0
    @State private var hasInitialValue = false

    var body: some View {
        let sourceValue = dragValue ?? sourceNormalizedLevel
        let clampedRenderedValue = Self.clamp(renderedValue)
        let isOn = clampedRenderedValue > 0.001
        let percentage = Int((clampedRenderedValue * 100).rounded())

        PathGauge(
            normalizedValue: clampedRenderedValue,
            isOn: isOn,
            percentage: percentage,
            onChange: { normalized in
                let snapped = Self.snap(normalized)
                guard shouldAcceptDragValue(snapped) else { return }
                dragValue = snapped
                renderedValue = snapped
            },
            onCommit: { normalized in
                let snapped = Self.snap(normalized)
                renderedValue = snapped
                dragValue = nil
                onCommit(snapped)
            }
        )
        .onAppear {
            guard !hasInitialValue else { return }
            renderedValue = sourceValue
            hasInitialValue = true
        }
        .onChange(of: sourceValue) { _, newValue in
            guard hasInitialValue else {
                renderedValue = newValue
                hasInitialValue = true
                return
            }
            guard abs(renderedValue - newValue) > 0.0005 else { return }

            if dragValue == nil {
                withAnimation(.easeInOut(duration: 0.24)) {
                    renderedValue = newValue
                }
            } else {
                renderedValue = newValue
            }
        }
        .onChange(of: requestedTarget) { _, target in
            guard let target else { return }
            let snapped = Self.snap(target)
            dragValue = nil
            withAnimation(.easeInOut(duration: 0.22)) {
                renderedValue = snapped
            }
            onCommit(snapped)
            requestedTarget = nil
        }
    }

    private func shouldAcceptDragValue(_ value: Double) -> Bool {
        guard let current = dragValue else { return true }
        return abs(current - value) > 0.005
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func snap(_ value: Double) -> Double {
        let clamped = clamp(value)
        return (clamped * 100).rounded() / 100
    }
}

private struct PathGauge: View {
    @Environment(\.colorScheme) private var colorScheme

    let normalizedValue: Double
    let isOn: Bool
    let percentage: Int
    let onChange: (Double) -> Void
    let onCommit: (Double) -> Void

    var body: some View {
        let progress = CGFloat(min(max(normalizedValue, 0), 1))
        let angle = Self.startAngle + (Self.sweepAngle * Double(progress))
        let radius = Self.diameter * 0.5 - Self.lineWidth * 0.5

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
        .frame(width: Self.diameter, height: Self.diameter)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    onChange(normalized(from: gesture.location))
                }
                .onEnded { gesture in
                    onCommit(normalized(from: gesture.location))
                }
        )
    }

    private var trackColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.26) : AppColors.cloud.opacity(0.95)
    }

    private func normalized(from location: CGPoint) -> Double {
        let center = CGPoint(x: Self.diameter * 0.5, y: Self.diameter * 0.5)
        let deltaX = location.x - center.x
        let deltaY = location.y - center.y
        let degrees = atan2(deltaY, deltaX) * 180 / .pi
        let turn = (degrees - Self.startAngle + 360).truncatingRemainder(dividingBy: 360) / 360
        let activeTurn = Self.sweepAngle / 360

        if turn <= activeTurn {
            return turn / activeTurn
        }

        let distanceToMax = turn - activeTurn
        let distanceToMin = 1 - turn
        return distanceToMax < distanceToMin ? 1 : 0
    }

    private static let diameter: CGFloat = 86
    private static let lineWidth: CGFloat = 11
    private static let handleSize: CGFloat = 20
    private static let startAngle: Double = -150
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
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .fill(Self.buttonBackground)
                    Circle()
                        .strokeBorder(.blue.opacity(0.55), lineWidth: 1.2)
                    Image(systemName: "power")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.blue.opacity(0.9))
                }
                .frame(width: 48, height: 48)
                .shadow(
                    color: .blue.opacity(0.28),
                    radius: 6,
                    x: 0,
                    y: 2
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle lights")

            Text("Power")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
    
    private static let buttonBackground = LinearGradient(
        colors: [Color.blue.opacity(0.38), Color.blue.opacity(0.24)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
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
