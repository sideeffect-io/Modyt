import SwiftUI
import UIKit

struct DashboardDeviceCardView: View {
    @Environment(\.dashboardDeviceCardStoreDependencies) private var dashboardDeviceCardStoreDependencies
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let favorite: FavoriteItem

    @ScaledMetric(relativeTo: .body) private var dashboardCardMinHeight: CGFloat = 194
    @ScaledMetric(relativeTo: .title3) private var cardIconSize: CGFloat = 22
    @ScaledMetric(relativeTo: .title3) private var cardIconFrame: CGFloat = 36

    var body: some View {
        WithStoreView(
            store: DashboardDeviceCardStore(
                dependencies: dashboardDeviceCardStoreDependencies,
                favoriteType: favorite.type
            ),
        ) { store in
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
        .frame(minHeight: dashboardCardMinHeight, alignment: .top)
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
        .frame(minHeight: dashboardCardMinHeight, alignment: .top)
        .glassCard(cornerRadius: 22)
    }

    private func cardHeader(
        for favorite: FavoriteItem,
        titleLineLimit: Int,
        onFavoriteTapped: @escaping () -> Void
    ) -> some View {
        let effectiveTitleLineLimit = dynamicTypeSize.isAccessibilitySize
            ? max(titleLineLimit, 2)
            : titleLineLimit

        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: iconSystemName(for: favorite))
                .font(.system(size: cardIconSize, weight: .semibold))
                .frame(width: cardIconFrame, height: cardIconFrame)

            Text(favorite.name)
                .font(.system(.headline, design: .rounded))
                .lineLimit(effectiveTitleLineLimit)
                .minimumScaleFactor(0.9)
                .frame(maxWidth: .infinity, alignment: .leading)

            FavoriteOrbButton(
                isFavorite: true,
                size: 32,
                accessibilityContext: favorite.name,
                action: onFavoriteTapped
            )
        }
    }

    private func iconSystemName(for favorite: FavoriteItem) -> String {
        if favorite.isScene {
            return sceneSymbolName(picto: nil, type: nil)
        }

        switch favorite.controlKind {
        case .heatPump:
            return "heat.waves"
        case .thermostat:
            return "thermometer"
        case .temperature:
            return "thermometer.medium"
        case .sunlight:
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
            switch favorite.controlKind {
            case .shutter:
                switch DashboardShutterRoute(favorite: favorite) {
                case .unavailable:
                    Text("Shutters unavailable")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                case .single(let deviceId):
                    SingleShutterView(
                        deviceId: deviceId
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                case .group(let deviceIds):
                    GroupShutterView(
                        deviceIds: deviceIds
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            case .light:
                if let identifier = favorite.controlDeviceIdentifier {
                    LightView(identifier: identifier)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    Text("Lights unavailable")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            case .temperature:
                if let identifier = favorite.controlDeviceIdentifier {
                    TemperatureView(identifier: identifier)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            case .thermostat:
                if let identifier = favorite.controlDeviceIdentifier {
                    ThermostatView(identifier: identifier)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            case .heatPump:
                if let identifier = favorite.controlDeviceIdentifier {
                    HeatPumpView(identifier: identifier)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            case .sunlight:
                if let identifier = favorite.controlDeviceIdentifier {
                    SunlightView(identifier: identifier)
                }
            case .energyConsumption:
                if let identifier = favorite.controlDeviceIdentifier {
                    EnergyConsumptionView(identifier: identifier)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            case .smoke:
                if let identifier = favorite.controlDeviceIdentifier {
                    SmokeView(identifier: identifier)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            default:
                EmptyView()
            }
        } else {
            EmptyView()
        }
    }

    private func supportsActiveControls(for favorite: FavoriteItem) -> Bool {
        if favorite.isGroup {
            return favorite.controlKind == .light || favorite.controlKind == .shutter
        }

        switch favorite.controlKind {
        case .shutter, .light, .temperature, .thermostat, .heatPump, .sunlight, .energyConsumption, .smoke:
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
}
