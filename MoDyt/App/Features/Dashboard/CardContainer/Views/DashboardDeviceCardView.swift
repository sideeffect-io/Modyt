import SwiftUI
import UIKit

struct DashboardDeviceCardView: View {
    @Environment(\.dashboardDeviceCardStoreFactory) private var dashboardDeviceCardStoreFactory

    let favorite: FavoriteItem

    private let dashboardCardHeight: CGFloat = 194

    var body: some View {
        WithStoreView(factory: { dashboardDeviceCardStoreFactory.make(favorite.type) }) { store in
            cardContent(
                for: favorite,
                onFavoriteTapped: { store.send(.favoriteTapped) }
            )
        }
    }

    @ViewBuilder
    private func cardContent(
        for favorite: FavoriteItem,
        onFavoriteTapped: @escaping () -> Void
    ) -> some View {
        if favorite.isScene {
            sceneCardContent(for: favorite, onFavoriteTapped: onFavoriteTapped)
        } else {
            deviceCardContent(for: favorite, onFavoriteTapped: onFavoriteTapped)
        }
    }

    private func sceneCardContent(
        for favorite: FavoriteItem,
        onFavoriteTapped: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(
                for: favorite,
                titleLineLimit: 2,
                onFavoriteTapped: onFavoriteTapped
            )

            Spacer(minLength: 0)

            SceneExecutionView(uniqueId: favorite.sceneExecutionUniqueId)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(16)
        .frame(height: dashboardCardHeight, alignment: .top)
        .glassCard(cornerRadius: 22)
    }

    private func deviceCardContent(
        for favorite: FavoriteItem,
        onFavoriteTapped: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(
                for: favorite,
                titleLineLimit: 1,
                onFavoriteTapped: onFavoriteTapped
            )

            if let passiveLabel = passiveBodyLabel(for: favorite) {
                Text(passiveLabel)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            controlContent(for: favorite)
        }
        .padding(16)
        .frame(height: dashboardCardHeight, alignment: .top)
        .glassCard(cornerRadius: 22)
    }

    private func cardHeader(
        for favorite: FavoriteItem,
        titleLineLimit: Int,
        onFavoriteTapped: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: iconSystemName(for: favorite))
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 36, height: 36)

            Text(favorite.name)
                .font(.system(.headline, design: .rounded))
                .lineLimit(titleLineLimit)
                .minimumScaleFactor(0.9)
                .frame(maxWidth: .infinity, alignment: .leading)

            FavoriteOrbButton(
                isFavorite: true,
                size: 32,
                action: onFavoriteTapped
            )
        }
    }

    private func iconSystemName(for favorite: FavoriteItem) -> String {
        if favorite.isScene {
            return sceneSymbolName(picto: nil, type: nil)
        }

        switch favorite.group {
        case .boiler:
            return isHeatPumpDevice(favorite) ? "heat.waves" : "thermometer"
        case .weather:
            return "sun.max.fill"
        case .smoke:
            return smokeSymbolName()
        default:
            return favorite.group.symbolName
        }
    }

    @ViewBuilder
    private func controlContent(for favorite: FavoriteItem) -> some View {
        if supportsActiveControls(for: favorite) {
            switch favorite.group {
            case .shutter:
                if favorite.shutterUniqueIds.isEmpty {
                    Text("Shutters unavailable")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    ShutterView(
                        shutterUniqueIds: favorite.shutterUniqueIds,
                        layout: .regular
                    )
                }
            case .light:
                LightView(uniqueId: favorite.controlUniqueId)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            case .thermo:
                TemperatureView(uniqueId: favorite.controlUniqueId)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            case .boiler:
                if isHeatPumpDevice(favorite) {
                    HeatPumpView(uniqueId: favorite.controlUniqueId)
                } else {
                    ThermostatView(uniqueId: favorite.controlUniqueId)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            case .weather:
                SunlightView(uniqueId: favorite.controlUniqueId)
            case .energy:
                EnergyConsumptionView(uniqueId: favorite.controlUniqueId)
            case .smoke:
                SmokeView(uniqueId: favorite.controlUniqueId)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            default:
                EmptyView()
            }
        } else {
            EmptyView()
        }
    }

    private func supportsActiveControls(for favorite: FavoriteItem) -> Bool {
        if favorite.isGroup {
            return favorite.usage == .light || favorite.usage == .shutter
        }

        switch favorite.group {
        case .shutter, .light, .thermo, .boiler, .weather, .energy, .smoke:
            return true
        default:
            return false
        }
    }

    private func passiveBodyLabel(for favorite: FavoriteItem) -> String? {
        guard !supportsActiveControls(for: favorite) else { return nil }
        if favorite.isGroup {
            return favorite.usage.rawValue.capitalized
        }
        return favorite.group.title
    }

    private func smokeSymbolName() -> String {
        let preferredSymbols = [
            "fire.extinguisher.fill",
            "sensor.fill",
            "flame.fill"
        ]

        for symbol in preferredSymbols where UIImage(systemName: symbol) != nil {
            return symbol
        }

        return "exclamationmark.triangle.fill"
    }

    private func isHeatPumpDevice(_ favorite: FavoriteItem) -> Bool {
        let usage = favorite.usage.rawValue.lowercased()
        if usage == "sh_hvac" || usage == "aeraulic" || usage.contains("hvac") {
            return true
        }

        let name = favorite.name.lowercased()
        return name.localizedStandardContains("pompe")
            || name.localizedStandardContains("heat pump")
    }
}
