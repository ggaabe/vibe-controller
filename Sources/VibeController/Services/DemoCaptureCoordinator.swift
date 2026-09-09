import AppKit
import Combine
import ScreenCaptureKit
import SwiftUI

struct DemoCaptureDisplay: Identifiable {
    var id: CGDirectDisplayID
    var name: String
    var width: Int
    var height: Int
}

enum DemoCapturePhase: Equatable {
    case idle, preparing, recording, saving, exporting
    var isBusy: Bool { self != .idle }
}

struct DemoCaptureManifest: Codable {
    var schemaVersion = 1
    var take: String
    var startedAt: String
    var startHostTime: Double
    var appVersion: String
    var status: String
    var displays: [DemoDisplayResult]
    var eventCount: Int = 0
    var droppedEvents: Int = 0
    var errors: [String] = []
    var followCursor: Bool?
    var followMovie: String?
    var followExportNote: String?
    var timing = "Event time is seconds from startHostTime on CMClockGetHostTimeClock. Video time = event time - that display's firstFrameSessionTime. Source PTS is converted using SCStream.synchronizationClock. Verify synchronization visually with the slates. Resolved actions are accepted mappings, not proof of delivery or visible response."
    var privacy = "Local selected displays and controller events only. No microphone, system audio, clipboard access, global keyboard logging, remote screen capture, or upload. Screen pixels can contain sensitive information."
}

@MainActor
final class DemoCaptureCoordinator: ObservableObject {
    let sink = DemoCaptureEventSink()
    @Published private(set) var phase: DemoCapturePhase = .idle { didSet { onStateChange?() } }
    @Published var selectedDisplays = Set<CGDirectDisplayID>()
    @Published private(set) var displays: [DemoCaptureDisplay] = []
    @Published var takeName = "Vibe Controller Demo"
    @Published private(set) var outputFolder: URL
    @Published private(set) var sessionFolder: URL?
    @Published private(set) var message: String?
    @Published private(set) var permissionGranted = false
    @Published private(set) var startedAt: Date?
    @Published private(set) var slateVisible = false
    @Published var followCursor = UserDefaults.standard.object(forKey: "demoCapture.followCursor") as? Bool ?? true {
        didSet { UserDefaults.standard.set(followCursor, forKey: "demoCapture.followCursor") }
    }
    @Published private(set) var followedDisplay: String?
    @Published private(set) var storage: DemoStorageSummary?
    @Published private(set) var exportProgress = 0.0
    var onStateChange: (() -> Void)?
    private var panel: NSWindow?
    private var slateWindows: [NSWindow] = []
    private var slateTask: Task<Void, Never>?
    private var operation: Task<Void, Never>?
    private var recorders: [DemoDisplayRecorder] = []
    private var journal: DemoCaptureJournal?
    private var manifest: DemoCaptureManifest?
    private var markerNumber = 0
    private var isQuitting = false
    private var followMonitor: DemoDisplayFollowMonitor?
    private var followExporter: DemoFollowExporter?
    private var storageTask: Task<Void, Never>?
    private var storageRefreshTask: Task<Void, Never>?

    init() {
        outputFolder = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vibe Controller Demo Captures", isDirectory: true)
    }

