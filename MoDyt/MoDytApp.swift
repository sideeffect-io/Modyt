import SwiftUI

@main
struct MoDytApp: App {
    @State private var store = AppCoordinatorStore(environment: .live())

    var body: some Scene {
        WindowGroup {
            AppRootView(store: store)
        }
    }
}
