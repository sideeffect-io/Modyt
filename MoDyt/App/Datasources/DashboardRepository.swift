import Foundation

actor DashboardRepository {
    private let deviceRepository: DeviceRepository
    private let sceneRepository: SceneRepository
    private let groupRepository: GroupRepository

    init(
        deviceRepository: DeviceRepository,
        sceneRepository: SceneRepository,
        groupRepository: GroupRepository
    ) {
        self.deviceRepository = deviceRepository
        self.sceneRepository = sceneRepository
        self.groupRepository = groupRepository
    }

    func observeFavorites() -> AsyncStream<[DashboardDeviceDescription]> {
        AsyncStream { continuation in
            let snapshotStore = FavoritesSnapshotStore()
            let emissionStore = FavoritesEmissionStore()
            let completionStore = MergeCompletionStore()

            let initialTask = Task { [deviceRepository, sceneRepository, groupRepository] in
                let deviceFavorites = await deviceRepository.favoriteDescriptionsSnapshot()
                let sceneFavorites = await sceneRepository.favoriteDescriptionsSnapshot()
                let groupFavorites = await groupRepository.favoriteDescriptionsSnapshot()
                let merged = (deviceFavorites + sceneFavorites + groupFavorites)
                    .sorted(by: areDashboardFavoritesOrderedAscending)
                if await emissionStore.shouldEmit(merged) {
                    continuation.yield(merged)
                }
            }

            let deviceTask = Task { [deviceRepository] in
                let deviceSequence = await deviceRepository.observeFavoriteDescriptions()
                for await devices in deviceSequence {
                    guard !Task.isCancelled else { return }
                    let merged = await snapshotStore.updateDevices(devices)
                    if await emissionStore.shouldEmit(merged) {
                        continuation.yield(merged)
                    }
                }

                if await completionStore.markTaskFinished() {
                    continuation.finish()
                }
            }

            let sceneTask = Task { [sceneRepository] in
                let sceneSequence = await sceneRepository.observeFavoriteDescriptions()
                for await scenes in sceneSequence {
                    guard !Task.isCancelled else { return }
                    let merged = await snapshotStore.updateScenes(scenes)
                    if await emissionStore.shouldEmit(merged) {
                        continuation.yield(merged)
                    }
                }

                if await completionStore.markTaskFinished() {
                    continuation.finish()
                }
            }

            let groupTask = Task { [groupRepository] in
                let groupSequence = await groupRepository.observeFavoriteDescriptions()
                for await groups in groupSequence {
                    guard !Task.isCancelled else { return }
                    let merged = await snapshotStore.updateGroups(groups)
                    if await emissionStore.shouldEmit(merged) {
                        continuation.yield(merged)
                    }
                }

                if await completionStore.markTaskFinished() {
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                initialTask.cancel()
                deviceTask.cancel()
                sceneTask.cancel()
                groupTask.cancel()
            }
        }
    }

    func reorderFavorite(from sourceId: String, to targetId: String) async {
        let deviceFavorites = await deviceRepository.favoriteDescriptionsSnapshot()
        let sceneFavorites = await sceneRepository.favoriteDescriptionsSnapshot()
        let groupFavorites = await groupRepository.favoriteDescriptionsSnapshot()
        var mergedFavorites = deviceFavorites + sceneFavorites + groupFavorites
        mergedFavorites.sort(by: areDashboardFavoritesOrderedAscending)

        guard let sourceIndex = mergedFavorites.firstIndex(where: { $0.uniqueId == sourceId }),
              let targetIndex = mergedFavorites.firstIndex(where: { $0.uniqueId == targetId }),
              sourceIndex != targetIndex else {
            return
        }

        let moved = mergedFavorites.remove(at: sourceIndex)
        mergedFavorites.insert(moved, at: targetIndex)

        var deviceOrders: [String: Int] = [:]
        var sceneOrders: [String: Int] = [:]
        var groupOrders: [String: Int] = [:]

        for (order, favorite) in mergedFavorites.enumerated() {
            switch favorite.source {
            case .device:
                deviceOrders[favorite.uniqueId] = order
            case .scene:
                sceneOrders[favorite.uniqueId] = order
            case .group:
                groupOrders[favorite.uniqueId] = order
            }
        }

        await deviceRepository.applyDashboardOrders(deviceOrders)
        await sceneRepository.applyDashboardOrders(sceneOrders)
        await groupRepository.applyDashboardOrders(groupOrders)
    }
}

private actor FavoritesSnapshotStore {
    private var devices: [DashboardDeviceDescription] = []
    private var scenes: [DashboardDeviceDescription] = []
    private var groups: [DashboardDeviceDescription] = []

    func updateDevices(_ values: [DashboardDeviceDescription]) -> [DashboardDeviceDescription] {
        devices = values
        return mergedFavorites()
    }

    func updateScenes(_ values: [DashboardDeviceDescription]) -> [DashboardDeviceDescription] {
        scenes = values
        return mergedFavorites()
    }

    func updateGroups(_ values: [DashboardDeviceDescription]) -> [DashboardDeviceDescription] {
        groups = values
        return mergedFavorites()
    }

    private func mergedFavorites() -> [DashboardDeviceDescription] {
        let merged = devices + scenes + groups
        return merged.sorted(by: areDashboardFavoritesOrderedAscending)
    }
}

private actor FavoritesEmissionStore {
    private var lastSnapshot: [DashboardDeviceDescription]?

    func shouldEmit(_ snapshot: [DashboardDeviceDescription]) -> Bool {
        if lastSnapshot == snapshot {
            return false
        }
        lastSnapshot = snapshot
        return true
    }
}

private actor MergeCompletionStore {
    private var finishedTaskCount = 0

    func markTaskFinished() -> Bool {
        finishedTaskCount += 1
        return finishedTaskCount == 3
    }
}

private func areDashboardFavoritesOrderedAscending(
    _ lhs: DashboardDeviceDescription,
    _ rhs: DashboardDeviceDescription
) -> Bool {
    let lhsOrder = lhs.dashboardOrder ?? Int.max
    let rhsOrder = rhs.dashboardOrder ?? Int.max
    if lhsOrder != rhsOrder {
        return lhsOrder < rhsOrder
    }

    if lhs.source != rhs.source {
        return sourcePriority(lhs.source) < sourcePriority(rhs.source)
    }

    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
}

private func sourcePriority(_ source: DashboardFavoriteSource) -> Int {
    switch source {
    case .device:
        return 0
    case .scene:
        return 1
    case .group:
        return 2
    }
}
