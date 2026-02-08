import SwiftUI

struct DeviceRow: View {
    let device: DeviceRecord
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(device.name)
                .font(.system(.headline, design: .rounded))
                .lineLimit(1)

            Spacer(minLength: 8)

            FavoriteOrbButton(
                isFavorite: device.isFavorite,
                action: onToggleFavorite
            )
        }
        .padding(16)
        .glassCard(cornerRadius: 22)
    }
}
