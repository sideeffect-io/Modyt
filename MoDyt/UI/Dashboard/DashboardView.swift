import SwiftUI
import UniformTypeIdentifiers
import MoDytCore

struct DashboardView: View {
    @Bindable var store: AppStore
    @State private var draggingId: String?

    var body: some View {
        ScrollView {
            if orderedFavorites.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "star")
                        .font(.system(size: 32, weight: .semibold))
                    Text("No favorites yet")
                        .font(.headline)
                    Text("Mark devices as favorites to pin them here.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 240)
                .padding(20)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(orderedFavorites) { device in
                        let card = DeviceCardView(device: device, isEditing: store.state.isDashboardEditing) {
                            store.send(.deviceAction(device))
                        }
                        if store.state.isDashboardEditing {
                            card
                                .onDrag {
                                    draggingId = device.id
                                    return NSItemProvider(object: device.id as NSString)
                                }
                                .onDrop(of: [UTType.text], delegate: DashboardDropDelegate(
                                    target: device,
                                    devices: orderedFavorites,
                                    draggingId: $draggingId
                                ) { updated in
                                    store.send(.dashboardLayoutUpdated(updated))
                                })
                        } else {
                            card
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(store.state.isDashboardEditing ? "Done" : "Edit") {
                    store.send(.dashboardEditingChanged(!store.state.isDashboardEditing))
                }
            }
        }
        .background(appBackground)
    }

    private var orderedFavorites: [DeviceSummary] {
        let favorites = store.state.devices.filter { $0.isFavorite }
        guard !store.state.dashboardLayout.isEmpty else {
            return favorites.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        let layoutMap = Dictionary(uniqueKeysWithValues: store.state.dashboardLayout.map { ($0.deviceId, $0) })
        return favorites.sorted { lhs, rhs in
            let left = layoutMap[lhs.id]
            let right = layoutMap[rhs.id]
            switch (left, right) {
            case let (left?, right?):
                if left.row != right.row { return left.row < right.row }
                return left.column < right.column
            case (nil, nil):
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            }
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 16)]
    }

    private var appBackground: some View {
        if #available(iOS 26, macOS 26, *) {
            return AnyView(
                LinearGradient(
                    colors: [.blue.opacity(0.15), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
        }
        return AnyView(Color.clear.ignoresSafeArea())
    }
}

private struct DashboardDropDelegate: DropDelegate {
    let target: DeviceSummary
    let devices: [DeviceSummary]
    @Binding var draggingId: String?
    let onReorder: ([DashboardPlacement]) -> Void

    init(
        target: DeviceSummary,
        devices: [DeviceSummary],
        draggingId: Binding<String?>,
        onReorder: @escaping ([DashboardPlacement]) -> Void
    ) {
        self.target = target
        self.devices = devices
        self._draggingId = draggingId
        self.onReorder = onReorder
    }

    func dropEntered(info: DropInfo) {
        guard let draggingId, draggingId != target.id else { return }
        guard let fromIndex = devices.firstIndex(where: { $0.id == draggingId }),
              let toIndex = devices.firstIndex(where: { $0.id == target.id }) else { return }
        let updated = reordered(from: fromIndex, to: toIndex)
        onReorder(updated)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingId = nil
        return true
    }

    private func reordered(from: Int, to: Int) -> [DashboardPlacement] {
        var list = devices
        let item = list.remove(at: from)
        list.insert(item, at: to)
        return list.enumerated().map { index, device in
            DashboardPlacement(deviceId: device.id, row: index / 2, column: index % 2, span: 1)
        }
    }
}
