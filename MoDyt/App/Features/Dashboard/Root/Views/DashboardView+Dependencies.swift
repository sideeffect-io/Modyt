import SwiftUI

extension DashboardStoreFactory {
    static let unimplemented = Self {
        missingDependency("dashboardStoreFactory")
    }
}

extension EnvironmentValues {
    @Entry var dashboardStoreFactory: DashboardStoreFactory = .unimplemented
}

private func missingDependency(_ label: StaticString) -> Never {
    fatalError("Missing DashboardView dependency: \(label)")
}
