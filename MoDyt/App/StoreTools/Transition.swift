import Foundation

struct Transition<State: Sendable, Effect: Sendable>: Sendable {
    let state: State
    let effects: [Effect]

    init(
        state: State,
        effects: [Effect] = []
    ) {
        self.state = state
        self.effects = effects
    }
}
