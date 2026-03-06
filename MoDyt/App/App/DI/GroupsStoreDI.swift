import SwiftUI
import DeltaDoreClient

enum GroupsStoreDependencyFactory {
    static func make(
        dependencyBag: DependencyBag = .production
    ) -> GroupsStore.Dependencies {
        let groupRepository = dependencyBag.localStorageDatasources.groupRepository
        let gatewayClient = dependencyBag.gatewayClient

        return .init(
            observeGroups: { await groupRepository.observeAll() },
            toggleFavorite: { groupID in try? await groupRepository.toggleFavorite(groupID) },
            refreshAll: { try? await gatewayClient.send(text: TydomCommand.refreshAll().request) }
        )
    }
}

extension EnvironmentValues {
    @Entry var groupsStoreDependencies: GroupsStore.Dependencies =
        GroupsStoreDependencyFactory.make()
}
