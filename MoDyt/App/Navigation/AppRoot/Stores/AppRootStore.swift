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

enum AppRootEffect: Sendable {}

@Observable
@MainActor
final class AppRootStore: StartableStore {
    struct StateMachine {
        var state: AppRootState = .initial

        mutating func reduce(_ event: AppRootEvent) -> [AppRootEffect] {
            switch event {
            case .authenticated:
                state.route = .runtime
            case .didDisconnect:
                state.route = .authentication
            }
            return []
        }
    }

    private(set) var stateMachine: StateMachine = StateMachine()

    var state: AppRootState {
        stateMachine.state
    }

    func send(_ event: AppRootEvent) {
        _ = stateMachine.reduce(event)
    }

    func start() {}
}
