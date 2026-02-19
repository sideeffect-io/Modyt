import Testing
import DeltaDoreClient
@testable import MoDyt

@MainActor
struct AuthenticationStoreTests {
    @Test
    func onAppearTriggersFlowInspectionReducerEffect() {
        let (nextState, effects) = AuthenticationReducer.reduce(
            state: .initial,
            event: .onAppear
        )

        #expect(nextState.phase == .bootstrapping)
        #expect(effects == [.inspectFlow])
    }

    @Test
    func flowInspectionTransitionsReducerByMode() {
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
    func loadSitesAndFailuresUpdateLoginStateInReducer() {
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
            event: .sitesLoaded(.failure(AuthenticationStoreError(message: "expected failure")))
        )
        guard case .login(let failureLogin) = failureState.phase else {
            #expect(Bool(false), "Expected login phase")
            return
        }
        #expect(!failureLogin.isLoadingSites)
        #expect(failureLogin.errorMessage != nil)
    }

    @Test
    func onAppearWithStoredCredentialsConnectsAndEmitsDelegate() async {
        let inspectCounter = Counter()
        let connectCounter = Counter()
        var didEmitAuthenticated = false

        let store = AuthenticationStore(
            dependencies: .init(
                inspectFlow: {
                    await inspectCounter.increment()
                    return .connectWithStoredCredentials
                },
                connectStored: {
                    await connectCounter.increment()
                },
                listSites: { _, _ in [] },
                connectNew: { _, _, _ in }
            )
        )
        store.onDelegateEvent = { delegateEvent in
            if case .authenticated = delegateEvent {
                didEmitAuthenticated = true
            }
        }

        store.send(.onAppear)
        let didConnect = await waitUntil {
            let inspectCalls = await inspectCounter.value
            let connectCalls = await connectCounter.value
            return inspectCalls == 1
                && connectCalls == 1
                && didEmitAuthenticated
                && store.state.phase == .connecting
        }

        #expect(didConnect)
        #expect(await inspectCounter.value == 1)
        #expect(await connectCounter.value == 1)
        #expect(didEmitAuthenticated)
        #expect(store.state.phase == .connecting)
    }

    @Test
    func storedCredentialsFailureTransitionsToErrorPhase() async {
        struct ConnectError: Error {}

        let store = AuthenticationStore(
            dependencies: .init(
                inspectFlow: { .connectWithStoredCredentials },
                connectStored: {
                    throw ConnectError()
                },
                listSites: { _, _ in [] },
                connectNew: { _, _, _ in }
            )
        )

        store.send(.onAppear)
        let didTransitionToError = await waitUntil {
            if case .error = store.state.phase {
                return true
            }
            return false
        }

        #expect(didTransitionToError)
        guard case .error(let message) = store.state.phase else {
            #expect(Bool(false), "Expected error phase")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test
    func loginFlowLoadsSitesThenConnectsWithSelectedSite() async {
        let listSitesRecorder = TestRecorder<String>()
        let connectRecorder = TestRecorder<String>()
        var didEmitAuthenticated = false

        let store = AuthenticationStore(
            dependencies: .init(
                inspectFlow: { .connectWithNewCredentials },
                connectStored: {},
                listSites: { email, password in
                    await listSitesRecorder.record("\(email)|\(password)")
                    return []
                },
                connectNew: { email, password, siteIndex in
                    await connectRecorder.record("\(email)|\(password)|\(siteIndex.map(String.init) ?? "nil")")
                }
            )
        )
        store.onDelegateEvent = { event in
            if case .authenticated = event {
                didEmitAuthenticated = true
            }
        }

        store.send(.onAppear)
        let didEnterLogin = await waitUntil {
            if case .login = store.state.phase {
                return true
            }
            return false
        }
        #expect(didEnterLogin)

        store.send(.loginEmailChanged("user@example.com"))
        store.send(.loginPasswordChanged("secret"))
        store.send(.loadSitesTapped)
        let didLoadSites = await waitUntil {
            let entries = await listSitesRecorder.values
            return entries == ["user@example.com|secret"]
        }

        #expect(didLoadSites)
        #expect(await listSitesRecorder.values == ["user@example.com|secret"])

        store.send(.siteSelected(0))
        store.send(.connectTapped)
        let didConnect = await waitUntil {
            let entries = await connectRecorder.values
            return entries == ["user@example.com|secret|0"]
                && didEmitAuthenticated
                && store.state.phase == .connecting
        }

        #expect(didConnect)
        #expect(await connectRecorder.values == ["user@example.com|secret|0"])
        #expect(didEmitAuthenticated)
        #expect(store.state.phase == .connecting)
    }

    @Test
    func connectFailureReturnsToLoginPhaseWithError() async {
        struct ConnectError: Error {}

        let store = AuthenticationStore(
            dependencies: .init(
                inspectFlow: { .connectWithNewCredentials },
                connectStored: {},
                listSites: { _, _ in [] },
                connectNew: { _, _, _ in
                    throw ConnectError()
                }
            )
        )

        store.send(.onAppear)
        let didEnterLogin = await waitUntil {
            if case .login = store.state.phase {
                return true
            }
            return false
        }
        #expect(didEnterLogin)

        store.send(.loginEmailChanged("user@example.com"))
        store.send(.loginPasswordChanged("secret"))
        store.send(.siteSelected(0))
        store.send(.connectTapped)
        let didFailConnection = await waitUntil {
            if case .login(let login) = store.state.phase {
                return !login.isConnecting && login.errorMessage != nil
            }
            return false
        }
        #expect(didFailConnection)

        guard case .login(let login) = store.state.phase else {
            #expect(Bool(false), "Expected login phase")
            return
        }

        #expect(!login.isConnecting)
        #expect(login.errorMessage != nil)
    }

    @Test
    func listSitesFailureReturnsToLoginWithErrorMessage() async {
        struct ListSitesError: Error {}

        let store = AuthenticationStore(
            dependencies: .init(
                inspectFlow: { .connectWithNewCredentials },
                connectStored: {},
                listSites: { _, _ in
                    throw ListSitesError()
                },
                connectNew: { _, _, _ in }
            )
        )

        store.send(.onAppear)
        let didEnterLogin = await waitUntil {
            if case .login = store.state.phase {
                return true
            }
            return false
        }
        #expect(didEnterLogin)

        store.send(.loginEmailChanged("user@example.com"))
        store.send(.loginPasswordChanged("secret"))
        store.send(.loadSitesTapped)
        let didFailListSites = await waitUntil {
            if case .login(let login) = store.state.phase {
                return !login.isLoadingSites && login.errorMessage != nil
            }
            return false
        }
        #expect(didFailListSites)

        guard case .login(let login) = store.state.phase else {
            #expect(Bool(false), "Expected login phase")
            return
        }

        #expect(!login.isLoadingSites)
        #expect(login.errorMessage != nil)
        #expect(login.sites.isEmpty)
    }
}
