import Testing
import DeltaDoreClient
@testable import MoDyt

struct AuthenticationReducerTests {
    @Test
    func onAppearTriggersFlowInspection() {
        let (nextState, effects) = AuthenticationReducer.reduce(
            state: .initial,
            event: .onAppear
        )

        #expect(nextState.phase == .bootstrapping)
        #expect(effects == [.inspectFlow])
    }

    @Test
    func flowInspectionTransitionsByMode() {
        let (storedState, storedEffects) = AuthenticationReducer.reduce(
            state: .initial,
            event: .flowInspected(.connectWithStoredCredentials)
        )
        #expect(storedState.phase == .connecting)
        #expect(storedEffects == [.connectStored])

        let (newState, newEffects) = AuthenticationReducer.reduce(
            state: .initial,
            event: .flowInspected(.connectWithNewCredentials)
        )
        #expect(newState.phase == .login(LoginState()))
        #expect(newEffects.isEmpty)
    }

    @Test
    func loadSitesAndFailuresUpdateLoginState() {
        var login = LoginState()
        login.email = "user@example.com"
        login.password = "secret"

        let startState = AuthenticationState(phase: .login(login))
        let (loadingState, effects) = AuthenticationReducer.reduce(
            state: startState,
            event: .loadSitesTapped
        )

        guard case .login(let loadingLogin) = loadingState.phase else {
            #expect(Bool(false), "Expected login phase")
            return
        }
        #expect(loadingLogin.isLoadingSites)
        #expect(effects == [.listSites(email: "user@example.com", password: "secret")])

        let (failureState, _) = AuthenticationReducer.reduce(
            state: loadingState,
            event: .sitesLoaded(.failure(TestError.expectedFailure))
        )
        guard case .login(let failureLogin) = failureState.phase else {
            #expect(Bool(false), "Expected login phase")
            return
        }
        #expect(!failureLogin.isLoadingSites)
        #expect(failureLogin.errorMessage != nil)
    }

    @MainActor
    @Test
    func connectionSucceededEmitsAuthenticatedDelegateEvent() {
        let store = AuthenticationStore(environment: TestSupport.makeEnvironment())
        var didEmitAuthenticated = false
        store.onDelegateEvent = { delegateEvent in
            if case .authenticated = delegateEvent {
                didEmitAuthenticated = true
            }
        }

        store.send(.connectionSucceeded(TestSupport.makeConnection()))

        #expect(didEmitAuthenticated)
    }
}
