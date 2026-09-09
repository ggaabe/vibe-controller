import AVFoundation
import XCTest
@testable import VibeController

@MainActor
final class DemoFollowTests: XCTestCase {
    let main = DemoFollowDisplay(id: 1, bounds: CGRect(x: 0, y: 0, width: 1600, height: 1000))
    let above = DemoFollowDisplay(id: 2, bounds: CGRect(x: 0, y: -1080, width: 1920, height: 1080))
    let left = DemoFollowDisplay(id: 3, bounds: CGRect(x: -1920, y: 0, width: 1920, height: 1080))

    func testVerticalJumpUsesGlobalCoordinatesAndBackdatesStableCrossing() {
        var state = DemoDisplayFollowState(displays: [main, above])
        XCTAssertEqual(state.observe(point: CGPoint(x: 800, y: 500), time: 0)?.displayID, 1)
        XCTAssertNil(state.observe(point: CGPoint(x: 900, y: -700), time: 1))
        XCTAssertNil(state.observe(point: CGPoint(x: 900, y: -700), time: 1.1))
        XCTAssertEqual(state.observe(point: CGPoint(x: 950, y: -750), time: 1.13), DemoDisplayChange(time: 1, displayID: 2))
    }

    func testBriefBoundaryExcursionsDoNotCut() {
        var state = DemoDisplayFollowState(displays: [main, above])
        _ = state.observe(point: CGPoint(x: 20, y: 20), time: 0)
        XCTAssertNil(state.observe(point: CGPoint(x: 20, y: -1), time: 1))
        XCTAssertNil(state.observe(point: CGPoint(x: 20, y: 1), time: 1.05))
        XCTAssertNil(state.observe(point: CGPoint(x: 20, y: -1), time: 1.09))
        XCTAssertNil(state.observe(point: CGPoint(x: 20, y: 1), time: 1.15))
        XCTAssertEqual(state.current, 1)
    }

    func testNegativeXAndUnselectedOrUnknownPointerKeepLastLocalDisplay() {
        var state = DemoDisplayFollowState(displays: [main, left])
        _ = state.observe(point: CGPoint(x: 50, y: 50), time: 0)
        _ = state.observe(point: CGPoint(x: -500, y: 400), time: 1)
        XCTAssertEqual(state.observe(point: CGPoint(x: -500, y: 400), time: 1.13)?.displayID, 3)
        XCTAssertNil(state.observe(point: CGPoint(x: 4000, y: 400), time: 2))
        XCTAssertNil(state.observe(point: nil, time: 3))
        XCTAssertEqual(state.current, 3)
    }

    func testMirroredBoundsKeepCurrentSource() {
        var state = DemoDisplayFollowState(displays: [main, DemoFollowDisplay(id: 2, bounds: main.bounds)])
        XCTAssertEqual(state.observe(point: .zero, time: 0)?.displayID, 1)
        XCTAssertNil(state.observe(point: CGPoint(x: 10, y: 10), time: 2))
    }

    func testNoSelectedDisplaysNeverCreatesSource() {
        var state = DemoDisplayFollowState(displays: [])
        XCTAssertNil(state.observe(point: .zero, time: 0))
    }

    func testEditPlanAccountsForDifferentRecordingStartsAndIgnoresUnknownDisplays() throws {
        let sources = [source(id: 1, start: 2, duration: 10), source(id: 2, start: 3, duration: 10)]
        let plan = try DemoFollowPlan.make(displays: sources, changes: [
            .init(time: 0, displayID: 1), .init(time: 4, displayID: 2),
            .init(time: 5, displayID: 999), .init(time: 7, displayID: 1)
        ])
        XCTAssertEqual(plan.sessionOrigin, 3)
        XCTAssertEqual(plan.duration, 9)
        XCTAssertEqual(plan.segments.map(\.displayID), [1, 2, 1])
        XCTAssertEqual(plan.segments.map(\.sourceStart), [1, 1, 5])
        XCTAssertEqual(plan.segments.map(\.duration), [1, 3, 5])
        XCTAssertEqual(plan.segments.map(\.sessionStart), [3, 4, 7])
    }

