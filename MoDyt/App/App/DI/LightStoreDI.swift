import SwiftUI

enum LightStoreDependencyFactory {
    static func make() -> LightStore.Dependencies {
        .init()
    }
}

extension EnvironmentValues {
    @Entry var lightStoreDependencies: LightStore.Dependencies =
        LightStoreDependencyFactory.make()
}
