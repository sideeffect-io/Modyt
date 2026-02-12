import SwiftUI

struct ScenesView: View {
    @Environment(\.scenesStoreFactory) private var scenesStoreFactory

    var body: some View {
        WithStoreView(factory: scenesStoreFactory.make) { store in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    listHeader
                        .padding(.horizontal, 2)

                    if store.state.scenes.isEmpty {
                        ContentUnavailableView(
                            "No Scenes Found",
                            systemImage: "sparkles.rectangle.stack",
                            description: Text("Automation scenarios from your gateway will appear here.")
                        )
                        .padding(.vertical, 24)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(store.state.scenes) { scene in
                                SceneRow(
                                    scene: scene,
                                    onToggleFavorite: { store.send(.toggleFavorite(scene.uniqueId)) }
                                )
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .navigationTitle("Scenes")
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
            Text("Automation Scenes")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text("Review every scenario configured in your gateway and star the ones you want on the dashboard.")
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
                            AppColors.aurora.opacity(0.32),
                            AppColors.cloud.opacity(0.22)
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
