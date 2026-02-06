import SwiftUI
import DeltaDoreClient

struct DeviceTile: View {
    let device: DeviceRecord
    let shutterRepository: ShutterRepository
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
                shutterRepository: shutterRepository,
                onChange: onControlChange
            )
        }
        .padding(16)
        .glassCard(cornerRadius: 22)
    }
}
