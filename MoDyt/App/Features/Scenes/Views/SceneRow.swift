import SwiftUI

struct SceneRow: View {
    let scene: SceneRecord
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: sceneSymbolName(picto: scene.picto, type: scene.type))
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 24, height: 24)
                .foregroundStyle(.primary)

            Text(scene.name)
                .font(.system(.headline, design: .rounded))
                .lineLimit(1)

            Spacer(minLength: 8)

            FavoriteOrbButton(
                isFavorite: scene.isFavorite,
                action: onToggleFavorite
            )
        }
        .padding(16)
        .glassCard(cornerRadius: 22)
    }
}
