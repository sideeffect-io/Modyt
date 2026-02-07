import SwiftUI

struct DevicesView: View {
    @Bindable var store: RuntimeStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                listHeader
                    .padding(.horizontal, 2)

                ForEach(store.state.groupedDevices) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader(section)

                        LazyVStack(spacing: 10) {
                            ForEach(section.devices) { device in
                                DeviceRow(
                                    device: device,
                                    onToggleFavorite: { store.send(.toggleFavorite(device.uniqueId)) }
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

    private func sectionHeader(_ section: DeviceGroupSection) -> some View {
        let favoritesInSection = section.devices.filter(\.isFavorite).count

        return HStack(spacing: 8) {
            Label {
                Text(section.group.title)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
            } icon: {
                Image(systemName: section.group.symbolName)
                    .font(.system(size: 15, weight: .bold))
            }

            Spacer()

            Text("\(section.devices.count)")
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