    func testEditPlanRejectsMissingNonfiniteAndIncompleteVideo() {
        XCTAssertThrowsError(try DemoFollowPlan.make(displays: [], changes: []))
        var invalid = source(id: 1, start: 0, duration: 2)
        invalid.error = "disk full"
        XCTAssertThrowsError(try DemoFollowPlan.make(displays: [invalid], changes: []))
        invalid.error = nil
        invalid.duration = .infinity
        XCTAssertThrowsError(try DemoFollowPlan.make(displays: [invalid], changes: []))
    }

    func testStorageThresholdsAndExportBudget() {
        XCTAssertFalse(DemoCaptureStorage.canStart(available: nil))
        XCTAssertFalse(DemoCaptureStorage.canStart(available: 4_999_999_999))
        XCTAssertTrue(DemoCaptureStorage.canStart(available: 5_000_000_000))
        XCTAssertTrue(DemoCaptureStorage.shouldStop(available: nil))
        XCTAssertTrue(DemoCaptureStorage.shouldStop(available: 1_999_999_999))
        XCTAssertFalse(DemoCaptureStorage.shouldStop(available: 2_000_000_000))
        XCTAssertGreaterThan(DemoCaptureStorage.previewBudget(duration: 600), DemoCaptureStorage.previewBudget(duration: 60))
    }

