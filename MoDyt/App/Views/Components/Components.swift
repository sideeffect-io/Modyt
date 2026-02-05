import SwiftUI
import DeltaDoreClient

struct AppBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    private struct BackgroundBlob: Identifiable {
        let id: Int
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
        let blur: CGFloat
        let opacity: Double
        let blendMode: BlendMode
    }

    private struct NoiseDot: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
        let radius: CGFloat
        let opacity: Double
    }

    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &*= 6364136223846793005
            state &+= 1
            return state
        }
    }

    private static let noiseDots: [NoiseDot] = {
        var rng = SeededGenerator(seed: 0xC0FFEE)
        return (0..<140).map { index in
            NoiseDot(
                id: index,
                x: CGFloat.random(in: 0...1, using: &rng),
                y: CGFloat.random(in: 0...1, using: &rng),
                radius: CGFloat.random(in: 0.0015...0.0045, using: &rng),
                opacity: Double.random(in: 0.15...0.45, using: &rng)
            )
        }
    }()

    private var blobs: [BackgroundBlob] {
        colorScheme == .dark ? darkBlobs : lightBlobs
    }

    var body: some View {
        let colors = colorScheme == .dark
            ? [Color(red: 0.03, green: 0.04, blue: 0.06), Color(red: 0.07, green: 0.09, blue: 0.14), Color(red: 0.1, green: 0.18, blue: 0.24)]
            : [AppColors.mist, AppColors.cloud, AppColors.sunrise]

        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)

                ForEach(blobs) { blob in
                    Circle()
                        .fill(blob.color)
                        .frame(width: blob.radius * 2, height: blob.radius * 2)
                        .position(
                            x: proxy.size.width * blob.x,
                            y: proxy.size.height * blob.y
                        )
                        .blur(radius: blob.blur)
                        .opacity(blob.opacity)
                        .blendMode(blob.blendMode)
                }

                if colorScheme == .dark {
                    Canvas { context, size in
                        for dot in Self.noiseDots {
                            let radius = min(size.width, size.height) * dot.radius
                            let rect = CGRect(
                                x: size.width * dot.x,
                                y: size.height * dot.y,
                                width: radius,
                                height: radius
                            )
                            context.fill(
                                Path(ellipseIn: rect),
                                with: .color(.white.opacity(dot.opacity))
                            )
                        }
                    }
                    .blendMode(.overlay)
                    .opacity(0.18)
                }
            }
            .ignoresSafeArea()
        }
    }

    private let lightBlobs: [BackgroundBlob] = [
        BackgroundBlob(
            id: 0,
            color: AppColors.sunrise,
            radius: 220,
            x: 0.15,
            y: 0.18,
            blur: 40,
            opacity: 0.45,
            blendMode: .softLight
        ),
        BackgroundBlob(
            id: 1,
            color: AppColors.aurora,
            radius: 260,
            x: 0.85,
            y: 0.12,
            blur: 55,
            opacity: 0.25,
            blendMode: .overlay
        ),
        BackgroundBlob(
            id: 2,
            color: AppColors.cloud,
            radius: 320,
            x: 0.25,
            y: 0.75,
            blur: 60,
            opacity: 0.35,
            blendMode: .softLight
        ),
        BackgroundBlob(
            id: 3,
            color: AppColors.ember,
            radius: 240,
            x: 0.8,
            y: 0.8,
            blur: 70,
            opacity: 0.18,
            blendMode: .overlay
        )
    ]

    private let darkBlobs: [BackgroundBlob] = [
        BackgroundBlob(
            id: 0,
            color: AppColors.aurora,
            radius: 300,
            x: 0.18,
            y: 0.22,
            blur: 70,
            opacity: 0.5,
            blendMode: .screen
        ),
        BackgroundBlob(
            id: 1,
            color: AppColors.ember,
            radius: 260,
            x: 0.88,
            y: 0.2,
            blur: 70,
            opacity: 0.45,
            blendMode: .screen
        ),
        BackgroundBlob(
            id: 2,
            color: Color(red: 0.16, green: 0.24, blue: 0.32),
            radius: 420,
            x: 0.2,
            y: 0.82,
            blur: 90,
            opacity: 0.55,
            blendMode: .plusLighter
        ),
        BackgroundBlob(
            id: 3,
            color: Color(red: 0.09, green: 0.14, blue: 0.2),
            radius: 460,
            x: 0.82,
            y: 0.78,
            blur: 100,
            opacity: 0.6,
            blendMode: .plusLighter
        )
    ]
}

enum AppColors {
    static let midnight = Color(red: 0.05, green: 0.08, blue: 0.12)
    static let slate = Color(red: 0.12, green: 0.18, blue: 0.24)
    static let aurora = Color(red: 0.12, green: 0.52, blue: 0.50)
    static let ember = Color(red: 0.96, green: 0.62, blue: 0.28)
    static let mist = Color(red: 0.97, green: 0.97, blue: 0.98)
    static let cloud = Color(red: 0.86, green: 0.90, blue: 0.94)
    static let sunrise = Color(red: 0.98, green: 0.86, blue: 0.74)
}

