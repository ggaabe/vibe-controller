import SwiftUI

enum ProductSurfaceStyle {
    static let cornerRadius: CGFloat = 20

    static func fill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.055)
            : Color.white.opacity(0.72)
    }

    static func border(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.075)
            : Color.black.opacity(0.075)
    }
}

private struct ProductPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: ProductSurfaceStyle.cornerRadius, style: .continuous)
                    .fill(ProductSurfaceStyle.fill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ProductSurfaceStyle.cornerRadius, style: .continuous)
                    .stroke(ProductSurfaceStyle.border(for: colorScheme), lineWidth: 1)
            )
    }
}

extension View {
    func productPanel(padding: CGFloat = 18) -> some View {
        modifier(ProductPanelModifier(padding: padding))
    }
}

struct ProductSectionTitle: View {
    let title: String
    let subtitle: String?
    let symbol: String

    init(_ title: String, subtitle: String? = nil, symbol: String) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct ReadinessRow: View {
    let title: String
    let detail: String
    let isReady: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "circle.dotted")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isReady ? Color.green : Color.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.075), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
