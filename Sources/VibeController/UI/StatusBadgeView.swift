import SwiftUI

struct StatusBadgeView: View {
    let state: AppStatusBadgeState

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(state.color).frame(width: 6, height: 6)
            Text(state.title).font(.caption.weight(.medium))
        }
        .foregroundStyle(state.color)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(state.color.opacity(0.12))
        )
    }
}
