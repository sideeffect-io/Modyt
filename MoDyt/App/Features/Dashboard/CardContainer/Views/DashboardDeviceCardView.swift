import SwiftUI

struct DashboardDeviceCardView: View {
    @Environment(\.dashboardDeviceCardStoreFactory) private var dashboardDeviceCardStoreFactory

    let device: DashboardDeviceDescription

    private let dashboardCardHeight: CGFloat = 194

    var body: some View {
        WithStoreView(factory: { dashboardDeviceCardStoreFactory.make(device.uniqueId) }) { store in
            cardContent(
                for: device,
                onFavoriteTapped: { store.send(.favoriteTapped) }
            )
        }
    }

    private func cardContent(
        for device: DashboardDeviceDescription,
        onFavoriteTapped: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Image(systemName: device.group.symbolName)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 36, height: 36)
                Spacer()
                FavoriteOrbButton(
                    isFavorite: true,
                    size: 32,
                    action: onFavoriteTapped
                )
            }

            Text(device.name)
                .font(.system(.headline, design: .rounded))
                .lineLimit(1)

            if device.group != .shutter && device.group != .light && device.group != .thermo && device.group != .boiler {
                Text(device.group.title)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            controlContent(for: device)
        }
        .padding(16)
        .frame(height: dashboardCardHeight, alignment: .top)
        .glassCard(cornerRadius: 22)
    }

    @ViewBuilder
    private func controlContent(for device: DashboardDeviceDescription) -> some View {
        switch device.group {
        case .shutter:
            ShutterView(uniqueId: device.uniqueId, layout: .regular)
        case .light:
            LightView(uniqueId: device.uniqueId)
        case .thermo:
            TemperatureView(uniqueId: device.uniqueId)
        case .boiler:
            ThermostatView(uniqueId: device.uniqueId)
        default:
            EmptyView()
        }
    }
}
