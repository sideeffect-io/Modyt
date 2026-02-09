import Foundation
import Observation

struct AppRootState {
    enum Route {
        case authentication
        case runtime
    }

    var route: Route
    var isAppActive: Bool

    static let initial = AppRootState(
        route: .authentication,
        isAppActive: true
    )
}

enum AppRootEvent {
    case setAppActive(Bool)
    case authenticated
    case didDisconnect
}

@Observable
@MainActor
final class AppRootStore {
    private(set) var state: AppRootState

    init(state: AppRootState = .initial) {
        self.state = state
    }

    func send(_ event: AppRootEvent) {
        switch event {
        case .setAppActive(let isAppActive):
            state.isAppActive = isAppActive

        case .authenticated:
            state.route = .runtime

        case .didDisconnect:
            state.route = .authentication
        }
    }
}
