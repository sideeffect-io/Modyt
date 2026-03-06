import SwiftUI

struct DevicesView: View {
    @Environment(\.devicesStoreDependencies) private var devicesStoreDependencies

    var body: some View {
        WithStoreView(
            store: DevicesStore(dependencies: devicesStoreDependencies),
        ) { store in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    listHeader
                        .padding(.horizontal, 2)

                    ForEach(store.state.groupedDevices, id: \.usage.rawValue) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader(section)

                            LazyVStack(spacing: 10) {
                                ForEach(section.items, id: \.id) { device in
                                    DeviceRow(
                                        device: device,
                                        onToggleFavorite: { store.send(.toggleFavorite(device.id)) }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .navigationTitle("Devices")
            .refreshable {
                store.send(.refreshRequested)
            }
        }
    }

    private var listHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Device Library")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text("Browse all connected devices by category and star the ones you want on the dashboard.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppColors.sunrise.opacity(0.35),
                            AppColors.aurora.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .glassCard(cornerRadius: 24, interactive: false)
    }

    private func sectionHeader(_ section: RepositoryDeviceTypeSection) -> some View {
        let favoritesInSection = section.items.filter(\.isFavorite).count

        return HStack(spacing: 8) {
            Label {
                Text(section.usage.title)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
            } icon: {
                Image(systemName: section.usage.symbolName)
                    .font(.system(size: 15, weight: .bold))
            }

            Spacer()

            Text("\(section.items.count)")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.12), in: Capsule())

            if favoritesInSection > 0 {
                Label("\(favoritesInSection)", systemImage: "star.fill")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(Color.yellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.yellow.opacity(0.15), in: Capsule())
            }
        }
    }
}

private extension Usage {
    var title: String {
        switch self {
        case .shutter: return "Shutters"
        case .window: return "Windows"
        case .door: return "Doors"
        case .garage: return "Garage"
        case .gate: return "Gates"
        case .light: return "Lights"
        case .energy: return "Energy"
        case .smoke: return "Smoke"
        case .boiler: return "Boilers"
        case .alarm: return "Alarm"
        case .weather: return "Weather"
        case .water: return "Water"
        case .thermo: return "Thermo"
        case .scene: return "Scenes"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .shutter: return "window.horizontal"
        case .window: return "rectangle.portrait"
        case .door: return "door.left.hand.open"
        case .garage: return "car"
        case .gate: return "square.split.2x2"
        case .light: return "lightbulb"
        case .energy: return "bolt"
        case .smoke: return "smoke"
        case .boiler: return "thermometer"
        case .alarm: return "shield.lefthalf.filled"
        case .weather: return "cloud.sun"
        case .water: return "drop"
        case .thermo: return "thermometer.medium"
        case .scene: return "play.rectangle"
        case .other: return "square.dashed"
        }
    }
}
