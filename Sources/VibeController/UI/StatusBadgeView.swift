import SwiftUI

struct StatusBadgeView: View {
    let state: AppStatusBadgeState

    var body: some View {
        Text(state.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(state.color)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(state.color.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(state.color.opacity(0.3), lineWidth: 1)
            )
    }
}
