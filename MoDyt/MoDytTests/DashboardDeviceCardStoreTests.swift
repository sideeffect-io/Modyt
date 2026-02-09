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
        await settleAsyncState()

        #expect(await recorder.values == ["toggle:light-1"])
    }
}
