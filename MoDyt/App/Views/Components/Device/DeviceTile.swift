import SwiftUI
import DeltaDoreClient

struct DeviceTile: View {
    let device: DeviceRecord
    let shutterRepository: ShutterRepository
    let onToggleFavorite: () -> Void
    let onControlChange: (String, JSONValue) -> Void

    private let dashboardCardHeight: CGFloat = 194

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Image(systemName: device.group.symbolName)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 36, height: 36)
                Spacer()
                FavoriteOrbButton(
                    isFavorite: device.isFavorite,
                    size: 32,
                    action: onToggleFavorite
                )
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
        .frame(height: dashboardCardHeight, alignment: .top)
        .glassCard(cornerRadius: 22)
    }
}
