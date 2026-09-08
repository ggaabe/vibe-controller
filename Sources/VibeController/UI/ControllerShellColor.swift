import SwiftUI

/// Artwork-only preference; deliberately separate from controller shortcut profiles.
enum ControllerShellColor: String, CaseIterable, Identifiable {
    case original, graphite, white, blue, pink, green

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    func palette(for family: ControllerFamily) -> [String] {
        switch self {
        case .original:
            return (family == .playStation ? Self.white : Self.graphite).palette(for: family)
        case .graphite: return ["#555B65", "#393E47", "#242830"]
        case .white: return ["#FFFFFF", "#E5E8EF", "#A6AEBB"]
        case .blue: return ["#6CAFFF", "#2874D4", "#154580"]
        case .pink: return ["#FF9EC8", "#E95394", "#9F285D"]
        case .green: return ["#B8EA75", "#76B83C", "#386623"]
        }
    }

    func swatch(for family: ControllerFamily) -> Color {
        let hex = UInt32(palette(for: family)[1].dropFirst(), radix: 16)!
        return Color(
            .sRGB, red: Double((hex >> 16) & 255) / 255,
            green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }

    func usesDarkCheckmark(for family: ControllerFamily) -> Bool {
        self == .white || self == .green || (self == .original && family == .playStation)
    }
}

struct ControllerColorPicker: View {
    @Binding var selection: ControllerShellColor
    let family: ControllerFamily
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 7) {
                swatch(selection, diameter: 16)
                Text("Color").font(.caption.weight(.medium))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Controller color")
        .accessibilityValue(selection.displayName)
        .accessibilityIdentifier("controller-map.color")
        .help("Change the controller shell color. Your choice is remembered for this layout.")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Controller color").font(.headline)
                Text("\(family.displayName) shell · Appearance only")
                    .font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(72), spacing: 8), count: 3), spacing: 8) {
                    ForEach(ControllerShellColor.allCases) { color in
                        Button {
                            selection = color
                        } label: {
                            VStack(spacing: 6) {
                                swatch(color, diameter: 32)
                                    .overlay {
                                        if selection == color {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(color.usesDarkCheckmark(for: family) ? Color.black : .white)
                                        }
                                    }
                                Text(color.displayName).font(.caption)
                                    .foregroundStyle(.primary)
                            }
                            .frame(width: 72, height: 66)
                            .background(
                                Color.accentColor.opacity(selection == color ? 0.12 : 0),
                                in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(color.displayName)
                        .accessibilityAddTraits(selection == color ? .isSelected : [])
                        .accessibilityIdentifier("controller-color.\(color.rawValue)")
                        .help("\(color.displayName) shell")
                    }
                }
            }
            .padding(16)
        }
    }

    private func swatch(_ color: ControllerShellColor, diameter: CGFloat) -> some View {
        Circle()
            .fill(color.swatch(for: family))
            .overlay(Circle().strokeBorder((colorScheme == .dark ? Color.white : .black).opacity(0.15), lineWidth: 1))
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}
