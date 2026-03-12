import SwiftUI

@main
struct MoDytApp: App {
    private let compositionRoot = AppCompositionRoot.live()

    var body: some SwiftUI.Scene {
        WindowGroup {
            AppRootView()
                .appCompositionRoot(compositionRoot)
        }
    }
}
