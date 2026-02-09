import SwiftUI

struct AppRootView: View {
    @Environment(\.appCoordinatorStoreFactory) private var appCoordinatorStoreFactory
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        WithStoreView(factory: appCoordinatorStoreFactory.make ) { store in
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                content(for: store)
            }
            .onChange(of: scenePhase) { _, newPhase in
                store.send(.setAppActive(newPhase == .active))
            }
        }
    }

    @ViewBuilder
    private func content(for store: AppRootStore) -> some View {
        switch store.state.route {
        case .authentication:
            AuthenticationRootView(onAuthenticated: {
                store.send(.authenticated)
            })

        case .runtime:
            RootTabView(
                isAppActive: store.state.isAppActive,
                onDidDisconnect: {
                    store.send(.didDisconnect)
                }
            )
        }
    }
}
