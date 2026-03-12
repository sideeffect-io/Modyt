import Foundation

struct FavoriteSourceSnapshot: Sendable, Equatable {
    let devices: [Device]
    let groups: [Group]
    let scenes: [Scene]
}

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

    func observeSourceSnapshot() async -> some AsyncSequence<FavoriteSourceSnapshot, Never> & Sendable {
        async let devices = deviceRepository.observeAll()
        async let groups = groupRepository.observeAll()
        async let scenes = sceneRepository.observeAll()

        return combineLatest(await devices, await groups, await scenes)
            .map { devices, groups, scenes in
                FavoriteSourceSnapshot(
                    devices: Self.filterFavorites(devices),
                    groups: Self.filterFavorites(groups),
                    scenes: Self.filterFavorites(scenes)
                )
            }
            .removeDuplicates()
    }

    func observeAll() async -> some AsyncSequence<[FavoriteItem], Never> & Sendable {
        let favoriteSources = await observeSourceSnapshot()

        return favoriteSources
            .map { sources in
                FavoriteItemsProjector.items(
                    devices: sources.devices,
                    groups: sources.groups,
                    scenes: sources.scenes
                )
            }
            .removeDuplicates()
    }

    func listSourceSnapshot() async throws -> FavoriteSourceSnapshot {
        async let devices = deviceRepository.listAll()
        async let groups = groupRepository.listAll()
        async let scenes = sceneRepository.listAll()

        return FavoriteSourceSnapshot(
            devices: Self.filterFavorites(try await devices),
            groups: Self.filterFavorites(try await groups),
            scenes: Self.filterFavorites(try await scenes)
        )
    }

    func listAll() async throws -> [FavoriteItem] {
        let favoriteSources = try await listSourceSnapshot()

        return FavoriteItemsProjector.items(
            devices: favoriteSources.devices,
            groups: favoriteSources.groups,
            scenes: favoriteSources.scenes
        )
    }

    func reorder(
        _ sourceType: FavoriteType,
        _ targetType: FavoriteType
    ) async throws {
        let snapshot = try await listAll()
        guard let reordered = FavoriteItemsProjector.reordered(
            snapshot,
            moving: sourceType,
            before: targetType
        ) else {
            return
        }

        var deviceOrders: [DeviceIdentifier: Int] = [:]
        var groupOrders: [String: Int] = [:]
        var sceneOrders: [String: Int] = [:]

        for (index, item) in reordered.enumerated() {
            switch item.type {
            case .device(let identifier):
                deviceOrders[identifier] = index
            case .group(let id, _):
                groupOrders[id] = index
            case .scene(let id):
                sceneOrders[id] = index
            }
        }

        let deviceOrderMap = deviceOrders
        let groupOrderMap = groupOrders
        let sceneOrderMap = sceneOrders

        try await deviceRepository.mutateByIDs(Array(deviceOrderMap.keys)) { device in
            guard device.isFavorite,
                  let order = deviceOrderMap[device.id] else {
                return
            }
            device.dashboardOrder = order
        }

        try await groupRepository.mutateByIDs(Array(groupOrderMap.keys)) { group in
            guard group.isFavorite,
                  let order = groupOrderMap[group.id] else {
                return
            }
            group.dashboardOrder = order
        }

        try await sceneRepository.mutateByIDs(Array(sceneOrderMap.keys)) { scene in
            guard scene.isFavorite,
                  let order = sceneOrderMap[scene.id] else {
                return
            }
            scene.dashboardOrder = order
        }
    }

    func toggleFavorite(_ favoriteType: FavoriteType) async throws {
        switch favoriteType {
        case .device(let identifier):
            try await toggleDeviceFavorite(identifier)
        case .group(let groupID, _):
            try await toggleGroupFavorite(groupID)
        case .scene(let sceneID):
            try await toggleSceneFavorite(sceneID)
        }
    }

    func removeFavorite(_ favoriteType: FavoriteType) async throws {
        switch favoriteType {
        case .device(let identifier):
            try await removeDeviceFavorite(identifier)
        case .group(let groupID, _):
            try await removeGroupFavorite(groupID)
        case .scene(let sceneID):
            try await removeSceneFavorite(sceneID)
        }
    }

    func toggleDeviceFavorite(_ identifier: DeviceIdentifier) async throws {
        guard let device = try await deviceRepository.get(identifier) else {
            return
        }

        if device.isFavorite {
            try await removeDeviceFavorite(identifier)
            return
        }

        let order = try await nextDashboardOrder()
        try await deviceRepository.mutateByIDs([identifier]) { device in
            device.isFavorite = true
            device.dashboardOrder = order
        }
    }

    func toggleGroupFavorite(_ groupID: String) async throws {
        guard let group = try await groupRepository.get(groupID) else {
            return
        }

        if group.isFavorite {
            try await removeGroupFavorite(groupID)
            return
        }

        let order = try await nextDashboardOrder()
        try await groupRepository.mutateByIDs([groupID]) { group in
            group.isFavorite = true
            group.dashboardOrder = order
        }
    }

    func toggleSceneFavorite(_ sceneID: String) async throws {
        guard let scene = try await sceneRepository.get(sceneID) else {
            return
        }

        if scene.isFavorite {
            try await removeSceneFavorite(sceneID)
            return
        }

        let order = try await nextDashboardOrder()
        try await sceneRepository.mutateByIDs([sceneID]) { scene in
            scene.isFavorite = true
            scene.dashboardOrder = order
        }
    }

    func removeDeviceFavorite(_ identifier: DeviceIdentifier) async throws {
        try await deviceRepository.mutateByIDs([identifier]) { device in
            device.isFavorite = false
            device.dashboardOrder = nil
        }
    }

    func removeGroupFavorite(_ groupID: String) async throws {
        try await groupRepository.mutateByIDs([groupID]) { group in
            group.isFavorite = false
            group.dashboardOrder = nil
        }
    }

    func removeSceneFavorite(_ sceneID: String) async throws {
        try await sceneRepository.mutateByIDs([sceneID]) { scene in
            scene.isFavorite = false
            scene.dashboardOrder = nil
        }
    }

    private func nextDashboardOrder() async throws -> Int {
        let snapshot = try await listSourceSnapshot()
        let maxOrder = [
            snapshot.devices.compactMap(\.dashboardOrder).max(),
            snapshot.groups.compactMap(\.dashboardOrder).max(),
            snapshot.scenes.compactMap(\.dashboardOrder).max(),
        ]
        .compactMap { $0 }
        .max() ?? -1

        return maxOrder + 1
    }

    private static func filterFavorites<Item: DomainType>(_ items: [Item]) -> [Item] {
        items.filter(\.isFavorite)
    }
}
