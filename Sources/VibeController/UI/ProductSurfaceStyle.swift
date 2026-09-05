import SwiftUI

enum ProductSurfaceStyle {
    static let cornerRadius: CGFloat = 14

    static func canvas(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.14, green: 0.155, blue: 0.18)
            : Color(red: 0.925, green: 0.936, blue: 0.952)
    }

    static func fill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.035)
            : Color.white.opacity(0.65)
    }

    static func border(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.07)
            : Color.black.opacity(0.06)
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
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 19)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
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
        .padding(.vertical, 6)
    }
}
