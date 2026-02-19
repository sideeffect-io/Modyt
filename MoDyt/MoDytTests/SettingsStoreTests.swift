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

        let didDisconnect = await waitUntil {
            !store.state.isDisconnecting && store.state.didDisconnect
        }
        #expect(didDisconnect)
        #expect(!store.state.isDisconnecting)
        #expect(store.state.didDisconnect)
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
        let didFail = await waitUntil {
            !store.state.isDisconnecting && !store.state.didDisconnect && store.state.errorMessage != nil
        }

        #expect(didFail)
        #expect(!store.state.isDisconnecting)
        #expect(!store.state.didDisconnect)
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
        let didFinishOnce = await waitUntil {
            let entries = await recorder.values
            return !store.state.isDisconnecting
                && store.state.didDisconnect
                && entries == ["disconnect"]
        }

        #expect(didFinishOnce)
        #expect(!store.state.isDisconnecting)
        #expect(store.state.didDisconnect)
        #expect(await recorder.values == ["disconnect"])
    }
}
