import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct DashboardView: View {
    @Environment(\.dashboardStoreFactory) private var dashboardStoreFactory
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var currentPage = 0
    @State private var isEditing = false
    @State private var editAnimationVersion = 0
    @State private var dragSource: FavoriteType?
    @State private var dropTarget: FavoriteType?

    private let dashboardHorizontalPadding: CGFloat = 18
    private let dashboardVerticalPadding: CGFloat = 24
    private let dashboardGridSpacing: CGFloat = 18
    private let dashboardBottomInset: CGFloat = 0
    private let dashboardPageIndicatorInset: CGFloat = 28
    private let dashboardCardVerticalFootprint: CGFloat = 196
    private let landscapeMinimumCardWidth: CGFloat = 220

    var body: some View {
        WithStoreView(
            store: dashboardStoreFactory.make(),
        ) { store in
            GeometryReader { proxy in
                dashboardContent(
                    store: store,
                    availableSize: proxy.size
                )
                .onChange(of: store.state.favorites.map(\.id)) { _, favoriteIDs in
                    if favoriteIDs.isEmpty {
                        exitEditMode()
                    } else if isEditing {
                        editAnimationVersion &+= 1
                    }
                }
                .navigationTitle("Dashboard")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(isEditing ? "Done" : "Edit") {
                            if isEditing {
                                exitEditMode()
                            } else {
                                enterEditMode()
                            }
                        }
                        .accessibilityLabel(isEditing ? "Done editing dashboard" : "Edit dashboard")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        if isEditing == false {
                            Button {
                                store.send(.refreshRequested)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .accessibilityLabel("Refresh dashboard")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dashboardContent(
        store: DashboardStore,
        availableSize: CGSize
    ) -> some View {
        let favorites = store.state.favorites
        let favoriteIDs = favorites.map(\.id)
        let metrics = paginationMetrics(
            for: availableSize,
            favoriteCount: favorites.count
        )
        let pagedFavorites = favoritePages(
            favorites,
            pageSize: metrics.pageSize
        )

        if favorites.isEmpty {
            ContentUnavailableView(
                "No Favorites Yet",
                systemImage: "star",
                description: Text("Mark devices, scenes, or groups as favorites to pin them here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, dashboardHorizontalPadding)
            .padding(.vertical, dashboardVerticalPadding)
            .padding(.bottom, dashboardBottomInset)
        } else if pagedFavorites.count == 1, let firstPage = pagedFavorites.first {
            favoritesPage(
                firstPage,
                store: store,
                columnCount: metrics.columnCount,
                bottomInset: dashboardBottomInset
            )
            .animation(.easeInOut(duration: 0.28), value: favoriteIDs)
        } else {
            TabView(
                selection: Binding(
                    get: { min(currentPage, max(pagedFavorites.count - 1, 0)) },
                    set: { currentPage = $0 }
                )
            ) {
                ForEach(Array(pagedFavorites.enumerated()), id: \.offset) { index, page in
                    favoritesPage(
                        page,
                        store: store,
                        columnCount: metrics.columnCount,
                        bottomInset: dashboardBottomInset + dashboardPageIndicatorInset
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.easeInOut(duration: 0.28), value: favoriteIDs)
        }
    }

    private func favoritesPage(
        _ favorites: [FavoriteItem],
        store: DashboardStore,
        columnCount: Int,
        bottomInset: CGFloat
    ) -> some View {
        LazyVGrid(columns: gridColumns(for: columnCount), spacing: dashboardGridSpacing) {
            ForEach(favorites, id: \.id) { favorite in
                favoriteTile(for: favorite, store: store)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, dashboardHorizontalPadding)
        .padding(.top, dashboardVerticalPadding)
        .padding(.bottom, bottomInset)
    }

    private func gridColumns(for columnCount: Int) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: dashboardGridSpacing),
            count: max(columnCount, 1)
        )
    }

    private func paginationMetrics(
        for availableSize: CGSize,
        favoriteCount: Int
    ) -> DashboardPaginationMetrics {
        let columnCount = gridColumnCount(for: availableSize)
        let rowsWithoutPageIndicator = gridRowCount(
            for: availableSize,
            bottomInset: dashboardBottomInset
        )
        let firstPassPageSize = max(columnCount * rowsWithoutPageIndicator, 1)
        let showsPageIndicator = favoriteCount > firstPassPageSize
        let rowCount = gridRowCount(
            for: availableSize,
            bottomInset: dashboardBottomInset + (showsPageIndicator ? dashboardPageIndicatorInset : 0)
        )

        return DashboardPaginationMetrics(
            columnCount: columnCount,
            rowCount: rowCount
        )
    }

    private func gridColumnCount(for availableSize: CGSize) -> Int {
        let contentWidth = max(availableSize.width - (dashboardHorizontalPadding * 2), 0)

        if availableSize.width > availableSize.height {
            let fittingColumnCount = max(
                1,
                Int((contentWidth + dashboardGridSpacing) / (landscapeMinimumCardWidth + dashboardGridSpacing))
            )
            return min(4, fittingColumnCount)
        }

        if horizontalSizeClass == .compact {
            return 2
        }

        return max(
            1,
            Int((contentWidth + dashboardGridSpacing) / (landscapeMinimumCardWidth + dashboardGridSpacing))
        )
    }

    private func gridRowCount(
        for availableSize: CGSize,
        bottomInset: CGFloat
    ) -> Int {
        if availableSize.width > availableSize.height {
            return 3
        }

        let usableHeight = max(
            availableSize.height - (dashboardVerticalPadding * 2) - bottomInset,
            dashboardCardVerticalFootprint
        )

        return max(
            1,
            Int((usableHeight + dashboardGridSpacing) / (dashboardCardVerticalFootprint + dashboardGridSpacing))
        )
    }

    private func favoritePages(
        _ favorites: [FavoriteItem],
        pageSize: Int
    ) -> [[FavoriteItem]] {
        guard pageSize > 0, favorites.isEmpty == false else { return [] }

        return stride(from: 0, to: favorites.count, by: pageSize).map { startIndex in
            let endIndex = min(startIndex + pageSize, favorites.count)
            return Array(favorites[startIndex..<endIndex])
        }
    }

    private func baseFavoriteTile(for favorite: FavoriteItem) -> some View {
        DashboardDeviceCardView(
            favorite: favorite,
            isEditing: isEditing,
            editAnimationVersion: editAnimationVersion,
            onRequestEditMode: enterEditMode
        )
        .padding(1)
        .transition(
            AnyTransition.asymmetric(
                insertion: .identity,
                removal: .opacity.combined(with: .scale(scale: 0.92))
            )
        )
    }

    @ViewBuilder
    private func favoriteTile(for favorite: FavoriteItem, store: DashboardStore) -> some View {
        if isEditing {
            baseFavoriteTile(for: favorite)
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
        } else {
            baseFavoriteTile(for: favorite)
        }
    }

    private func enterEditMode() {
        guard isEditing == false else { return }

        dragSource = nil
        dropTarget = nil
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()

        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            isEditing = true
        }
    }

    private func exitEditMode() {
        guard isEditing else { return }

        dragSource = nil
        dropTarget = nil

        withAnimation(.easeInOut(duration: 0.18)) {
            isEditing = false
        }
    }
}

private struct DashboardPaginationMetrics {
    let columnCount: Int
    let rowCount: Int

    var pageSize: Int {
        max(columnCount * rowCount, 1)
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
