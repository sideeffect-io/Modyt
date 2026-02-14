import Testing
@testable import MoDyt

struct AppRootStoreTests {
    @MainActor
    @Test
    func authenticatedEventSwitchesToRuntimeRoute() {
        let coordinator = AppRootStore()

        coordinator.send(.authenticated)

        switch coordinator.state.route {
        case .runtime:
            #expect(true)
        case .authentication:
            #expect(Bool(false), "Expected runtime route")
        }
    }

    @MainActor
    @Test
    func didDisconnectSwitchesBackToAuthenticationRoute() {
        let coordinator = AppRootStore()
        coordinator.send(.authenticated)

        coordinator.send(.didDisconnect)

        switch coordinator.state.route {
        case .authentication:
            #expect(true)
        case .runtime:
            #expect(Bool(false), "Expected authentication route")
        }
    }
}
