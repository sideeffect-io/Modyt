import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @Environment(\.dashboardStoreFactory) private var dashboardStoreFactory
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var dragSourceId: String?
    @State private var dropTargetId: String?

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
                    description: Text("Mark devices, scenes, or groups as favorites to pin them here.")
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
            if dropTargetId == device.uniqueId {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(.white.opacity(0.6), lineWidth: 2)
            }
        }
        .overlay(alignment: .topTrailing) {
            if dropTargetId == device.uniqueId {
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
            }
        }
        .onDrag {
            dragSourceId = device.uniqueId
            return NSItemProvider(object: device.uniqueId as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: DashboardCardDropDelegate(
                targetId: device.uniqueId,
                dragSourceId: $dragSourceId,
                dropTargetId: $dropTargetId,
                onReorder: { sourceId, targetId in
                    store.send(.reorderFavorite(sourceId, targetId))
                }
            )
        )
    }
}

private struct DashboardCardDropDelegate: DropDelegate {
    let targetId: String
    @Binding var dragSourceId: String?
    @Binding var dropTargetId: String?
    let onReorder: (String, String) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func dropEntered(info: DropInfo) {
        guard dragSourceId != targetId else { return }
        dropTargetId = targetId
    }

    func dropExited(info: DropInfo) {
        guard dropTargetId == targetId else { return }
        dropTargetId = nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            dropTargetId = nil
            dragSourceId = nil
        }

        guard let sourceId = dragSourceId, sourceId != targetId else { return false }
        onReorder(sourceId, targetId)
        return true
    }
}
