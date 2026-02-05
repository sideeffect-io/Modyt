import SwiftUI

struct DashboardView: View {
    @Bindable var store: AppStore
    @State private var draggedId: String?

    private var favorites: [DeviceRecord] {
        store.state.favorites
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                summaryCard
                favoritesSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .navigationTitle("Dashboard")
        .refreshable {
            store.send(.refreshRequested)
        }
    }

    private var summaryCard: some View {
        let total = store.state.devices.count
        let favoriteCount = store.state.favorites.count
        let groupCount = store.state.groupedDevices.count

        return VStack(alignment: .leading, spacing: 16) {
            Text("Home Overview")
                .font(.system(.title2, design: .rounded).weight(.semibold))

            HStack(spacing: 16) {
                summaryPill(title: "Devices", value: "\(total)")
                summaryPill(title: "Favorites", value: "\(favoriteCount)")
                summaryPill(title: "Types", value: "\(groupCount)")
            }

            Button {
                store.send(.refreshRequested)
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh All")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .glassCard(cornerRadius: 26)
    }

    private func summaryPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassCard(cornerRadius: 16, interactive: false)
    }

    @ViewBuilder
    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Favorites")
                .font(.system(.title3, design: .rounded).weight(.semibold))

            if favorites.isEmpty {
                ContentUnavailableView(
                    "No Favorites Yet",
                    systemImage: "star",
                    description: Text("Mark devices as favorites in the Devices tab.")
                )
                .padding(.vertical, 24)
            } else {
                let columns = [GridItem(.adaptive(minimum: 170), spacing: 16)]
                if #available(iOS 26.0, macOS 26.0, *) {
                    GlassEffectContainer(spacing: 18) {
                        LazyVGrid(columns: columns, spacing: 16) {
                            favoritesGrid
                        }
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        favoritesGrid
                    }
                }
            }
        }
    }

    private var favoritesGrid: some View {
        ForEach(favorites) { device in
            let targetStep = store.state.shutterTargetStep(for: device)
            let actualStep = store.state.shutterActualStep(for: device)
            DeviceTile(
                device: device,
                shutterTargetStep: targetStep,
                shutterActualStep: actualStep,
                onToggleFavorite: { store.send(.toggleFavorite(device.uniqueId)) },
                onControlChange: { key, value in
                    store.send(.deviceControlChanged(uniqueId: device.uniqueId, key: key, value: value))
                }
            )
            .overlay {
                if draggedId == device.uniqueId {
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(.white.opacity(0.6), lineWidth: 2)
                }
            }
            .draggable(device.uniqueId)
            .dropDestination(for: String.self) { items, _ in
                guard let sourceId = items.first else { return false }
                store.send(.reorderFavorite(sourceId, device.uniqueId))
                return true
            } isTargeted: { isTargeted in
                draggedId = isTargeted ? device.uniqueId : nil
            }
        }
    }
}
