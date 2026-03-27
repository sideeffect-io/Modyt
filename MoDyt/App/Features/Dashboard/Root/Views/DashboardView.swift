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

    var body: some View {
        WithStoreView(
            store: dashboardStoreFactory.make(),
        ) { store in
            GeometryReader { proxy in
                let headerMetrics = dashboardHeaderMetrics(for: proxy.size)

                dashboardContent(
                    store: store,
                    availableSize: CGSize(
                        width: proxy.size.width,
                        height: max(proxy.size.height - headerMetrics.reservedHeight, 0)
                    )
                )
                .safeAreaInset(edge: .top, spacing: 0) {
                    dashboardHeader(
                        store: store,
                        metrics: headerMetrics
                    )
                }
                .onChange(of: store.state.favorites.map(\.id)) { _, favoriteIDs in
                    if favoriteIDs.isEmpty {
                        exitEditMode()
                    } else if isEditing {
                        editAnimationVersion &+= 1
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
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
            .padding(.horizontal, metrics.layout.horizontalPadding)
            .padding(.vertical, metrics.layout.verticalPadding)
            .padding(.bottom, metrics.layout.bottomInset)
        } else if pagedFavorites.count == 1, let firstPage = pagedFavorites.first {
            favoritesPage(
                firstPage,
                store: store,
                metrics: metrics,
                bottomInset: metrics.layout.bottomInset
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
                        metrics: metrics,
                        bottomInset: metrics.contentBottomInset
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
        metrics: DashboardPaginationMetrics,
        bottomInset: CGFloat
    ) -> some View {
        LazyVGrid(columns: gridColumns(for: metrics), spacing: metrics.layout.gridSpacing) {
            ForEach(favorites, id: \.id) { favorite in
                favoriteTile(for: favorite, store: store)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, metrics.layout.horizontalPadding)
        .padding(.top, metrics.layout.verticalPadding)
        .padding(.bottom, bottomInset)
    }

    private func gridColumns(for metrics: DashboardPaginationMetrics) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: metrics.layout.gridSpacing),
            count: max(metrics.columnCount, 1)
        )
    }

    private func paginationMetrics(
        for availableSize: CGSize,
        favoriteCount: Int
    ) -> DashboardPaginationMetrics {
        DashboardPaginationMetrics.make(
            availableSize: availableSize,
            favoriteCount: favoriteCount,
            horizontalSizeClass: horizontalSizeClass
        )
    }

    private func dashboardHeaderMetrics(for availableSize: CGSize) -> DashboardHeaderMetrics {
        if horizontalSizeClass == .compact, availableSize.height > availableSize.width {
            return .compactPortrait
        }

        return .standard
    }

    private func dashboardHeader(
        store: DashboardStore,
        metrics: DashboardHeaderMetrics
    ) -> some View {
        HStack(spacing: 12) {
            Text("Dashboard")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                if isEditing == false {
                    dashboardHeaderIconButton(
                        systemName: "arrow.clockwise",
                        size: metrics.controlHeight
                    ) {
                        store.send(.refreshRequested)
                    }

                    dashboardHeaderDivider(height: metrics.controlHeight)
                }

                dashboardHeaderTextButton(
                    title: isEditing ? "Done" : "Edit",
                    height: metrics.controlHeight
                ) {
                    if isEditing {
                        exitEditMode()
                    } else {
                        enterEditMode()
                    }
                }
            }
            .glassCard(cornerRadius: metrics.controlHeight / 2, interactive: false, tone: .inset)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.top, metrics.topPadding)
        .padding(.bottom, metrics.bottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dashboardHeaderTextButton(
        title: String,
        height: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .padding(.horizontal, 12)
                .frame(height: height)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            title == "Done"
                ? "Done editing dashboard"
                : "Edit dashboard"
        )
    }

    private func dashboardHeaderIconButton(
        systemName: String,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: size, height: size)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Refresh dashboard")
    }

    private func dashboardHeaderDivider(height: CGFloat) -> some View {
        Rectangle()
            .fill(.white.opacity(0.3))
            .frame(width: 1, height: max(height - 12, 14))
            .padding(.vertical, 6)
            .accessibilityHidden(true)
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

struct DashboardPaginationMetrics {
    let layout: DashboardLayoutMetrics
    let columnCount: Int
    let rowCount: Int
    let showsPageIndicator: Bool

    var pageSize: Int {
        max(columnCount * rowCount, 1)
    }

    var contentBottomInset: CGFloat {
        layout.bottomInset + (showsPageIndicator ? layout.pageIndicatorInset : 0)
    }

    static func make(
        availableSize: CGSize,
        favoriteCount: Int,
        horizontalSizeClass: UserInterfaceSizeClass?
    ) -> DashboardPaginationMetrics {
        let standardMetrics = paginate(
            availableSize: availableSize,
            favoriteCount: favoriteCount,
            horizontalSizeClass: horizontalSizeClass,
            layout: .standard
        )

        guard isCompactPortrait(
            availableSize: availableSize,
            horizontalSizeClass: horizontalSizeClass
        ) else {
            return standardMetrics
        }

        let compactMetrics = paginate(
            availableSize: availableSize,
            favoriteCount: favoriteCount,
            horizontalSizeClass: horizontalSizeClass,
            layout: .compactPortrait
        )

        if compactMetrics.pageSize > standardMetrics.pageSize {
            return compactMetrics
        }

        return standardMetrics
    }

    private static func paginate(
        availableSize: CGSize,
        favoriteCount: Int,
        horizontalSizeClass: UserInterfaceSizeClass?,
        layout: DashboardLayoutMetrics
    ) -> DashboardPaginationMetrics {
        let columnCount = gridColumnCount(
            for: availableSize,
            horizontalSizeClass: horizontalSizeClass,
            layout: layout
        )
        let rowsWithoutPageIndicator = gridRowCount(
            for: availableSize,
            bottomInset: layout.bottomInset,
            layout: layout
        )
        let firstPassPageSize = max(columnCount * rowsWithoutPageIndicator, 1)
        let showsPageIndicator = favoriteCount > firstPassPageSize
        let rowCount = gridRowCount(
            for: availableSize,
            bottomInset: layout.bottomInset + (showsPageIndicator ? layout.pageIndicatorInset : 0),
            layout: layout
        )

        return DashboardPaginationMetrics(
            layout: layout,
            columnCount: columnCount,
            rowCount: rowCount,
            showsPageIndicator: showsPageIndicator
        )
    }

    private static func isCompactPortrait(
        availableSize: CGSize,
        horizontalSizeClass: UserInterfaceSizeClass?
    ) -> Bool {
        horizontalSizeClass == .compact && availableSize.height > availableSize.width
    }

    private static func gridColumnCount(
        for availableSize: CGSize,
        horizontalSizeClass: UserInterfaceSizeClass?,
        layout: DashboardLayoutMetrics
    ) -> Int {
        let contentWidth = max(availableSize.width - (layout.horizontalPadding * 2), 0)

        if availableSize.width > availableSize.height {
            let fittingColumnCount = max(
                1,
                Int((contentWidth + layout.gridSpacing) / (layout.landscapeMinimumCardWidth + layout.gridSpacing))
            )
            return min(4, fittingColumnCount)
        }

        if horizontalSizeClass == .compact {
            return 2
        }

        return max(
            1,
            Int((contentWidth + layout.gridSpacing) / (layout.landscapeMinimumCardWidth + layout.gridSpacing))
        )
    }

    private static func gridRowCount(
        for availableSize: CGSize,
        bottomInset: CGFloat,
        layout: DashboardLayoutMetrics
    ) -> Int {
        if availableSize.width > availableSize.height {
            return 3
        }

        let usableHeight = max(
            availableSize.height - (layout.verticalPadding * 2) - bottomInset,
            layout.cardVerticalFootprint
        )

        return max(
            1,
            Int((usableHeight + layout.gridSpacing) / (layout.cardVerticalFootprint + layout.gridSpacing))
        )
    }
}

struct DashboardLayoutMetrics {
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let gridSpacing: CGFloat
    let bottomInset: CGFloat
    let pageIndicatorInset: CGFloat
    let cardVerticalFootprint: CGFloat
    let landscapeMinimumCardWidth: CGFloat

    static let standard = DashboardLayoutMetrics(
        horizontalPadding: 18,
        verticalPadding: 24,
        gridSpacing: 18,
        bottomInset: 0,
        pageIndicatorInset: 24,
        cardVerticalFootprint: 196,
        landscapeMinimumCardWidth: 220
    )

    static let compactPortrait = DashboardLayoutMetrics(
        horizontalPadding: 16,
        verticalPadding: 16,
        gridSpacing: 12,
        bottomInset: 0,
        pageIndicatorInset: 16,
        cardVerticalFootprint: 196,
        landscapeMinimumCardWidth: 220
    )
}

struct DashboardHeaderMetrics {
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let controlHeight: CGFloat

    var reservedHeight: CGFloat {
        topPadding + controlHeight + bottomPadding
    }

    static let standard = DashboardHeaderMetrics(
        horizontalPadding: 18,
        topPadding: 6,
        bottomPadding: 6,
        controlHeight: 32
    )

    static let compactPortrait = DashboardHeaderMetrics(
        horizontalPadding: 16,
        topPadding: 4,
        bottomPadding: 4,
        controlHeight: 30
    )
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
