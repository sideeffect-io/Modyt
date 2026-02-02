import SwiftUI

@main
struct MoDytApp: App {
    @State private var store = AppStore(environment: .live())

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
        }
    }
}
