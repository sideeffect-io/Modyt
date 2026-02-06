import Testing
@testable import MoDyt

struct AppCoordinatorStoreTests {
    @MainActor
    @Test
    func authenticatedDelegateEventSwitchesToRuntimeRoute() {
        let coordinator = AppCoordinatorStore(environment: TestSupport.makeEnvironment())

        coordinator.send(.authenticationDelegateEvent(.authenticated(connection: TestSupport.makeConnection())))

        let isRuntimeRoute: Bool
        switch coordinator.state.route {
        case .runtime:
            isRuntimeRoute = true
        case .authentication:
            isRuntimeRoute = false
        }
        #expect(isRuntimeRoute)
    }

    @MainActor
    @Test
    func appActiveStateIsForwardedAcrossAuthenticationHandoff() {
        let coordinator = AppCoordinatorStore(environment: TestSupport.makeEnvironment())
        coordinator.send(.setAppActive(false))

        coordinator.send(.authenticationDelegateEvent(.authenticated(connection: TestSupport.makeConnection())))

        switch coordinator.state.route {
        case .runtime(let runtimeStore):
            #expect(runtimeStore.state.isAppActive == false)
        case .authentication:
            #expect(Bool(false), "Expected runtime route")
        }
    }

    @MainActor
    @Test
    func runtimeDelegateEventSwitchesBackToAuthenticationRoute() {
        let coordinator = AppCoordinatorStore(environment: TestSupport.makeEnvironment())
        coordinator.send(.authenticationDelegateEvent(.authenticated(connection: TestSupport.makeConnection())))

        coordinator.send(.runtimeDelegateEvent(.didDisconnect))

        let isAuthenticationRoute: Bool
        switch coordinator.state.route {
        case .authentication:
            isAuthenticationRoute = true
        case .runtime:
            isAuthenticationRoute = false
        }
        #expect(isAuthenticationRoute)
    }
}
