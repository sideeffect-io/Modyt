import SwiftUI

extension GroupsStoreFactory {
    static let unimplemented = Self {
        missingDependency("groupsStoreFactory")
    }
}

extension EnvironmentValues {
    @Entry var groupsStoreFactory: GroupsStoreFactory = .unimplemented
}

private func missingDependency(_ label: StaticString) -> Never {
    fatalError("Missing GroupsView dependency: \(label)")
}
