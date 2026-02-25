import Foundation

struct LocalStorageDatasources: Sendable {
    let deviceRepository: DeviceRepository
    let groupRepository: GroupRepository
    let sceneRepository: SceneRepository
    let ackRepository: ACKRepository
    let favoritesRepository: FavoriteRepository
    let tydomMessageRepositoryRouter: TydomMessageRepositoryRouter
}

func makeLocalStorageDatasources(
    databasePath: String,
    now: @escaping @Sendable () -> Date = Date.init,
    log: @escaping @Sendable (String) -> Void = { _ in }
) -> LocalStorageDatasources {

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

    let ackRepository = ACKRepository()
    
    let favoritesRepository = FavoriteRepository(
        deviceRepository: deviceRepository,
        groupRepository: groupRepository,
        sceneRepository: sceneRepository
    )
    
    let tydomMessageRepositoryRouter = TydomMessageRepositoryRouter(
        deviceRepository: deviceRepository,
        groupRepository: groupRepository,
        sceneRepository: sceneRepository,
        ackRepository: ackRepository,
        log: log
    )
    
    return LocalStorageDatasources(
        deviceRepository: deviceRepository,
        groupRepository: groupRepository,
        sceneRepository: sceneRepository,
        ackRepository: ackRepository,
        favoritesRepository: favoritesRepository,
        tydomMessageRepositoryRouter: tydomMessageRepositoryRouter
    )
}
