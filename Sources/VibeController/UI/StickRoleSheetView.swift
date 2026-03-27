import SwiftUI

struct StickRoleSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel

    let stickSide: StickSide

    @State private var choice: StickRoleChoice = .off

    var body: some View {
        let snapshot = stickSide == .left ? appModel.controllerSnapshot.leftStick : appModel.controllerSnapshot.rightStick

        VStack(alignment: .leading, spacing: 18) {
            Text(stickSide.displayName)
                .font(.title2.weight(.semibold))

            Text("Assign this stick to primary cursor movement, precision cursor movement, or turn it off.")
                .foregroundStyle(.secondary)

            HStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.05))
                        .frame(width: 110, height: 110)
                    Circle()
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                        .frame(width: 110, height: 110)
                    Circle()
                        .fill(Color.accentColor.opacity(0.25))
                        .frame(width: 28, height: 28)
                        .offset(x: snapshot.x * 26, y: -snapshot.y * 26)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Live vector")
                        .font(.headline)
                    Text(String(format: "x %.2f   y %.2f", snapshot.x, snapshot.y))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Role", selection: $choice) {
                ForEach(StickRoleChoice.allCases) { role in
                    Text(role.displayName).tag(role)
                }
            }
            .pickerStyle(.radioGroup)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    appModel.assignStick(stickSide, role: choice)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            choice = appModel.roleChoice(for: stickSide)
        }
    }
}