    func testStorageInventoryIsReadOnlyScopedAndExcludesCurrentTakeFromReminders() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("old-take")
        let current = root.appendingPathComponent("active-take")
        let recent = root.appendingPathComponent("recent-take")
        let unrelated = root.appendingPathComponent("phone-originals")
        for dir in [old, current, recent, unrelated] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 8192).write(to: dir.appendingPathComponent("original.mov"))
        }
        for dir in [old, current, recent] {
            let age: Double = dir == recent ? 60 : 15 * 24 * 60 * 60
            let manifest = DemoCaptureManifest(take: "test", startedAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-age)),
                startHostTime: 0, appVersion: "test", status: "complete", displays: [])
            try JSONEncoder().encode(manifest).write(to: dir.appendingPathComponent("session.json"))
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked-take"), withDestinationURL: old)
        let summary = DemoCaptureStorage.inspect(root: root, currentTake: current)
        XCTAssertEqual(summary.takeCount, 3)
        XCTAssertEqual(summary.olderTakes.map { $0.resolvingSymlinksInPath().path }, [old.resolvingSymlinksInPath().path])
        XCTAssertGreaterThan(summary.takeBytes, 0)
        XCTAssertGreaterThan(summary.currentTakeBytes, 0)
        for dir in [old, current, recent, unrelated] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("original.mov").path))
        }
    }

    func testAspectFitDoesNotCropTallScreens() {
        let size = CGSize(width: 1200, height: 1920)
        let transform = DemoFollowExporter.fitTransform(size: size, preferred: .identity)
        let fitted = CGRect(origin: .zero, size: size).applying(transform)
        XCTAssertEqual(fitted.height, 1080, accuracy: 0.001)
        XCTAssertEqual(fitted.midX, 960, accuracy: 0.001)
        XCTAssertGreaterThan(fitted.minX, 0)
    }

    func testLowSpaceSkipsDerivativeWithoutTouchingOriginals() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("display-1.mov")
        let data = Data("original remains".utf8)
        try data.write(to: original)
        let plan = try DemoFollowPlan.make(displays: [source(id: 1, start: 0, duration: 3)], changes: [])
        do {
            _ = try await DemoFollowExporter().export(plan: plan, folder: root, freeBytes: { 1_000_000 })
            XCTFail("Expected a storage guard")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: original), data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("follow-cursor.mp4").path))
    }

    func testRealFollowMovieCutsBetweenSourcesAndPreservesOriginals() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try await makeSource(id: 1, red: 220, blue: 15, root: root)
        try await makeSource(id: 2, red: 15, blue: 220, root: root)
        let original1 = try Data(contentsOf: root.appendingPathComponent("display-1.mov"))
        let original2 = try Data(contentsOf: root.appendingPathComponent("display-2.mov"))
        let plan = try DemoFollowPlan.make(displays: [source(id: 1, start: 0, duration: 2), source(id: 2, start: 0, duration: 2)],
            changes: [.init(time: 0, displayID: 1), .init(time: 1, displayID: 2)])
        let output = try await DemoFollowExporter().export(plan: plan, folder: root, freeBytes: { 100_000_000_000 })
        let asset = AVURLAsset(url: root.appendingPathComponent(output))
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 2, accuracy: 1.0 / 30)
        XCTAssertEqual(size, CGSize(width: 1920, height: 1080))
        let reader = try AVAssetReader(asset: asset)
        let decoded = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(decoded)
        XCTAssertTrue(reader.startReading())
        var firstColorVerified = false
        var secondColorVerified = false
        while let sample = decoded.copyNextSampleBuffer() {
            let time = sample.presentationTimeStamp.seconds
            guard let buffer = sample.imageBuffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let offset = CVPixelBufferGetBytesPerRow(buffer) * 540 + 960 * 4
            let blue = Int(base[offset]), red = Int(base[offset + 2])
            if time >= 0 && time < 1 { XCTAssertGreaterThan(red, blue + 100); firstColorVerified = true }
            if time >= 1 && time < 2 { XCTAssertGreaterThan(blue, red + 100); secondColorVerified = true }
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        }
        XCTAssertEqual(reader.status, .completed)
        XCTAssertTrue(firstColorVerified && secondColorVerified)
        // VFR optimization may hold the final blue frame instead of emitting
        // 30 duplicates. Check an actual image well into that held interval.
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let held = try await generator.image(at: CMTime(seconds: 1.8, preferredTimescale: 600))
        var rgba = [UInt8](repeating: 0, count: 4)
        rgba.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(held.image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        XCTAssertGreaterThan(Int(rgba[2]), Int(rgba[0]) + 100)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("display-1.mov")), original1)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("display-2.mov")), original2)
    }

    private func source(id: UInt32, start: Double, duration: Double) -> DemoDisplayResult {
        DemoDisplayResult(displayID: id, file: "display-\(id).mov", width: 320, height: 180,
            firstFrameSessionTime: start, firstSourcePTS: 100, duration: duration, frames: 1, droppedFrames: 0)
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VibeFollowTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSource(id: UInt32, red: UInt8, blue: UInt8, root: URL) async throws {
        let dir = root.appendingPathComponent("source-\(id)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let host = DemoCaptureClock.now
        let journal = try DemoCaptureJournal(url: dir.appendingPathComponent("events.jsonl"), startHostTime: host)
        let recorder = try DemoDisplayRecorder(display: nil, pixelWidth: 320, pixelHeight: 180, folder: dir, journal: journal, onFailure: { _ in })
        var pixel: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel), kCVReturnSuccess)
        let buffer = try XCTUnwrap(pixel)
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<180 { for x in 0..<320 {
            let offset = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
            base[offset] = blue; base[offset + 1] = 15; base[offset + 2] = red; base[offset + 3] = 255
        } }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        var format: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &format), noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 60),
            presentationTimeStamp: CMTime(seconds: host - 3, preferredTimescale: 1_000_000_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
            formatDescription: try XCTUnwrap(format), sampleTiming: &timing, sampleBufferOut: &sample), noErr)
        recorder.appendFrame(try XCTUnwrap(sample), clock: CMClockGetHostTimeClock())
        let result = await recorder.stop()
        _ = await journal.finish()
        XCTAssertNil(result.error)
        try FileManager.default.moveItem(at: dir.appendingPathComponent(result.file), to: root.appendingPathComponent("display-\(id).mov"))
    }
}
