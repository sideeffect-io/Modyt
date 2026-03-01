import SwiftUI

struct GroupRow: View {
    let group: Group
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(group.name)
                .font(.system(.headline, design: .rounded))
                .lineLimit(1)

            Spacer(minLength: 8)

            FavoriteOrbButton(
                isFavorite: group.isFavorite,
                action: onToggleFavorite
            )
            .disabled(group.memberIdentifiers.isEmpty)
            .opacity(group.memberIdentifiers.isEmpty ? 0.5 : 1)
        }
        .padding(16)
        .glassCard(cornerRadius: 22)
    }
}
