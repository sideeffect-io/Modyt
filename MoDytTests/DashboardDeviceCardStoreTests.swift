import Testing
@testable import MoDyt

struct DashboardDeviceCardStoreReducerTests {
    @Test
    func favoriteTappedEmitsToggleFavoriteEffect() {
        let favoriteType = FavoriteType.group(
            groupId: "group-1",
            memberIdentifiers: [.init(deviceId: 5, endpointId: 1)]
        )
        let transition = DashboardDeviceCardStore.StateMachine.reduce(
            .initial,
            .favoriteTapped,
            favoriteType: favoriteType
        )

        #expect(transition.state == .initial)
        #expect(transition.effects == [.toggleFavorite])
    }
}

@MainActor
struct DashboardDeviceCardStoreEffectTests {
    @Test
    func startIsANoOp() async {
        let recorder = TestRecorder<FavoriteType>()
        let store = DashboardDeviceCardStore(
            favoriteType: .device(identifier: .init(deviceId: 1, endpointId: 1)),
            toggleFavorite: .init(
                toggleFavorite: { await recorder.record($0) }
            )
        )

        store.start()
        await testSettle()

        #expect(await recorder.values().isEmpty)
    }

    @Test
    func favoriteTappedForwardsExactFavoriteType() async {
        let favoriteType = FavoriteType.scene(sceneId: "scene-12")
        let recorder = TestRecorder<FavoriteType>()
        let store = DashboardDeviceCardStore(
            favoriteType: favoriteType,
            toggleFavorite: .init(
                toggleFavorite: { await recorder.record($0) }
            )
        )

        store.send(.favoriteTapped)

        #expect(await testWaitUntilAsync {
            await recorder.values() == [favoriteType]
        })
    }
}
