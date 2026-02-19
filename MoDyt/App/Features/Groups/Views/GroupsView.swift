import SwiftUI

struct GroupsView: View {
    @Environment(\.groupsStoreFactory) private var groupsStoreFactory

    var body: some View {
        WithStoreView(factory: groupsStoreFactory.make) { store in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    listHeader
                        .padding(.horizontal, 2)

                    if store.state.groups.isEmpty {
                        ContentUnavailableView(
                            "No Groups Found",
                            systemImage: "square.grid.3x3.topleft.filled",
                            description: Text("Gateway groups will appear here when available.")
                        )
                        .padding(.vertical, 24)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(store.state.groups) { group in
                                GroupRow(
                                    group: group,
                                    onToggleFavorite: { store.send(.toggleFavorite(group.uniqueId)) }
                                )
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .navigationTitle("Groups")
            .task {
                store.send(.onAppear)
            }
            .refreshable {
                store.send(.refreshRequested)
            }
        }
    }

    private var listHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Device Groups")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text("Manage gateway groups and choose which ones should appear on the dashboard.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppColors.cloud.opacity(0.33),
                            AppColors.aurora.opacity(0.21)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .glassCard(cornerRadius: 24, interactive: false)
    }
}
