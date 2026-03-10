import Testing
@testable import MoDyt

struct DashboardDeviceCardStoreReducerTests {
    @Test
    func favoriteTappedEmitsToggleFavoriteEffect() {
        let favoriteType = FavoriteType.group(
            groupId: "group-1",
            memberIdentifiers: [.init(deviceId: 5, endpointId: 1)]
        )
        var stateMachine = DashboardDeviceCardStore.StateMachine()

        let effects = stateMachine.reduce(.favoriteTapped, favoriteType: favoriteType)

        #expect(stateMachine.state == .initial)
        #expect(effects == [.toggleFavorite(favoriteType)])
    }
}

@MainActor
struct DashboardDeviceCardStoreEffectTests {
    @Test
    func startIsANoOp() async {
        let recorder = TestRecorder<FavoriteType>()
        let store = DashboardDeviceCardStore(
            dependencies: .init(
                toggleFavorite: { await recorder.record($0) }
            ),
            favoriteType: .device(identifier: .init(deviceId: 1, endpointId: 1))
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
            dependencies: .init(
                toggleFavorite: { await recorder.record($0) }
            ),
            favoriteType: favoriteType
        )

        store.send(.favoriteTapped)

        #expect(await testWaitUntilAsync {
            await recorder.values() == [favoriteType]
        })
    }
}
