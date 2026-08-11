import SwiftUI

struct CursorSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var advancedExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Cursor")
                .font(.title2.weight(.semibold))

            VStack(spacing: 14) {
                Picker("Primary cursor stick", selection: appModel.primaryStickBinding()) {
                    ForEach(StickAssignment.allCases) { assignment in
                        Text(assignment.displayName).tag(assignment)
                    }
                }
                Picker("Precision cursor stick", selection: appModel.precisionStickBinding()) {
                    ForEach(StickAssignment.allCases) { assignment in
                        Text(assignment.displayName).tag(assignment)
                    }
                }
            }
            .pickerStyle(.menu)

            SliderSettingRow(
                title: "Primary speed",
                value: appModel.cursorBinding(\.primarySpeed),
                range: 400...4200,
                formatter: { "\(Int($0.rounded())) px/s" }
            )

            Toggle(isOn: appModel.cursorBinding(\.flickBoostEnabled)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Flick boost")
                    Text("Adds speed after a very fast full-stick flick.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .frame(minHeight: 40)
            .accessibilityHint("Temporarily increases primary cursor speed after a very fast full-stick sweep.")

            SliderSettingRow(
                title: "Precision speed",
                value: appModel.cursorBinding(\.precisionSpeed),
                range: 100...1800,
                formatter: { "\(Int($0.rounded())) px/s" }
            )

            SliderSettingRow(
                title: "Dead zone",
                value: appModel.cursorBinding(\.deadZone),
                range: 0.02...0.35,
                formatter: { String(format: "%.2f", $0) }
            )

            DisclosureGroup("Advanced", isExpanded: $advancedExpanded) {
                VStack(spacing: 14) {
                    SliderSettingRow(
                        title: "Smoothing",
                        value: appModel.cursorBinding(\.smoothing),
                        range: 0...1,
                        formatter: { String(format: "%.2f", $0) }
                    )

                    SliderSettingRow(
                        title: "Response curve",
                        value: appModel.cursorBinding(\.responseCurve),
                        range: 1.0...2.6,
                        formatter: { String(format: "%.2f", $0) }
                    )

                    Toggle("Acceleration", isOn: appModel.cursorBinding(\.accelerationEnabled))

                    Toggle("Invert primary X", isOn: appModel.cursorBinding(\.invertPrimaryX))
                    Toggle("Invert primary Y", isOn: appModel.cursorBinding(\.invertPrimaryY))
                    Toggle("Invert precision X", isOn: appModel.cursorBinding(\.invertPrecisionX))
                    Toggle("Invert precision Y", isOn: appModel.cursorBinding(\.invertPrecisionY))

                    SliderSettingRow(
                        title: "Horizontal multiplier",
                        value: appModel.cursorBinding(\.horizontalSpeedMultiplier),
                        range: 0.2...2.0,
                        formatter: { String(format: "%.2fx", $0) }
                    )

                    SliderSettingRow(
                        title: "Vertical multiplier",
                        value: appModel.cursorBinding(\.verticalSpeedMultiplier),
                        range: 0.2...2.0,
                        formatter: { String(format: "%.2fx", $0) }
                    )
                }
                .padding(.top, 10)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

struct SliderSettingRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let formatter: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(formatter(value))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}
