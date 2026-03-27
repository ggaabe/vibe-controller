import SwiftUI

struct StatusBadgeView: View {
    let state: AppStatusBadgeState

    var body: some View {
        Text(state.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(state.color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
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
