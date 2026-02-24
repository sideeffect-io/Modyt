import Foundation

extension Domain {
    struct SQLiteBackedRepositories: Sendable {
        let deviceRepository: DeviceRepository
        let groupRepository: GroupRepository
        let sceneRepository: SceneRepository
        let favoritesRepository: FavoriteRepository
        let tydomMessageRepositoryRouter: Domain.TydomMessageRepositoryRouter
    }

    static func makeSQLiteBackedRepositories(
        databasePath: String,
        now: @escaping @Sendable () -> Date = Date.init,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) -> SQLiteBackedRepositories {
        let deviceRepository = DeviceRepository.makeDeviceRepository(
            databasePath: databasePath,
            now: now,
            log: log
        )

        let groupRepository = GroupRepository.makeGroupRepository(
            databasePath: databasePath,
            now: now,
            log: log
        )

        let sceneRepository = SceneRepository.makeSceneRepository(
            databasePath: databasePath,
            now: now,
            log: log
        )

        let favoritesRepository = FavoriteRepository(
            deviceRepository: deviceRepository,
            groupRepository: groupRepository,
            sceneRepository: sceneRepository
        )

        let tydomMessageRepositoryRouter = Domain.TydomMessageRepositoryRouter(
            deviceRepository: deviceRepository,
            groupRepository: groupRepository,
            sceneRepository: sceneRepository,
            log: log
        )

        return SQLiteBackedRepositories(
            deviceRepository: deviceRepository,
            groupRepository: groupRepository,
            sceneRepository: sceneRepository,
            favoritesRepository: favoritesRepository,
            tydomMessageRepositoryRouter: tydomMessageRepositoryRouter
        )
    }
}
