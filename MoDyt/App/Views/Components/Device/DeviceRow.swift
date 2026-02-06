import SwiftUI
import DeltaDoreClient

struct DeviceRow: View {
    let device: DeviceRecord
    let shutterRepository: ShutterRepository
    let onToggleFavorite: () -> Void
    let onControlChange: (String, JSONValue) -> Void

    var body: some View {
        if device.group == .shutter {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: "window.shade.open")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(AppColors.sunrise.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))

                    Text(device.name)
                        .font(.system(.headline, design: .rounded))
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Button(action: onToggleFavorite) {
                        Image(systemName: device.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(device.isFavorite ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 28, height: 28)
                }

                DeviceControlView(
                    device: device,
                    shutterLayout: .list,
                    shutterRepository: shutterRepository,
                    onChange: onControlChange
                )
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(8)
            .glassCard(cornerRadius: 16)
        } else {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: device.group.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(AppColors.sunrise.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(.headline, design: .rounded))
                        .lineLimit(1)
                    Text(device.statusText)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 6) {
                    Button(action: onToggleFavorite) {
                        Image(systemName: device.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(device.isFavorite ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 28, height: 28)

                    DeviceControlView(
                        device: device,
                        shutterLayout: .compact,
                        shutterRepository: shutterRepository,
                        onChange: onControlChange
                    )
                }
            }
            .padding(8)
            .glassCard(cornerRadius: 16)
        }
    }
}
