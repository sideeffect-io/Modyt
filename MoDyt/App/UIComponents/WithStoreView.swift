import SwiftUI

struct WithStoreView<Store, Content: View>: View where Store: StartableStore {
    @State private var store: Store
    @State private var didStart = false

    private let content: (Store) -> Content

    init(
        store: @autoclosure @escaping () -> Store,
        @ViewBuilder content: @escaping (Store) -> Content
    ) {
        _store = State(wrappedValue: store())
        self.content = content
    }

    var body: some View {
        content(store)
            .task {
                guard !didStart else { return }
                store.start()
                didStart = true
            }
    }
}
