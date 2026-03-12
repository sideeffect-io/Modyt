import Foundation

enum FavoriteItemsProjector {
    nonisolated static func items(
        devices: [Device],
        groups: [Group],
        scenes: [Scene]
    ) -> [FavoriteItem] {
        let deviceFavoriteItems = devices.map {
            FavoriteItem(
                name: $0.name,
                usage: $0.resolvedUsage,
                type: .device(identifier: $0.id),
                order: $0.dashboardOrder ?? 0,
                controlKind: $0.controlKind,
                rawUsage: $0.usage
            )
        }

        let groupFavoriteItems = groups.map {
            FavoriteItem(
                name: $0.name,
                usage: $0.resolvedUsage,
                type: .group(groupId: $0.id, memberIdentifiers: $0.memberIdentifiers),
                order: $0.dashboardOrder ?? 0,
                controlKind: FavoriteControlKind.from(usage: $0.resolvedUsage),
                rawUsage: $0.usage
            )
        }

        let sceneFavoriteItems = scenes.map {
            FavoriteItem(
                name: $0.name,
                usage: .scene,
                type: .scene(sceneId: $0.id),
                order: $0.dashboardOrder ?? 0,
                controlKind: .scene,
                rawUsage: "scene"
            )
        }

        let favorites = deviceFavoriteItems + groupFavoriteItems + sceneFavoriteItems
        return favorites.sorted(by: areOrderedAscending)
    }

    nonisolated static func reordered(
        _ values: [FavoriteItem],
        moving sourceType: FavoriteType,
        before targetType: FavoriteType
    ) -> [FavoriteItem]? {
        guard let sourceIndex = values.firstIndex(where: { $0.id == sourceType.id }),
              let targetIndex = values.firstIndex(where: { $0.id == targetType.id }),
              sourceIndex != targetIndex else {
            return nil
        }

        var reordered = values
        let moved = reordered.remove(at: sourceIndex)
        reordered.insert(moved, at: targetIndex)
        return reordered
    }

    private nonisolated static func dashboardOrderValue(_ value: Int?) -> Int {
        value ?? Int.max
    }

    private nonisolated static func sourcePriority(_ item: FavoriteItem) -> Int {
        switch item.type {
        case .device:
            return 0
        case .scene:
            return 1
        case .group:
            return 2
        }
    }

    private nonisolated static func areOrderedAscending(
        _ lhs: FavoriteItem,
        _ rhs: FavoriteItem
    ) -> Bool {
        let lhsOrder = dashboardOrderValue(lhs.order)
        let rhsOrder = dashboardOrderValue(rhs.order)
        if lhsOrder != rhsOrder {
            return lhsOrder < rhsOrder
        }

        let lhsItem = sourcePriority(lhs)
        let rhsItem = sourcePriority(rhs)
        if lhsItem != rhsItem {
            return lhsItem < rhsItem
        }

        let nameCompare = lhs.name.localizedStandardCompare(rhs.name)
        if nameCompare != .orderedSame {
            return nameCompare == .orderedAscending
        }

        return lhs.id < rhs.id
    }
}
