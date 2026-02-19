import Testing
@testable import MoDyt

@MainActor
struct DashboardDeviceCardStoreTests {
    @Test
    func favoriteTappedDispatchesToggleFavorite() async {
        let recorder = TestRecorder<String>()
        let store = DashboardDeviceCardStore(
            uniqueId: "light-1",
            dependencies: .init(
                toggleFavorite: { uniqueId in
                    await recorder.record("toggle:\(uniqueId)")
                }
            )
        )

        store.send(.favoriteTapped)
        let didDispatch = await waitUntil {
            (await recorder.values).count == 1
        }

        #expect(didDispatch)
        #expect(await recorder.values == ["toggle:light-1"])
    }

    @Test
    func favoriteTappedDispatchesToggleFavoriteForGroupId() async {
        let recorder = TestRecorder<String>()
        let store = DashboardDeviceCardStore(
            uniqueId: "group_1773652822",
            dependencies: .init(
                toggleFavorite: { uniqueId in
                    await recorder.record("toggle:\(uniqueId)")
                }
            )
        )

        store.send(.favoriteTapped)
        let didDispatch = await waitUntil {
            (await recorder.values).count == 1
        }

        #expect(didDispatch)
        #expect(await recorder.values == ["toggle:group_1773652822"])
    }
}
