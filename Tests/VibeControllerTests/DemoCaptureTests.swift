import AVFoundation
import Foundation
import XCTest
@testable import VibeController

@MainActor
final class DemoCaptureTests: XCTestCase {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VibeCaptureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func snapshot(_ pressed: Set<ControllerControlID> = []) -> ControllerSnapshot {
        var value = ControllerSnapshot.disconnected
        value.isConnected = true
        value.pressedControls = pressed
        return value
    }

    private func readEvents(_ url: URL) throws -> [DemoCaptureEvent] {
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
            try JSONDecoder().decode(DemoCaptureEvent.self, from: Data($0.utf8))
        }
    }

    func testOptionMenuVisibilityAndRecordingEscapeHatch() {
        XCTAssertFalse(DemoCaptureAppMenu.shouldShow(optionHeld: false, isCapturing: false))
        XCTAssertTrue(DemoCaptureAppMenu.shouldShow(optionHeld: true, isCapturing: false))
        XCTAssertTrue(DemoCaptureAppMenu.shouldShow(optionHeld: false, isCapturing: true))
    }

    func testAnalogThrottleNeverHidesButtonTriggerStickOrDisconnectEdges() {
        var gate = DemoInputGate()
        var value = snapshot()
        XCTAssertTrue(gate.accepts(value, at: 0))
        value.leftStick.x = 0.1
        XCTAssertFalse(gate.accepts(value, at: 0.001))
        value.pressedControls = [.buttonEast]
        XCTAssertTrue(gate.accepts(value, at: 0.002))
        value.pressedControls = []
        XCTAssertTrue(gate.accepts(value, at: 0.003))
        value.analogValues[.rightTrigger] = 0.20
        XCTAssertTrue(gate.accepts(value, at: 0.004))
        value.analogValues[.rightTrigger] = 0
        XCTAssertTrue(gate.accepts(value, at: 0.005))
        value.leftStick.pressed = true
        XCTAssertTrue(gate.accepts(value, at: 0.006))
        value.isConnected = false
        XCTAssertTrue(gate.accepts(value, at: 0.007))
        XCTAssertFalse(gate.accepts(value, at: 0.008))
        XCTAssertTrue(gate.accepts(value, at: 0.025))
    }

    func testJournalBoundedBacklogAndDrain() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let queue = DispatchQueue(label: "test.capture.blocked-storage")
        queue.suspend()
        let url = dir.appendingPathComponent("events.jsonl")
        let journal = try DemoCaptureJournal(url: url, startHostTime: 0, capacity: 2, queue: queue)
        for index in 0..<100 {
            journal.submit { DemoCaptureEvent(kind: "marker", time: Double(index), label: "test") }
        }
        queue.resume()
        let result = await journal.finish()
        XCTAssertEqual(result.written, 2)
        XCTAssertEqual(result.dropped, 98)
        XCTAssertNil(result.error)
        XCTAssertEqual(try readEvents(url).map(\.time), [0, 1])
        journal.submit { DemoCaptureEvent(kind: "marker", time: 999) }
        XCTAssertEqual(try readEvents(url).count, 2)
    }

    func testSinkIsOptInAndDetachesWithoutLeakingIntoAnotherTake() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sink = DemoCaptureEventSink()
        sink.marker("not recording")
        sink.input(snapshot([.buttonEast]))
        for index in 1...2 {
            let url = dir.appendingPathComponent("\(index).jsonl")
            let journal = try DemoCaptureJournal(url: url, startHostTime: DemoCaptureClock.now)
            sink.attach(journal)
            sink.input(snapshot([.buttonEast]))
            sink.marker("take \(index)")
            sink.detach()
            sink.marker("not recording")
            let result = await journal.finish()
            XCTAssertEqual(result.written, 2)
            let events = try readEvents(url)
            XCTAssertEqual(events.first?.pressed, [ControllerControlID.buttonEast.rawValue])
            XCTAssertEqual(events.last?.label, "take \(index)")
            XCTAssertTrue(events.allSatisfy { $0.time >= 0 })
        }
    }

    func testCaptureDoesNotBlockShortcutsWhenDiskAndMainThreadAreBlocked() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let disk = DispatchQueue(label: "test.capture.slow-disk")
        disk.suspend()
        let journal = try DemoCaptureJournal(url: dir.appendingPathComponent("events.jsonl"),
            startHostTime: DemoCaptureClock.now, capacity: 4, queue: disk)
        let sink = DemoCaptureEventSink()
        sink.attach(journal)
        let finished = DispatchSemaphore(value: 0)
        let engine = ActionEngine(cursorEngine: CursorEngine(), shortcutOutput: { shortcut, down in
            if shortcut.keyCode == 63 && !down { finished.signal() }
        }, demoCaptureSink: sink)
        engine.accessibilityTrusted = true
        engine.configureRealtimeActions(profile: .gabesDefaults, applicationBundleIdentifier: nil, enabled: true)
        let relay = ControllerInputRelay(inputQueue: DispatchQueue(label: "test.capture.input", qos: .userInteractive))
        relay.setRealtimeHandler { sink.input($0) }
        relay.setRealtimeActionHandler { engine.receiveRealtimeActions($0) }
        let started = DemoCaptureClock.now
        relay.receiveGameController(snapshot([.buttonEast]))
        relay.receiveGameController(snapshot())
        relay.receiveGameController(snapshot([.rightTrigger]))
        relay.receiveGameController(snapshot())
        XCTAssertEqual(finished.wait(timeout: .now() + 0.5), .success)
        print("Capture enabled, storage/main blocked: screenshot + dictation in \((DemoCaptureClock.now - started) * 1000) ms")
        sink.detach()
        disk.resume()
        _ = await journal.finish()
        engine.cancelAll()
    }

    func testResolvedModifierActionAndSoloReleaseAreLoggedOnce() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("events.jsonl")
        let journal = try DemoCaptureJournal(url: url, startHostTime: DemoCaptureClock.now)
        let sink = DemoCaptureEventSink()
        sink.attach(journal)
        let engine = ActionEngine(cursorEngine: CursorEngine(), shortcutOutput: { _, _ in }, demoCaptureSink: sink)
        engine.accessibilityTrusted = true
        let profile = ControllerProfile.gabesDefaults
        engine.process(snapshot: snapshot([.rightShoulder]), profile: profile)
        engine.process(snapshot: snapshot([.rightShoulder, .buttonNorth]), profile: profile)
        engine.process(snapshot: snapshot([.rightShoulder, .buttonNorth]), profile: profile)
        engine.process(snapshot: snapshot(), profile: profile)
        engine.process(snapshot: snapshot([.leftShoulder]), profile: profile)
        engine.process(snapshot: snapshot(), profile: profile)
        sink.detach()
        _ = await journal.finish()
        let events = try readEvents(url)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?.modifier, ControllerControlID.rightShoulder.rawValue)
        XCTAssertEqual(events.first?.control, ControllerControlID.buttonNorth.rawValue)
        XCTAssertEqual(events.last?.label, "modifier-release: Escape")
        engine.cancelAll()
    }

    func testVideoDimensionsPreserveAspectAndEvenEncoderSizes() {
        let wide = DemoDisplayRecorder.dimensions(width: 5120, height: 2880)
        XCTAssertEqual(wide.0, 3840); XCTAssertEqual(wide.1, 2160)
        let portrait = DemoDisplayRecorder.dimensions(width: 2160, height: 3840)
        XCTAssertEqual(portrait.0, 1214); XCTAssertEqual(portrait.1, 2160)
        let laptop = DemoDisplayRecorder.dimensions(width: 3024, height: 1964)
        XCTAssertEqual(laptop.0, 3024); XCTAssertEqual(laptop.1, 1964)
    }

    func testEncoderFinalizesRealMovieWithQuietTailAndClockOffset() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = DemoCaptureClock.now
        let journal = try DemoCaptureJournal(url: dir.appendingPathComponent("events.jsonl"), startHostTime: host - 3)
        let recorder = try DemoDisplayRecorder(display: nil, pixelWidth: 320, pixelHeight: 180,
            folder: dir, journal: journal, onFailure: { _ in })
        // A single frame one second before Stop simulates an unchanged screen.
        let pts = CMTime(seconds: host - 1, preferredTimescale: 1_000_000_000)
        recorder.appendFrame(try frame(pts: pts), clock: CMClockGetHostTimeClock())
        let result = await recorder.stop()
        _ = await journal.finish()
        XCTAssertNil(result.error)
        XCTAssertEqual(result.frames, 1)
        XCTAssertEqual(result.firstFrameSessionTime ?? -1, 2, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(result.duration, 1)
        let asset = AVURLAsset(url: dir.appendingPathComponent(result.file))
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThanOrEqual(duration.seconds, 0.99)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: tracks[0], outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var decoded = 0
        while output.copyNextSampleBuffer() != nil { decoded += 1 }
        XCTAssertGreaterThan(decoded, 0)
        XCTAssertEqual(reader.status, .completed)
    }

    func testStoppingWithoutFramesReportsIncompleteNotSuccess() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let journal = try DemoCaptureJournal(url: dir.appendingPathComponent("events.jsonl"), startHostTime: 0)
        let recorder = try DemoDisplayRecorder(display: nil, pixelWidth: 320, pixelHeight: 180,
            folder: dir, journal: journal, onFailure: { _ in })
        let result = await recorder.stop()
        _ = await journal.finish()
        XCTAssertNotNil(result.error)
        XCTAssertEqual(result.frames, 0)
    }

    private func frame(pts: CMTime) throws -> CMSampleBuffer {
        var pixel: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel), kCVReturnSuccess)
        let buffer = try XCTUnwrap(pixel)
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 90, CVPixelBufferGetBytesPerRow(buffer) * 180)
        CVPixelBufferUnlockBaseAddress(buffer, [])
        var format: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
            imageBuffer: buffer, formatDescriptionOut: &format), noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 60), presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
            formatDescription: try XCTUnwrap(format), sampleTiming: &timing, sampleBufferOut: &sample), noErr)
        return try XCTUnwrap(sample)
    }
}
