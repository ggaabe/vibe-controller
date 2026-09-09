import SwiftUI

struct DemoCaptureView: View {
    @ObservedObject var capture: DemoCaptureCoordinator

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "record.circle").font(.system(size: 32)).foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("A clean take. Ready for the edit.").font(.title2.weight(.semibold))
                            Text("Screen recordings and controller timing for your next demo.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    TextField("Take name", text: $capture.takeName).textFieldStyle(.roundedBorder)
                        .disabled(capture.phase.isBusy)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("DISPLAYS ON THIS MAC").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Button("Refresh", action: capture.refreshDisplays).disabled(capture.phase.isBusy)
                        }
                        ForEach(capture.displays) { display in
                            Toggle(isOn: Binding(
                                get: { capture.selectedDisplays.contains(display.id) },
                                set: { selected in
                                    if selected { capture.selectedDisplays.insert(display.id) }
                                    else { capture.selectedDisplays.remove(display.id) }
                                }
                            )) {
                                HStack {
                                    Image(systemName: "display")
                                    Text(display.name)
                                    Spacer()
                                    Text("\(display.width) × \(display.height)").foregroundStyle(.secondary).monospacedDigit()
                                }
                            }.frame(minHeight: 40).disabled(capture.phase.isBusy)
                        }
                        Text("One editable video per display · up to 4K / 60 fps · cursor included")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Follow cursor across selected displays", isOn: $capture.followCursor)
                            .disabled(capture.phase.isBusy || capture.selectedDisplays.count < 2)
                            .frame(minHeight: 40)
                        Text(capture.selectedDisplays.count < 2
                            ? "Select at least two displays above. Both are recorded continuously; an extra 1080p review movie follows your cursor after Stop & Save."
                            : "Creates a 1080p follow-cursor review movie after Stop & Save. Your separate full-resolution recordings are kept for editing.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let display = capture.followedDisplay, capture.phase == .recording {
                            Label("Following: \(display)", systemImage: "cursorarrow.and.square.on.square.dashed")
                                .font(.callout).foregroundStyle(.tint)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Nothing starts until you press Record", systemImage: "lock.shield")
                            .font(.subheadline.weight(.semibold))
                        Text("Everything visible on selected displays will be saved locally. Hide sensitive windows and notifications first. No microphone or system audio is recorded, so your dictation microphone stays free.")
                        Text("Record the other Mac separately. Universal Control cannot send its screen back here.")
                    }.font(.callout).foregroundStyle(.secondary)
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Save takes to").font(.caption).foregroundStyle(.secondary)
                            Text(capture.outputFolder.path).font(.caption).lineLimit(2).textSelection(.enabled)
                        }
                        Spacer()
                        Button("Choose…", action: capture.chooseFolder).disabled(capture.phase.isBusy)
                    }
                    storageSection
                    if let message = capture.message {
                        Label(message, systemImage: "info.circle").font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !capture.permissionGranted {
                        Button("Allow Screen Recording…", action: capture.requestPermission)
                            .controlSize(.large).frame(minHeight: 40)
                        Text("If you just enabled it in Settings, press Record to check again. A relaunch may be required by macOS.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if capture.phase == .recording {
                        HStack {
                            Button("Sync Slate") { capture.showSlate() }.disabled(capture.slateVisible)
                            Button("End Slate") { capture.showSlate(label: "END") }.disabled(capture.slateVisible)
                            Button("Add Marker", action: capture.addMarker)
                        }.controlSize(.large)
                        Text("Start your phone first. A START slate appears automatically; film an END slate before stopping. Keep the controller visible below the screens.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if capture.phase == .exporting {
                        ProgressView(value: capture.exportProgress) {
                            Text("Building follow-cursor review movie…")
                        } currentValueLabel: {
                            Text(capture.exportProgress, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                        }
                        Text("The original screen recordings are already saved. Quitting cancels only this extra review copy.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(26)
            }
            Divider()
            HStack(spacing: 12) {
                Circle().fill(capture.phase == .recording ? Color.red : Color.secondary.opacity(0.4)).frame(width: 8, height: 8)
                if let start = capture.startedAt {
                    Text(start, style: .timer).monospacedDigit().font(.system(.body, design: .monospaced))
                } else {
                    Text(capture.phase == .preparing ? "Preparing…" : capture.phase == .saving ? "Saving take…" : capture.phase == .exporting ? "Making review movie…" : "Ready when you are")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if capture.sessionFolder != nil, !capture.phase.isBusy {
                    Button("Show Take", action: capture.revealTake)
                }
                if capture.phase == .recording {
                    Button("Stop & Save", action: capture.stop).tint(.red).buttonStyle(.borderedProminent)
                } else {
                    Button("Record", action: capture.start).buttonStyle(.borderedProminent)
                        .disabled(capture.phase.isBusy || capture.selectedDisplays.isEmpty)
                }
            }.controlSize(.large).frame(minHeight: 48).padding(.horizontal, 20).padding(.vertical, 10)
        }
        .accessibilityIdentifier("demo-capture.panel")
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Storage", systemImage: "internaldrive").font(.subheadline.weight(.semibold))
            if let storage = capture.storage {
                Text("\(storage.takeCount) takes · \(bytes(storage.takeBytes)) used · \(storage.availableBytes.map(bytes) ?? "Unknown space") free")
                    .font(.callout).monospacedDigit()
                if capture.phase == .recording {
                    Text("Current take: \(bytes(storage.currentTakeBytes))").font(.caption).monospacedDigit()
                }
                if !storage.olderTakes.isEmpty {
                    Label("\(storage.olderTakes.count) takes are over 14 days old. Review and remove what you no longer need.", systemImage: "clock.badge.exclamationmark")
                        .font(.callout).foregroundStyle(.orange)
                    Button("Review Older Takes in Finder", action: capture.reviewOlderTakes)
                        .disabled(capture.phase.isBusy).frame(minHeight: 40)
                }
            }
            Text("About \(bytes(capture.estimatedBytesPerMinute)) per minute for selected displays, plus the review movie. Requires 5 GB free; attempts to stop and save below 2 GB.")
                .font(.caption).foregroundStyle(.secondary)
            Text("No automatic deletion. Keep your final edit or a backup before removing takes. Files in Trash still occupy disk space until you empty it.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Show Recordings", action: capture.showRecordingsFolder).disabled(capture.storage?.takeCount == 0)
                Button("Refresh Storage", action: capture.refreshStorage)
            }.frame(minHeight: 40)
        }
    }
}

struct DemoSyncSlate: View {
    let tag: String
    let displayID: UInt32
    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.10, blue: 0.18)
            VStack(spacing: 18) {
                Text("VIBE CONTROLLER").font(.system(size: 24, weight: .semibold, design: .monospaced)).tracking(5)
                Text(tag).font(.system(size: 76, weight: .bold, design: .monospaced)).monospacedDigit()
                Text("DISPLAY \(displayID)").font(.system(size: 18, design: .monospaced))
                Text("Match this visible slate in your phone and screen footage.").font(.title3)
            }.foregroundStyle(.white)
        }.ignoresSafeArea()
    }
}
