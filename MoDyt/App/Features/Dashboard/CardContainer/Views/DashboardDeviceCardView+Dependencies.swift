import SwiftUI

extension DashboardDeviceCardStoreFactory {
    static let unimplemented = Self { _ in
        missingDependency("dashboardDeviceCardStoreFactory")
    }
}

extension EnvironmentValues {
    @Entry var dashboardDeviceCardStoreFactory: DashboardDeviceCardStoreFactory = .unimplemented
}

private func missingDependency(_ label: StaticString) -> Never {
    fatalError("Missing DashboardDeviceCardView dependency: \(label)")
}
