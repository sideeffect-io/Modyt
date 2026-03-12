import SwiftUI
import Combine

private final class StoreBox<Store: StartableStore>: ObservableObject {
    let store: Store

    init(factory: @escaping () -> Store) {
        self.store = factory()
    }
}

struct WithStoreView<Store, Content: View>: View where Store: StartableStore {
    @StateObject private var storeBox: StoreBox<Store>
    @State private var didStart = false

    private let content: (Store) -> Content

    init(
        store: @autoclosure @escaping () -> Store,
        @ViewBuilder content: @escaping (Store) -> Content
    ) {
        _storeBox = StateObject(wrappedValue: StoreBox(factory: store))
        self.content = content
    }

    var body: some View {
        content(storeBox.store)
            .task {
                guard !didStart else { return }
                storeBox.store.start()
                didStart = true
            }
    }
}