extension View {
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 20, interactive: Bool = true) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            let base = interactive ? Glass.regular.interactive() : Glass.regular
            self.glassEffect(base, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

struct DeviceTile: View {
    let device: DeviceRecord
    let shutterTargetStep: ShutterStep?
    let shutterActualStep: ShutterStep?
    let onToggleFavorite: () -> Void
    let onControlChange: (String, JSONValue) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: device.group.symbolName)
                    .font(.system(size: 22, weight: .semibold))
                Spacer()
                Button(action: onToggleFavorite) {
                    Image(systemName: device.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(device.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
            }

            Text(device.name)
                .font(.system(.headline, design: .rounded))
                .lineLimit(1)

            if device.group != .shutter {
                Text(device.statusText)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            DeviceControlView(
                device: device,
                shutterLayout: .regular,
                shutterTargetStep: shutterTargetStep,
                shutterActualStep: shutterActualStep,
                onChange: onControlChange
            )
        }
        .padding(16)
        .glassCard(cornerRadius: 22)
    }
}

struct DeviceRow: View {
    let device: DeviceRecord
    let shutterTargetStep: ShutterStep?
    let shutterActualStep: ShutterStep?
    let onToggleFavorite: () -> Void
    let onControlChange: (String, JSONValue) -> Void

    var body: some View {
        if device.group == .shutter {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "window.shade.open")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(AppColors.sunrise.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))

                    Text(device.name)
                        .font(.system(.headline, design: .rounded))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Button(action: onToggleFavorite) {
                        Image(systemName: device.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(device.isFavorite ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                }

                DeviceControlView(
                    device: device,
                    shutterLayout: .list,
                    shutterTargetStep: shutterTargetStep,
                    shutterActualStep: shutterActualStep,
                    onChange: onControlChange
                )
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(10)
            .glassCard(cornerRadius: 18)
        } else {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: device.group.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(AppColors.sunrise.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(.headline, design: .rounded))
                        .lineLimit(1)
                    Text(device.statusText)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    Button(action: onToggleFavorite) {
                        Image(systemName: device.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(device.isFavorite ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)

                    DeviceControlView(
                        device: device,
                        shutterLayout: .compact,
                        shutterTargetStep: shutterTargetStep,
                        shutterActualStep: shutterActualStep,
                        onChange: onControlChange
                    )
                }
            }
            .padding(10)
            .glassCard(cornerRadius: 18)
        }
    }
}

private struct DeviceControlView: View {
    let device: DeviceRecord
    let shutterLayout: ShutterControlLayout
    let shutterTargetStep: ShutterStep?
    let shutterActualStep: ShutterStep?
    let onChange: (String, JSONValue) -> Void
    private var descriptor: DeviceControlDescriptor? { device.primaryControlDescriptor() }

    var body: some View {
        if let descriptor {
            switch descriptor.kind {
            case .toggle:
                Toggle("", isOn: Binding(
                    get: { descriptor.isOn },
                    set: { onChange(descriptor.key, .bool($0)) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)

            case .slider:
                if device.group == .shutter {
                    ShutterControlView(
                        descriptor: descriptor,
                        metrics: shutterLayout.metrics,
                        targetStep: shutterTargetStep,
                        actualStepOverride: shutterActualStep,
                        onChange: onChange
                    )
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        Slider(value: Binding(
                            get: { descriptor.value },
                            set: { onChange(descriptor.key, .number($0)) }
                        ), in: descriptor.range)
                        Text("\(Int(descriptor.value))")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 140)
                }
            }
        } else {
            EmptyView()
        }
    }
}

private enum ShutterControlLayout {
    case compact
    case list
    case regular

    var metrics: ShutterMetrics {
        switch self {
        case .compact:
            return .compact
        case .list:
            return .list
        case .regular:
            return .regular
        }
    }
}

private struct ShutterMetrics {
    let barWidth: CGFloat
    let barSpacing: CGFloat
    let compactHeight: CGFloat
    let expandedHeight: CGFloat
    let cornerRadius: CGFloat
    let padding: CGFloat
    let strokeWidth: CGFloat
    let overlayGap: CGFloat

    var totalWidth: CGFloat {
        barWidth * 5 + barSpacing * 4 + padding * 2
    }

    static let compact = ShutterMetrics(
        barWidth: 26,
        barSpacing: 6,
        compactHeight: 20,
        expandedHeight: 42,
        cornerRadius: 12,
        padding: 8,
        strokeWidth: 3,
        overlayGap: 2
    )

    static let list = ShutterMetrics(
        barWidth: 28,
        barSpacing: 6,
        compactHeight: 20,
        expandedHeight: 44,
        cornerRadius: 12,
        padding: 12,
        strokeWidth: 3,
        overlayGap: 2
    )

    static let regular = ShutterMetrics(
        barWidth: 32,
        barSpacing: 8,
        compactHeight: 22,
        expandedHeight: 50,
        cornerRadius: 14,
        padding: 14,
        strokeWidth: 3,
        overlayGap: 2
    )
}

private struct ShutterControlView: View {
    let descriptor: DeviceControlDescriptor
    let metrics: ShutterMetrics
    let targetStep: ShutterStep?
    let actualStepOverride: ShutterStep?
    let onChange: (String, JSONValue) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var localTargetStep: ShutterStep?
    @State private var hasUserTarget = false

    private var actualStep: ShutterStep {
        actualStepOverride ?? ShutterStep.nearestStep(for: descriptor.value, in: descriptor.range)
    }

    private var effectiveTargetStep: ShutterStep {
        localTargetStep ?? targetStep ?? actualStep
    }

    private var isInFlight: Bool {
        hasUserTarget && actualStep != effectiveTargetStep
    }

    var body: some View {
        VStack(spacing: 10) {
            shutterPills
            shutterIcons
        }
        .padding(.vertical, metrics.padding)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 18, interactive: true)
        .onAppear {
            if localTargetStep == nil {
                localTargetStep = targetStep ?? actualStep
                hasUserTarget = targetStep != nil
            }
        }
        .onChange(of: targetStep) { _, newValue in
            if let newValue {
                localTargetStep = newValue
                hasUserTarget = true
            } else {
                hasUserTarget = false
                localTargetStep = actualStep
            }
        }
        .onChange(of: actualStep) { _, newValue in
            if !hasUserTarget {
                localTargetStep = newValue
            }
        }
    }

    private var shutterPills: some View {
        HStack(alignment: .bottom, spacing: metrics.barSpacing) {
            ForEach(ShutterStep.allCases) { step in
                Button {
                    select(step)
                } label: {
                    ShutterPill(
                        step: step,
                        isTarget: step == effectiveTargetStep,
                        isActual: step == actualStep,
                        isInFlight: isInFlight,
                        metrics: metrics
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(step.accessibilityLabel)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, metrics.padding)
    }

    private var shutterIcons: some View {
        HStack(spacing: metrics.barSpacing) {
            ForEach(ShutterStep.allCases) { step in
                iconView(for: step)
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .secondary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, metrics.padding)
    }

    @ViewBuilder
    private func iconView(for step: ShutterStep) -> some View {
        switch step {
        case .open:
            Image(systemName: "sun.max")
        case .half:
            Image(systemName: "circle.bottomhalf.filled")
        case .closed:
            Image(systemName: "moon")
        case .quarter, .threeQuarter:
            Color.clear
        }
    }

    private func select(_ step: ShutterStep) {
        guard step != actualStep else { return }
        let targetValue = step.mappedValue(in: descriptor.range)
        localTargetStep = step
        hasUserTarget = true
        onChange(descriptor.key, .number(targetValue))
    }
}

private struct ShutterPill: View {
    let step: ShutterStep
    let isTarget: Bool
    let isActual: Bool
    let isInFlight: Bool
    let metrics: ShutterMetrics

    @Environment(\.colorScheme) private var colorScheme

    private var pillGradient: LinearGradient {
        let colors: [Color]
        if colorScheme == .dark {
            let top = isTarget
                ? Color(red: 0.36, green: 0.37, blue: 0.4)
                : Color(red: 0.3, green: 0.31, blue: 0.33)
            let bottom = isTarget
                ? Color(red: 0.28, green: 0.29, blue: 0.32)
                : Color(red: 0.23, green: 0.24, blue: 0.26)
            colors = [top, bottom]
        } else {
            colors = [
                .black.opacity(isTarget ? 0.9 : 0.82),
                .black.opacity(isTarget ? 0.7 : 0.64)
            ]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
            .fill(pillGradient)
            .frame(
                height: isTarget ? metrics.expandedHeight : metrics.compactHeight,
                alignment: .bottom
            )
            .overlay {
                ShutterActualOverlay(
                    isVisible: isActual,
                    isPulsing: isInFlight && isActual,
                    metrics: metrics
                )
            }
            .shadow(color: .black.opacity(isTarget ? 0.35 : 0.2), radius: 6, x: 0, y: 4)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isTarget)
            .frame(minWidth: metrics.barWidth, maxWidth: .infinity, minHeight: metrics.expandedHeight, alignment: .bottom)
            .contentShape(.rect)
    }
}

private struct ShutterActualOverlay: View {
    let isVisible: Bool
    let isPulsing: Bool
    let metrics: ShutterMetrics

    @State private var pulseOn = false

    private var pulseOpacity: Double {
        isPulsing ? (pulseOn ? 0.2 : 1.0) : 1.0
    }

    var body: some View {
        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
            .inset(by: -(metrics.overlayGap + metrics.strokeWidth / 2))
            .stroke(.blue, lineWidth: metrics.strokeWidth)
            .shadow(color: .blue.opacity(isPulsing ? 0.6 : 0.4), radius: isPulsing ? 8 : 6)
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.24), value: isVisible)
            .opacity(pulseOpacity)
            .onAppear { updatePulse(isPulsing) }
            .onChange(of: isPulsing) { _, newValue in
                updatePulse(newValue)
            }
    }

    private func updatePulse(_ active: Bool) {
        if active {
            pulseOn = false
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulseOn = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                pulseOn = false
            }
        }
    }
}
