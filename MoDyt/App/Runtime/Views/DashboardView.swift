import SwiftUI

struct DashboardView: View {
    @Bindable var store: RuntimeStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var draggedId: String?

    private var favorites: [DeviceRecord] {
        store.state.favorites
    }

    private var favoriteIDs: [String] {
        favorites.map(\.uniqueId)
    }

    private var gridColumns: [GridItem] {
        if horizontalSizeClass == .compact {
            return [
                GridItem(.flexible(minimum: 0), spacing: 18),
                GridItem(.flexible(minimum: 0), spacing: 18)
            ]
        }
        return [GridItem(.adaptive(minimum: 220), spacing: 18)]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                favoritesSection
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 24)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 74)
        }
        .navigationTitle("Dashboard")
        .refreshable {
            store.send(.refreshRequested)
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if favorites.isEmpty {
                ContentUnavailableView(
                    "No Favorites Yet",
                    systemImage: "star",
                    description: Text("Mark devices as favorites in the Devices tab.")
                )
                .padding(.vertical, 24)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 18) {
                    favoritesGrid
                }
                .animation(.easeInOut(duration: 0.28), value: favoriteIDs)
            }
        }
    }

    private var favoritesGrid: some View {
        ForEach(favorites) { device in
            favoriteTile(for: device)
        }
    }

    private func favoriteTile(for device: DeviceRecord) -> some View {
        let tile = DeviceTile(
            device: device,
            shutterRepository: store.shutterRepository,
            onToggleFavorite: { store.send(.toggleFavorite(device.uniqueId)) },
            onControlChange: { key, value in
                store.send(.deviceControlChanged(uniqueId: device.uniqueId, key: key, value: value))
            }
        )

        return tile
            .padding(1)
            .transition(
                AnyTransition.asymmetric(
                    insertion: .identity,
                    removal: .opacity.combined(with: .scale(scale: 0.92))
                )
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