    func show() {
        refreshDisplays()
        refreshStorage()
        permissionGranted = CGPreflightScreenCaptureAccess()
        if panel == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Demo Capture"
            window.identifier = NSUserInterfaceItemIdentifier("demo-capture")
            window.contentView = NSHostingView(rootView: DemoCaptureView(capture: self))
            window.minSize = NSSize(width: 500, height: 520)
            window.isReleasedWhenClosed = false
            window.center()
            panel = window
        }
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refreshDisplays() {
        guard !phase.isBusy else { return }
        displays = NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return nil }
            return DemoCaptureDisplay(id: id, name: screen.localizedName,
                width: Int(screen.frame.width * screen.backingScaleFactor),
                height: Int(screen.frame.height * screen.backingScaleFactor))
        }
        selectedDisplays.formIntersection(Set(displays.map(\.id)))
        if selectedDisplays.isEmpty, let first = displays.first { selectedDisplays = [first.id] }
    }

    func requestPermission() {
        guard !phase.isBusy else { return }
        permissionGranted = CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
        if !permissionGranted {
            message = "Enable Vibe Controller in Privacy & Security → Screen & System Audio Recording. macOS may ask you to quit and reopen the app. Your controller permissions are separate."
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        } else { message = nil }
    }

    func chooseFolder() {
        guard !phase.isBusy else { return }
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.canCreateDirectories = true
        picker.prompt = "Save Takes Here"
        if picker.runModal() == .OK, let url = picker.url {
            outputFolder = url
            storage = nil
            storageRefreshTask?.cancel()
            storageRefreshTask = nil
            refreshStorage()
        }
    }

    func start() {
        guard !phase.isBusy, !selectedDisplays.isEmpty else { return }
        permissionGranted = CGPreflightScreenCaptureAccess()
        guard permissionGranted else { requestPermission(); return }
        message = nil
        manifest = nil
        sessionFolder = nil
        followedDisplay = nil
        exportProgress = 0
        phase = .preparing
        operation = Task { await beginTake() }
    }

    private func beginTake() async {
        do {
            let root = outputFolder
            let free = await Task.detached(priority: .utility) { DemoCaptureStorage.availableBytes(at: root) }.value
            guard DemoCaptureStorage.canStart(available: free) else {
                throw DemoCaptureError.message(free == nil
                    ? "Could not check free disk space. Choose an available recording folder and try again."
                    : "At least 5 GB of free disk space is needed to start a take. Review older recordings or choose another disk.")
            }
            let available = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let selected = displays.filter { selectedDisplays.contains($0.id) }
            guard selected.allSatisfy({ item in available.displays.contains { $0.displayID == item.id } }) else {
                throw DemoCaptureError.message("A selected display disconnected. Refresh displays and try again.")
            }
            let identifier = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                + "-" + UUID().uuidString.prefix(6)
            let folder = outputFolder.appendingPathComponent(identifier, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            sessionFolder = folder
            let hostTime = DemoCaptureClock.now
            let newJournal = try DemoCaptureJournal(url: folder.appendingPathComponent("events.jsonl"), startHostTime: hostTime)
            journal = newJournal
            manifest = DemoCaptureManifest(take: takeName, startedAt: ISO8601DateFormatter().string(from: Date()),
                startHostTime: hostTime,
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
                status: "recording-not-finalized", displays: [])
            manifest?.followCursor = followCursor && selected.count > 1
            try saveManifest()
            try Self.readme.write(to: folder.appendingPathComponent("READ-ME.txt"), atomically: true, encoding: .utf8)
            sink.attach(newJournal)
            sink.marker("Capture requested")
            if manifest?.followCursor == true {
                let monitor = DemoDisplayFollowMonitor(displays: selected.map {
                    DemoFollowDisplay(id: $0.id, bounds: CGDisplayBounds($0.id))
                }, journal: newJournal, onChange: { [weak self] id in
                    Task { @MainActor in
                        guard let self, self.phase.isBusy else { return }
                        self.followedDisplay = self.displays.first { $0.id == id }?.name ?? "Display \(id)"
                    }
                })
                followMonitor = monitor
                monitor.start()
            }
            for item in selected {
                guard let display = available.displays.first(where: { $0.displayID == item.id }) else { continue }
                let recorder = try DemoDisplayRecorder(display: display, pixelWidth: item.width, pixelHeight: item.height,
                    folder: folder, journal: newJournal, onFailure: { [weak self] error in
                        Task { @MainActor in
                            guard let self else { return }
                            self.message = error
                            if self.phase == .recording { self.stop() }
                        }
                    })
                recorders.append(recorder)
                try await recorder.start()
                manifest?.displays.append(await recorder.snapshot())
                try saveManifest()
            }
            guard message == nil else { throw DemoCaptureError.message(message!) }
            startedAt = Date()
            markerNumber = 0
            phase = .recording
            startStorageMonitoring()
            sink.marker("All selected displays recording")
            showSlate(label: "START")
            panel?.orderOut(nil)
        } catch {
            message = error.localizedDescription
            await finishTake()
        }
    }

    func stop() {
        guard phase == .recording else { return }
        phase = .saving
        operation = Task { await finishTake() }
    }

    /// Used by applicationShouldTerminate: keep the app alive until video
    /// containers and the event journal have been finalized.
    func finishBeforeQuit() async {
        isQuitting = true
        followExporter?.cancel()
        await operation?.value
        if phase == .recording {
            phase = .saving
            await finishTake()
        }
    }

    private func finishTake() async {
        phase = .saving
        storageTask?.cancel()
        storageTask = nil
        dismissSlate()
        sink.marker("Capture stopping")
        let changes = await followMonitor?.stop() ?? []
        followMonitor = nil
        var results: [DemoDisplayResult] = []
        for recorder in recorders { results.append(await recorder.stop()) }
        recorders.removeAll()
        sink.detach()
        let journalResult = await journal?.finish()
        journal = nil
        if var manifest {
            manifest.displays = results
            manifest.eventCount = journalResult?.written ?? 0
            manifest.droppedEvents = journalResult?.dropped ?? 0
            manifest.errors = results.compactMap(\.error)
            if let error = journalResult?.error { manifest.errors.append(error) }
            if let message { manifest.errors.append(message) }
            if manifest.droppedEvents > 0 { manifest.errors.append("Some controller events were dropped because storage could not keep up.") }
            manifest.status = manifest.errors.isEmpty ? "complete" : "incomplete"
            self.manifest = manifest
            do { try saveManifest() }
            catch { message = "The video files were saved, but session.json could not be finalized: \(error.localizedDescription)" }
            if manifest.followCursor == true, let folder = sessionFolder {
                do {
                    let plan = try DemoFollowPlan.make(displays: results, changes: changes)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    try encoder.encode(plan).write(to: folder.appendingPathComponent("follow-plan.json"), options: .atomic)
                    if isQuitting {
                        self.manifest?.followExportNote = "App quit before review export; sources and the edit plan were saved."
                    } else {
                        startedAt = nil
                        phase = .exporting
                        let exporter = DemoFollowExporter()
                        followExporter = exporter
                        self.manifest?.followMovie = try await exporter.export(plan: plan, folder: folder,
                            freeBytes: { DemoCaptureStorage.availableBytes(at: folder) },
                            progress: { [weak self] value in Task { @MainActor in self?.exportProgress = value } })
                    }
                } catch {
                    self.manifest?.followExportNote = error.localizedDescription
                }
                followExporter = nil
                do { try saveManifest() }
                catch { message = "Could not save follow-cursor metadata: \(error.localizedDescription)" }
                if let note = self.manifest?.followExportNote, message == nil { message = note }
            }
            if message == nil { message = manifest.errors.first ?? "Take saved. Your videos and input timing are ready for editing." }
        }
        startedAt = nil
        phase = .idle
        refreshStorage()
        if !isQuitting { show() }
    }

    func addMarker() {
        guard phase == .recording else { return }
        markerNumber += 1
        sink.marker("Editorial marker \(markerNumber)")
    }

    func showSlate(label: String = "SYNC") {
        guard phase == .recording, !slateVisible else { return }
        slateVisible = true
        let tag = "\(label) \(UUID().uuidString.prefix(4))"
        sink.marker("Slate requested: \(tag) — use the visible change for camera synchronization")
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
                  selectedDisplays.contains(id) else { continue }
            let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .floating
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: DemoSyncSlate(tag: tag, displayID: id))
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            slateWindows.append(window)
        }
        slateTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            sink.marker("Slate dismissed: \(tag)")
            dismissSlate()
        }
    }

    private func dismissSlate() {
        slateTask?.cancel()
        slateTask = nil
        slateWindows.forEach { $0.close() }
        slateWindows.removeAll()
        slateVisible = false
    }

    func revealTake() {
        if let sessionFolder { NSWorkspace.shared.activateFileViewerSelecting([sessionFolder]) }
    }

    func refreshStorage() {
        guard storageRefreshTask == nil else { return }
        let root = outputFolder
        let current = phase.isBusy ? sessionFolder : nil
        storageRefreshTask = Task {
            let result = await Task.detached(priority: .utility) {
                DemoCaptureStorage.inspect(root: root, currentTake: current)
            }.value
            guard !Task.isCancelled else { return }
            if outputFolder == root { storage = result }
            storageRefreshTask = nil
        }
    }

    private func startStorageMonitoring() {
        storageTask?.cancel()
        let root = outputFolder
        storageTask = Task {
            var tick = 0
            while !Task.isCancelled, phase == .recording {
                let available = await Task.detached(priority: .utility) { DemoCaptureStorage.availableBytes(at: root) }.value
                guard !Task.isCancelled, phase == .recording else { return }
                if DemoCaptureStorage.shouldStop(available: available) {
                    message = available == nil
                        ? "Recording stopped because the destination disk could no longer be checked. Your captured files are being saved."
                        : "Recording stopped to preserve 2 GB of free disk space. Your captured files are being saved."
                    stop()
                    return
                }
                if tick % 5 == 0 { refreshStorage() }
                tick += 1
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func reviewOlderTakes() {
        guard !phase.isBusy, let older = storage?.olderTakes, !older.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(older)
    }

    func showRecordingsFolder() {
        guard FileManager.default.fileExists(atPath: outputFolder.path) else { return }
        NSWorkspace.shared.open(outputFolder)
    }

    var estimatedBytesPerMinute: Int64 {
        displays.filter { selectedDisplays.contains($0.id) }.reduce(0) { total, display in
            let (width, height) = DemoDisplayRecorder.dimensions(width: display.width, height: display.height)
            return total + Int64(DemoDisplayRecorder.targetBitrate(width: width, height: height)) * 60 / 8
        }
    }

    private func saveManifest() throws {
        guard let manifest, let sessionFolder else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: sessionFolder.appendingPathComponent("session.json"), options: .atomic)
    }

    private static let readme = """
    VIBE CONTROLLER — DEMO CAPTURE

    Each display-<id>.mov is a separate SDR H.264 video (up to 4K, up to 60 fps,
    native display aspect ratio). No audio is recorded. Use your phone narration.
    session.json lists dimensions, timing offsets, dropped frames/events and errors.
    A take is only finalized when status is complete or incomplete. Preserve any
    partial files after an error; do not treat them as a completed recording.

    When Follow Cursor is enabled for two or more selected local displays,
    follow-cursor.mp4 is an additional 1080p/30 fps review edit. Full-resolution
    originals stay untouched. follow-plan.json lists the source cuts and session
    origin; display_changed events record stable cursor crossings. The review
    movie omits startup/tail time not shared by every source. The tracker samples
    at about 30 Hz and ignores crossings shorter than 120 ms. Unselected/remote
    displays do not become capture sources. Check followExportNote if export was
    skipped or cancelled; the plan and originals can still be used in the edit.

    STORAGE: the app requires 5 GB free to begin, checks space during recording,
    and attempts to stop/finalize below 2 GB. Review copies also have space checks.
    The capture panel flags takes older than 14 days for manual review in Finder.
    Nothing is automatically deleted. Moving a take to Trash does not reclaim
    disk space until Trash is emptied; preserve exported work/backups first.

    events.jsonl is newline-delimited JSON for custom editing tools, not a native
    Resolve import. controller_input contains raw states (analog updates capped
    at 60 Hz; button/trigger edges bypass throttling). resolved_action describes
    an accepted mapping once per activation, not every repeat tick or OS effect.
    A modifier's solo action is logged at release. marker is an editorial/sync
    cue. video_anchor connects source timestamps to host-clock and video time.

    TIME: event.time is seconds from the session's host-clock origin. To place
    an event on a display video, subtract that display's firstFrameSessionTime.
    Negative results happened before that video's first frame. Clocks are local
    to this Mac, NOT shared with the phone or another Mac. Use the visible START
    and END slates to align phone footage and check drift, not callback time.
    Input, accepted mapping and visible response can happen at different times.

    Record the other Mac locally using its built-in screen recorder. Universal
    Control does not return its screen or foreground-app state. Film a distinct
    visible cue on that Mac at both ends too; these timestamps cannot sync it.

    EDIT: track each filmed laptop screen in Resolve/Fusion, corner-pin the clean
    recording into it, then animate a larger panel for important interactions.
    Rotoscope hands/controller/forearms from the original phone footage ABOVE
    the floating panel. Keep an uncut POV moment proving the physical interaction.

    PRIVACY: capture includes everything visible on selected displays. Hide
    notifications and sensitive windows. No microphone/system audio, clipboard
    reads, global keyboard logging or automatic upload occurs.
    """
}
