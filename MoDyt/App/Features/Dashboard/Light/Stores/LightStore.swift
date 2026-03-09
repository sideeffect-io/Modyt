import Foundation

@MainActor
final class LightStore: StartableStore {
    struct Dependencies {}

    let identifier: DeviceIdentifier

    init(
        identifier: DeviceIdentifier,
        dependencies: Dependencies
    ) {
        self.identifier = identifier
        _ = dependencies
    }

    func start() {}
}
