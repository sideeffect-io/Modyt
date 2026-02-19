import SwiftUI

struct GroupsStoreFactory {
    let make: @MainActor () -> GroupsStore

    static func live(environment: AppEnvironment) -> GroupsStoreFactory {
        GroupsStoreFactory {
            GroupsStore(
                dependencies: .init(
                    observeGroups: {
                        await environment.groupRepository.observeGroups()
                    },
                    toggleFavorite: { uniqueId in
                        await environment.groupRepository.toggleFavorite(uniqueId: uniqueId)
                    },
                    refreshAll: {
                        await environment.requestRefreshAll()
                    }
                )
            )
        }
    }
}

private struct GroupsStoreFactoryKey: EnvironmentKey {
    static var defaultValue: GroupsStoreFactory {
        GroupsStoreFactory.live(environment: .live())
    }
}

extension EnvironmentValues {
    var groupsStoreFactory: GroupsStoreFactory {
        get { self[GroupsStoreFactoryKey.self] }
        set { self[GroupsStoreFactoryKey.self] = newValue }
    }
}
