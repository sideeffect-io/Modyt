import SwiftUI
import Testing
@testable import MoDyt

struct DashboardStoreReducerTests {
    @Test
    func favoriteTypeIDsAreScopedBySource() {
        let scene = FavoriteType.scene(sceneId: "1")
        let group = FavoriteType.group(groupId: "1", memberIdentifiers: [])
        let device = FavoriteType.device(identifier: .init(deviceId: 1, endpointId: 1))

        #expect(scene.id != group.id)
        #expect(group.id != device.id)
        #expect(scene.id != device.id)
    }

    @Test
    func onAppearEmitsStartObservingFavoritesEffect() {
        let initialState = DashboardState.initial
        let transition = DashboardStore.StateMachine.reduce(initialState, .onAppear)

        #expect(transition.state == initialState)
        #expect(transition.effects == [.startObservingFavorites])
    }

    @Test
    func refreshRequestedEmitsRefreshAllEffect() {
        let initialState = DashboardState.initial
        let transition = DashboardStore.StateMachine.reduce(initialState, .refreshRequested)

        #expect(transition.state == initialState)
        #expect(transition.effects == [.refreshAll])
    }

    @Test
    func reorderFavoriteEmitsReorderEffectWithIds() {
        let initialState = DashboardState.initial

        let source = FavoriteType.scene(sceneId: "12")
        let target = FavoriteType.group(
            groupId: "42",
            memberIdentifiers: [.init(deviceId: 4, endpointId: 1)]
        )

        let transition = DashboardStore.StateMachine.reduce(
            initialState,
            .reorderFavorite(source, target)
        )

        #expect(transition.state == initialState)
        #expect(transition.effects == [.reorderFavorite(source, target)])
    }

    @Test
    func favoritesObservedProjectsFavoritesWithoutEmittingEffects() {
        let initialState = DashboardState.initial
        let device = makeTestDevice(
            identifier: .init(deviceId: 42, endpointId: 1),
            name: "Kitchen Light",
            usage: "light",
            isFavorite: true,
            dashboardOrder: 0
        )
        let scene = makeTestScene(
            id: "8",
            name: "Night",
            isFavorite: true,
            dashboardOrder: 1
        )
        let observation = DashboardFavoritesObservation(
            devices: [device],
            groups: [],
            scenes: [scene]
        )

        let transition = DashboardStore.StateMachine.reduce(
            initialState,
            .favoritesObserved(observation)
        )

        #expect(
            transition.state.favorites
                == FavoriteItemsProjector.items(
                    devices: observation.devices,
                    groups: observation.groups,
                    scenes: observation.scenes
                )
        )
        #expect(transition.effects.isEmpty)
    }

    @Test
    func compactPortraitPaginationUsesSixCardsPerPageWhenTighterChromeCreatesRoom() {
        let metrics = DashboardPaginationMetrics.make(
            availableSize: CGSize(width: 390, height: 680),
            favoriteCount: 7,
            horizontalSizeClass: .compact
        )

        #expect(metrics.columnCount == 2)
        #expect(metrics.rowCount == 3)
        #expect(metrics.pageSize == 6)
        #expect(metrics.showsPageIndicator)
    }

    @Test
    func compactPortraitPaginationKeepsFourCardsPerPageWhenHeightIsStillTooShort() {
        let metrics = DashboardPaginationMetrics.make(
            availableSize: CGSize(width: 390, height: 650),
            favoriteCount: 7,
            horizontalSizeClass: .compact
        )

        #expect(metrics.columnCount == 2)
        #expect(metrics.rowCount == 2)
        #expect(metrics.pageSize == 4)
        #expect(metrics.showsPageIndicator)
    }
}
