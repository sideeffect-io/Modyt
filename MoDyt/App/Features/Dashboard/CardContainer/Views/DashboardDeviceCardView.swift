import SwiftUI
import UIKit

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

    @ViewBuilder
    private func cardContent(
        for device: DashboardDeviceDescription,
        onFavoriteTapped: @escaping () -> Void
    ) -> some View {
        if device.isScene {
            sceneCardContent(for: device, onFavoriteTapped: onFavoriteTapped)
        } else {
            deviceCardContent(for: device, onFavoriteTapped: onFavoriteTapped)
        }
    }

    private func sceneCardContent(
        for device: DashboardDeviceDescription,
        onFavoriteTapped: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Image(systemName: iconSystemName(for: device))
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
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(height: dashboardCardHeight, alignment: .top)
        .glassCard(cornerRadius: 22)
    }

    private func deviceCardContent(
        for device: DashboardDeviceDescription,
        onFavoriteTapped: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Image(systemName: iconSystemName(for: device))
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

            if device.group != .shutter
                && device.group != .light
                && device.group != .thermo
                && device.group != .boiler
                && device.group != .smoke
                && device.group != .weather
                && device.group != .energy {
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

    private func iconSystemName(for device: DashboardDeviceDescription) -> String {
        if device.isScene {
            return sceneSymbolName(picto: device.scenePicto, type: device.sceneType)
        }

        switch device.group {
        case .boiler:
            return isHeatPumpDevice(device) ? "heat.waves" : "thermometer"
        case .weather:
            return "sun.max.fill"
        case .smoke:
            return smokeSymbolName()
        default:
            return device.group.symbolName
        }
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
            if isHeatPumpDevice(device) {
                HeatPumpView(uniqueId: device.uniqueId)
            } else {
                ThermostatView(uniqueId: device.uniqueId)
            }
        case .weather:
            SunlightView(uniqueId: device.uniqueId)
        case .energy:
            EnergyConsumptionView(uniqueId: device.uniqueId)
        case .smoke:
            SmokeView(uniqueId: device.uniqueId)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        default:
            EmptyView()
        }
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

    private func isHeatPumpDevice(_ device: DashboardDeviceDescription) -> Bool {
        let usage = device.usage.lowercased()
        if usage == "sh_hvac" || usage == "aeraulic" || usage.contains("hvac") {
            return true
        }

        let name = device.name.lowercased()
        return name.localizedStandardContains("pompe")
            || name.localizedStandardContains("heat pump")
    }
}
