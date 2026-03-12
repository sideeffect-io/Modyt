import SwiftUI

struct FavoriteOrbButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let isFavorite: Bool
    let size: CGFloat
    let accessibilityContext: String?
    let action: () -> Void

    private static let minimumTouchTarget: CGFloat = 44

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
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .frame(
            width: max(size, Self.minimumTouchTarget),
            height: max(size, Self.minimumTouchTarget)
        )
        .contentShape(.rect)
        .shadow(color: shadowColor, radius: colorScheme == .light ? 6 : 4, x: 0, y: size >= 36 ? 2 : 1)
        .accessibilityLabel(accessibilityLabel)
    }

    init(
        isFavorite: Bool,
        size: CGFloat = 36,
        accessibilityContext: String? = nil,
        action: @escaping () -> Void
    ) {
        self.isFavorite = isFavorite
        self.size = size
        self.accessibilityContext = accessibilityContext
        self.action = action
    }

    private var accessibilityLabel: String {
        if let accessibilityContext, accessibilityContext.isEmpty == false {
            return isFavorite
                ? "Remove \(accessibilityContext) from favorites"
                : "Add \(accessibilityContext) to favorites"
        }

        return isFavorite ? "Remove favorite" : "Add favorite"
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
