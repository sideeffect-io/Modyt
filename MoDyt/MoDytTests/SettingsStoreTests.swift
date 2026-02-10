import Testing
@testable import MoDyt

@MainActor
struct SettingsStoreTests {
    @Test
    func disconnectTapSetsInFlightAndCallsDependency() async {
        let recorder = TestRecorder<String>()
        let store = SettingsStore(
            dependencies: .init(
                requestDisconnect: {
                    await recorder.record("disconnect")
                    return .success(())
                }
            )
        )

        store.send(.disconnectTapped)
        #expect(store.state.isDisconnecting)

        await settleAsyncState()
        #expect(!store.state.isDisconnecting)
        #expect(store.state.errorMessage == nil)
        #expect(await recorder.values == ["disconnect"])
    }

    @Test
    func disconnectFailureSetsErrorMessage() async {
        let store = SettingsStore(
            dependencies: .init(
                requestDisconnect: {
                    .failure(SettingsStoreError(message: "disconnect failed"))
                }
            )
        )

        store.send(.disconnectTapped)
        await settleAsyncState()

        #expect(!store.state.isDisconnecting)
        #expect(store.state.errorMessage != nil)
    }

    @Test
    func disconnectTapIsIgnoredWhileAlreadyDisconnecting() async {
        let recorder = TestRecorder<String>()
        let store = SettingsStore(
            dependencies: .init(
                requestDisconnect: {
                    await recorder.record("disconnect")
                    return .success(())
                }
            )
        )

        store.send(.disconnectTapped)
        store.send(.disconnectTapped)
        await settleAsyncState()

        #expect(!store.state.isDisconnecting)
        #expect(await recorder.values == ["disconnect"])
    }
}
