import SwiftUI
import DeltaDoreClient

struct AppBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = colorScheme == .dark
            ? [AppColors.midnight, AppColors.slate, AppColors.aurora]
            : [AppColors.mist, AppColors.cloud, AppColors.sunrise]

        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(AppColors.ember.opacity(colorScheme == .dark ? 0.25 : 0.18))
                .frame(width: 260, height: 260)
                .blur(radius: 40)
                .offset(x: 140, y: -120)
            Circle()
                .fill(AppColors.aurora.opacity(colorScheme == .dark ? 0.22 : 0.18))
                .frame(width: 340, height: 340)
                .blur(radius: 60)
                .offset(x: -160, y: 180)
        }
    }
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

            Text(device.statusText)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)

            DeviceControlView(descriptor: device.primaryControlDescriptor(), onChange: onControlChange)
        }
        .padding(16)
        .glassCard(cornerRadius: 22)
    }
}

struct DeviceRow: View {
    let device: DeviceRecord
    let onToggleFavorite: () -> Void
    let onControlChange: (String, JSONValue) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: device.group.symbolName)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(AppColors.sunrise.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.system(.headline, design: .rounded))
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

                DeviceControlView(descriptor: device.primaryControlDescriptor(), onChange: onControlChange)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 18)
    }
}

struct DeviceControlView: View {
    let descriptor: DeviceControlDescriptor?
    let onChange: (String, JSONValue) -> Void

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
        } else {
            EmptyView()
        }
    }
}
