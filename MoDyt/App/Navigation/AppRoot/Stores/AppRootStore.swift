import Foundation
import Observation

struct AppRootState {
    enum Route {
        case authentication
        case runtime
    }

    var route: Route

    static let initial = AppRootState(
        route: .authentication
    )
}

enum AppRootEvent {
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
        case .authenticated:
            state.route = .runtime

        case .didDisconnect:
            state.route = .authentication
        }
    }
}
