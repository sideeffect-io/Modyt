import SwiftUI

struct FavoriteOrbButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let isFavorite: Bool
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isFavorite
                                ? [Color.yellow.opacity(0.95), AppColors.ember.opacity(0.9)]
                                : unfavoritedBackgroundColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Circle()
                    .stroke(strokeColor, lineWidth: colorScheme == .light ? 1.2 : 1)

                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: symbolSize, weight: .bold))
                    .foregroundStyle(iconColor)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isFavorite)
            }
        }
        .buttonStyle(.plain)
        .frame(width: size, height: size)
        .shadow(color: shadowColor, radius: colorScheme == .light ? 6 : 4, x: 0, y: size >= 36 ? 2 : 1)
        .accessibilityLabel(isFavorite ? "Remove favorite" : "Add favorite")
    }

    init(isFavorite: Bool, size: CGFloat = 36, action: @escaping () -> Void) {
        self.isFavorite = isFavorite
        self.size = size
        self.action = action
    }

    private var symbolSize: CGFloat {
        max(12, size * 0.39)
    }

    private var unfavoritedBackgroundColors: [Color] {
        if colorScheme == .light {
            return [AppColors.mist.opacity(0.95), AppColors.cloud.opacity(0.9)]
        }
        return [.white.opacity(0.24), .white.opacity(0.16)]
    }

    private var iconColor: Color {
        if isFavorite {
            return AppColors.midnight
        }
        return colorScheme == .light ? AppColors.slate : .white.opacity(0.85)
    }

    private var strokeColor: Color {
        if isFavorite {
            return .white.opacity(0.85)
        }
        return colorScheme == .light ? AppColors.slate.opacity(0.35) : .white.opacity(0.35)
    }

    private var shadowColor: Color {
        guard colorScheme == .light else { return .clear }
        return AppColors.midnight.opacity(isFavorite ? 0.18 : 0.14)
    }
}
