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

        let (nextState, effects) = DashboardReducer.reduce(
            state: initialState,
            event: .onAppear
        )

        #expect(nextState == initialState)
        #expect(effects == [.startObservingFavorites])
    }

    @Test
    func refreshRequestedEmitsRefreshAllEffect() {
        let initialState = DashboardState.initial

        let (nextState, effects) = DashboardReducer.reduce(
            state: initialState,
            event: .refreshRequested
        )

        #expect(nextState == initialState)
        #expect(effects == [.refreshAll])
    }

    @Test
    func reorderFavoriteEmitsReorderEffectWithIds() {
        let initialState = DashboardState.initial

        let source = FavoriteType.scene(sceneId: "12")
        let target = FavoriteType.group(
            groupId: "42",
            memberIdentifiers: [.init(deviceId: 4, endpointId: 1)]
        )

        let (nextState, effects) = DashboardReducer.reduce(
            state: initialState,
            event: .reorderFavorite(source, target)
        )

        #expect(nextState == initialState)
        #expect(effects == [.reorderFavorite(source, target)])
    }

    @Test
    func favoritesUpdatedMutatesStateWithoutEmittingEffects() {
        let initialState = DashboardState.initial
        let updatedFavorites = [
            FavoriteItem(
                name: "Kitchen Light",
                usage: .light,
                type: .device(identifier: .init(deviceId: 42, endpointId: 1)),
                order: 0
            ),
            FavoriteItem(
                name: "Night",
                usage: .scene,
                type: .scene(sceneId: "8"),
                order: 1
            )
        ]

        let (nextState, effects) = DashboardReducer.reduce(
            state: initialState,
            event: .favoritesUpdated(updatedFavorites)
        )

        #expect(nextState.favorites == updatedFavorites)
        #expect(effects.isEmpty)
    }
}
