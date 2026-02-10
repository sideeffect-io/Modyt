import SwiftUI
import DeltaDoreClient

struct DashboardView: View {
    @Environment(\.dashboardStoreFactory) private var dashboardStoreFactory
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var draggedId: String?

    var body: some View {
        WithStoreView(factory: dashboardStoreFactory.make) { store in
            ScrollView {
                VStack(spacing: 22) {
                    favoritesSection(store: store)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 24)
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 74)
            }
            .navigationTitle("Dashboard")
            .task {
                store.send(.onAppear)
            }
            .refreshable {
                store.send(.refreshRequested)
            }
        }
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

    @ViewBuilder
    private func favoritesSection(store: DashboardStore) -> some View {
        let favoriteDevices = store.state.favoriteDevices
        let favoriteIDs = favoriteDevices.map(\.uniqueId)

        VStack(alignment: .leading, spacing: 12) {
            if favoriteDevices.isEmpty {
                ContentUnavailableView(
                    "No Favorites Yet",
                    systemImage: "star",
                    description: Text("Mark devices as favorites in the Devices tab.")
                )
                .padding(.vertical, 24)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 18) {
                    ForEach(favoriteDevices, id: \.uniqueId) { device in
                        favoriteTile(for: device, store: store)
                    }
                }
                .animation(.easeInOut(duration: 0.28), value: favoriteIDs)
            }
        }
    }

    private func favoriteTile(for device: DashboardDeviceDescription, store: DashboardStore) -> some View {
        DashboardDeviceCardView(device: device)
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
