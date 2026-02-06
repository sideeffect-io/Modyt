import SwiftUI

struct AppRootView: View {
    @Bindable var store: AppCoordinatorStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            AppBackgroundView()
                .ignoresSafeArea()
            content
        }
        .task {
            store.send(.onAppear)
        }
        .onChange(of: scenePhase) { _, newPhase in
            store.send(.setAppActive(newPhase == .active))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state.route {
        case .authentication(let authenticationStore):
            AuthenticationRootView(store: authenticationStore)
        case .runtime(let runtimeStore):
            RuntimeRootView(store: runtimeStore)
        }
    }
}
