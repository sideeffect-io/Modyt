import Foundation

actor DashboardRepository {
    private let deviceRepository: DeviceRepository
    private let sceneRepository: SceneRepository

    init(
        deviceRepository: DeviceRepository,
        sceneRepository: SceneRepository
    ) {
        self.deviceRepository = deviceRepository
        self.sceneRepository = sceneRepository
    }

    func observeFavorites() -> AsyncStream<[DashboardDeviceDescription]> {
        AsyncStream { continuation in
            let snapshotStore = FavoritesSnapshotStore()
            let completionStore = MergeCompletionStore()

            let deviceTask = Task { [deviceRepository] in
                let deviceSequence = await deviceRepository.observeFavoriteDescriptions()
                for await devices in deviceSequence {
                    guard !Task.isCancelled else { return }
                    let merged = await snapshotStore.updateDevices(devices)
                    continuation.yield(merged)
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
                    continuation.yield(merged)
                }

                if await completionStore.markTaskFinished() {
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                deviceTask.cancel()
                sceneTask.cancel()
            }
        }
    }

    func reorderFavorite(from sourceId: String, to targetId: String) async {
        let deviceFavorites = await deviceRepository.favoriteDescriptionsSnapshot()
        let sceneFavorites = await sceneRepository.favoriteDescriptionsSnapshot()
        var mergedFavorites = deviceFavorites + sceneFavorites
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

        for (order, favorite) in mergedFavorites.enumerated() {
            switch favorite.source {
            case .device:
                deviceOrders[favorite.uniqueId] = order
            case .scene:
                sceneOrders[favorite.uniqueId] = order
            }
        }

        await deviceRepository.applyDashboardOrders(deviceOrders)
        await sceneRepository.applyDashboardOrders(sceneOrders)
    }
}

private actor FavoritesSnapshotStore {
    private var devices: [DashboardDeviceDescription] = []
    private var scenes: [DashboardDeviceDescription] = []

    func updateDevices(_ values: [DashboardDeviceDescription]) -> [DashboardDeviceDescription] {
        devices = values
        return mergedFavorites()
    }

    func updateScenes(_ values: [DashboardDeviceDescription]) -> [DashboardDeviceDescription] {
        scenes = values
        return mergedFavorites()
    }

    private func mergedFavorites() -> [DashboardDeviceDescription] {
        let merged = devices + scenes
        return merged.sorted(by: areDashboardFavoritesOrderedAscending)
    }
}

private actor MergeCompletionStore {
    private var finishedTaskCount = 0

    func markTaskFinished() -> Bool {
        finishedTaskCount += 1
        return finishedTaskCount == 2
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
    }
}
