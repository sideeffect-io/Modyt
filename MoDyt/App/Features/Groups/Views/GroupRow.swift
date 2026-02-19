import SwiftUI

struct GroupRow: View {
    let group: GroupRecord
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
            .disabled(group.memberUniqueIds.isEmpty)
            .opacity(group.memberUniqueIds.isEmpty ? 0.5 : 1)
        }
        .padding(16)
        .glassCard(cornerRadius: 22)
    }
}
