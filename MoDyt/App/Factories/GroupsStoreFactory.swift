import SwiftUI
import DeltaDoreClient

struct GroupsStoreFactory {
    let make: @MainActor () -> GroupsStore

    static func live(dependencies: DependencyBag) -> GroupsStoreFactory {
        GroupsStoreFactory {
            let groupRepository = dependencies.localStorageDatasources.groupRepository

            return GroupsStore(
                dependencies: .init(
                    observeGroups: { await groupRepository.observeAll() },
                    toggleFavorite: { groupID in try? await groupRepository.toggleFavorite(groupID) },
                    refreshAll: { try? await dependencies.gatewayClient.send(text: TydomCommand.refreshAll().request) }
                )
            )
        }
    }
}

private struct GroupsStoreFactoryKey: EnvironmentKey {
    static var defaultValue: GroupsStoreFactory {
        .live(dependencies: .live())
    }
}

extension EnvironmentValues {
    var groupsStoreFactory: GroupsStoreFactory {
        get { self[GroupsStoreFactoryKey.self] }
        set { self[GroupsStoreFactoryKey.self] = newValue }
    }
}
