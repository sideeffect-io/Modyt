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
        var stateMachine = DashboardStore.StateMachine(state: initialState)
        let effects = stateMachine.reduce(.onAppear)
        let nextState = stateMachine.state

        #expect(nextState == initialState)
        #expect(effects == [.startObservingFavorites])
    }

    @Test
    func refreshRequestedEmitsRefreshAllEffect() {
        let initialState = DashboardState.initial
        var stateMachine = DashboardStore.StateMachine(state: initialState)
        let effects = stateMachine.reduce(.refreshRequested)
        let nextState = stateMachine.state

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

        var stateMachine = DashboardStore.StateMachine(state: initialState)
        let effects = stateMachine.reduce(.reorderFavorite(source, target))
        let nextState = stateMachine.state

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

        var stateMachine = DashboardStore.StateMachine(state: initialState)
        let effects = stateMachine.reduce(.favoritesUpdated(updatedFavorites))
        let nextState = stateMachine.state

        #expect(nextState.favorites == updatedFavorites)
        #expect(effects.isEmpty)
    }
}
