import Foundation

actor FavoriteRepository {
    private let deviceRepository: DeviceRepository
    private let groupRepository: GroupRepository
    private let sceneRepository: SceneRepository

    init(
        deviceRepository: DeviceRepository,
        groupRepository: GroupRepository,
        sceneRepository: SceneRepository
    ) {
        self.deviceRepository = deviceRepository
        self.groupRepository = groupRepository
        self.sceneRepository = sceneRepository
    }

    func observeAll() async -> some AsyncSequence<[FavoriteItem], Never> & Sendable {
        async let favoriteDevices = deviceRepository.observeFavorites()
        async let favoriteGroups = groupRepository.observeFavorites()
        async let favoriteScenes = sceneRepository.observeFavorites()

        return combineLatest(await favoriteDevices, await favoriteGroups, await favoriteScenes).map { devices, groups, scenes in
            Self.mergeFavorites(
                devices: devices,
                groups: groups,
                scenes: scenes
            )
        }
    }

    func listAll() async throws -> [FavoriteItem] {
        async let devices = deviceRepository.listAll()
        async let groups = groupRepository.listAll()
        async let scenes = sceneRepository.listAll()

        return Self.mergeFavorites(
            devices: try await devices,
            groups: try await groups,
            scenes: try await scenes
        )
    }

    func reorder(
        _ sourceType: FavoriteType,
        _ targetType: FavoriteType
    ) async throws {
        let snapshot = try await listAll()
        guard let reordered = Self.reorderedFavorites(
            snapshot,
            moving: sourceType,
            before: targetType
        ) else {
            return
        }

        var deviceOrders: [String: Int] = [:]
        var groupOrders: [String: Int] = [:]
        var sceneOrders: [String: Int] = [:]

        for (index, item) in reordered.enumerated() {
            switch item.type {
            case .device(let id):
                deviceOrders[id] = index
            case .group(let id, _):
                groupOrders[id] = index
            case .scene(let id):
                sceneOrders[id] = index
            }
        }

        try await deviceRepository.applyDashboardOrders(deviceOrders)
        try await groupRepository.applyDashboardOrders(groupOrders)
        try await sceneRepository.applyDashboardOrders(sceneOrders)
    }

    func setFavorite(_ favoriteType: FavoriteType, _ isFavorite: Bool) async throws {
        switch favoriteType {
        case .device(let deviceID):
            try await deviceRepository.setFavorite(deviceID, isFavorite)
        case .group(let groupID, _):
            try await groupRepository.setFavorite(groupID, isFavorite)
        case .scene(let sceneID):
            try await sceneRepository.setFavorite(sceneID, isFavorite)
        }
    }

    func removeFavorite(_ favoriteType: FavoriteType) async throws {
        try await setFavorite(favoriteType, false)
    }
    
    static func mergeFavorites(
        devices: [Device],
        groups: [Group],
        scenes: [Scene]
    ) -> [FavoriteItem] {
        let deviceFavoriteItems = devices.map {
            FavoriteItem(
                name: $0.name,
                usage: $0.resolvedUsage,
                type: .device(deviceId: $0.id),
                order: $0.dashboardOrder ?? 0
            )
        }
        
        let groupFavoriteItems = groups.map {
            FavoriteItem(
                name: $0.name,
                usage: $0.resolvedUsage,
                type: .group(groupId: $0.id, memberUniqueIds: $0.memberUniqueIds),
                order: $0.dashboardOrder ?? 0
            )
        }
        
        let sceneFavoriteItems = scenes.map {
            FavoriteItem(
                name: $0.name,
                usage: .scene,
                type: .scene(sceneId: $0.id),
                order: $0.dashboardOrder ?? 0
            )
        }
        
        let favorites = deviceFavoriteItems
        + groupFavoriteItems
        + sceneFavoriteItems
        
        return favorites.sorted(by: areFavoriteCandidatesOrderedAscending)
    }
    
    static func reorderedFavorites(
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
    
    private static func dashboardOrderValue(_ value: Int?) -> Int {
        value ?? Int.max
    }
    
    private static func sourcePriority(_ item: FavoriteItem) -> Int {
        switch item.type {
        case .device:
            return 0
        case .scene:
            return 1
        case .group:
            return 2
        }
    }
        
    private static func areFavoriteCandidatesOrderedAscending(
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
