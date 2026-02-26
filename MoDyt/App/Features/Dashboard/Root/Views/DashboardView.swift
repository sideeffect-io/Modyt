import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @Environment(\.dashboardStoreFactory) private var dashboardStoreFactory
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var dragSource: FavoriteType?
    @State private var dropTarget: FavoriteType?

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
        let favorites = store.state.favorites
        let favoriteIDs = favorites.map(\.id)

        VStack(alignment: .leading, spacing: 12) {
            if favorites.isEmpty {
                ContentUnavailableView(
                    "No Favorites Yet",
                    systemImage: "star",
                    description: Text("Mark devices, scenes, or groups as favorites to pin them here.")
                )
                .padding(.vertical, 24)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 18) {
                    ForEach(favorites, id: \.id) { favorite in
                        favoriteTile(for: favorite, store: store)
                    }
                }
                .animation(.easeInOut(duration: 0.28), value: favoriteIDs)
            }
        }
    }

    private func favoriteTile(for favorite: FavoriteItem, store: DashboardStore) -> some View {
        DashboardDeviceCardView(favorite: favorite)
        .padding(1)
        .transition(
            AnyTransition.asymmetric(
                insertion: .identity,
                removal: .opacity.combined(with: .scale(scale: 0.92))
            )
        )
        .overlay {
            if dropTarget == favorite.type {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(.white.opacity(0.6), lineWidth: 2)
            }
        }
        .overlay(alignment: .topTrailing) {
            if dropTarget == favorite.type {
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
            }
        }
        .onDrag {
            dragSource = favorite.type
            return NSItemProvider(object: favorite.id as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: DashboardCardDropDelegate(
                target: favorite.type,
                dragSource: $dragSource,
                dropTarget: $dropTarget,
                onReorder: { source, target in
                    store.send(.reorderFavorite(source, target))
                }
            )
        )
    }
}

private struct DashboardCardDropDelegate: DropDelegate {
    let target: FavoriteType
    @Binding var dragSource: FavoriteType?
    @Binding var dropTarget: FavoriteType?
    let onReorder: (FavoriteType, FavoriteType) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func dropEntered(info: DropInfo) {
        guard dragSource != target else { return }
        dropTarget = target
    }

    func dropExited(info: DropInfo) {
        guard dropTarget == target else { return }
        dropTarget = nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            dropTarget = nil
            dragSource = nil
        }

        guard let source = dragSource, source != target else { return false }
        onReorder(source, target)
        return true
    }
}
