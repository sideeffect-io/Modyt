import SwiftUI

struct WithStoreView<Store, Content: View>: View {
    @State private var store: Store
    private let content: (Store) -> Content

    init(
        factory: @escaping () -> Store,
        @ViewBuilder content: @escaping (Store) -> Content
    ) {
        _store = State(initialValue: factory())
        self.content = content
    }

    var body: some View {
        content(store)
    }
}
