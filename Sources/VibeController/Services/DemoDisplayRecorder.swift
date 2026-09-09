import AVFoundation
import ScreenCaptureKit

struct DemoDisplayResult: Codable, Sendable {
    var displayID: UInt32
    var file: String
    var width: Int
    var height: Int
    var firstFrameSessionTime: Double?
    var firstSourcePTS: Double?
    var duration: Double
    var frames: Int
    var droppedFrames: Int
    var error: String?
}

enum DemoCaptureError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

/// Video only: never opens the microphone used by dictation. Each display has
/// its own encoder queue, stream, timestamps and independently editable file.
final class DemoDisplayRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.vibe-controller.demo-video", qos: .utility)
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let journal: DemoCaptureJournal
    private var stream: SCStream!
    private var result: DemoDisplayResult
    private var firstPTS: CMTime?
    private var lastSample: CMSampleBuffer?
    private var lastAnchorTime = -Double.infinity
    private var stopping = false
    private var sourceClock: CMClock = CMClockGetHostTimeClock()
    private let onFailure: @Sendable (String) -> Void

    static func dimensions(width: Int, height: Int) -> (Int, Int) {
        let scale = min(1, min(3840.0 / Double(max(width, 1)), 2160.0 / Double(max(height, 1))))
        return (max(2, Int(Double(width) * scale) / 2 * 2), max(2, Int(Double(height) * scale) / 2 * 2))
    }

    static func targetBitrate(width: Int, height: Int) -> Int {
        min(40_000_000, max(8_000_000, width * height * 5))
    }

    // A nil display is an encoder-only fixture for tests; start() rejects it.
    init(display: SCDisplay?, pixelWidth: Int, pixelHeight: Int, folder: URL,
         journal: DemoCaptureJournal, onFailure: @escaping @Sendable (String) -> Void) throws {
        let (width, height) = Self.dimensions(width: pixelWidth, height: pixelHeight)
        let filename = "display-\(display?.displayID ?? 0).mov"
        self.journal = journal
        self.onFailure = onFailure
        result = DemoDisplayResult(displayID: display?.displayID ?? 0, file: filename, width: width,
            height: height, duration: 0, frames: 0, droppedFrames: 0)
        writer = try AVAssetWriter(outputURL: folder.appendingPathComponent(filename), fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Self.targetBitrate(width: width, height: height),
                AVVideoExpectedSourceFrameRateKey: 60,
                AVVideoMaxKeyFrameIntervalKey: 60
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw DemoCaptureError.message("Could not create the video encoder.") }
        writer.add(input)
        super.init()
        guard let display else { return }
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 5
        configuration.showsCursor = true
        configuration.capturesAudio = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        let filter = SCContentFilter(display: display, excludingWindows: [])
        stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
    }

    func start() async throws {
        guard let stream else { throw DemoCaptureError.message("No display was selected.") }
        try await stream.startCapture()
        // The UI only says Recording once every selected display has produced
        // an encoded frame. This also catches a permission/encoder failure.
        for _ in 0..<100 {
            let state = await snapshot()
            if let error = state.error { throw DemoCaptureError.message(error) }
            if state.frames > 0 { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw DemoCaptureError.message("No video arrived from display \(result.displayID). Check Screen Recording permission and try again.")
    }

    func snapshot() async -> DemoDisplayResult {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.result) }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        guard outputType == .screen, !stopping, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete else { return }
        guard let clock = stream.synchronizationClock else {
            fail("The display stream has no synchronization clock."); return
        }
        appendFrame(sampleBuffer, clock: clock,
            displayMachTime: (attachments.first?[.displayTime] as? NSNumber)?.doubleValue)
    }

    /// Serialized by the stream output queue. Encoder-only tests use the same
    /// path with synthetic frames and a known host clock, without capturing UI.
    func appendFrame(_ sampleBuffer: CMSampleBuffer, clock: CMClock, displayMachTime: Double? = nil) {
        guard !stopping, result.error == nil else { return }
        sourceClock = clock
        let pts = sampleBuffer.presentationTimeStamp
        // Convert clock domains explicitly; never assume the stream PTS epoch
        // equals Date, uptime, or the callback's arrival time.
        let hostTime = CMSyncConvertTime(pts, from: clock, to: CMClockGetHostTimeClock()).seconds
        guard hostTime.isFinite else { fail("Could not synchronize the video clock."); return }
        if writer.status == .unknown {
            guard writer.startWriting() else { fail(writer.error?.localizedDescription ?? "Video encoder failed to start."); return }
        }
        guard input.isReadyForMoreMediaData else { result.droppedFrames += 1; return }
        if firstPTS == nil {
            writer.startSession(atSourceTime: pts)
        }
        guard input.append(sampleBuffer) else { fail(writer.error?.localizedDescription ?? "Video frame could not be written."); return }
        if firstPTS == nil {
            firstPTS = pts
            result.firstSourcePTS = pts.seconds
            result.firstFrameSessionTime = hostTime - journal.startHostTime
        }
        lastSample = sampleBuffer
        result.frames += 1
        result.duration = (pts - firstPTS!).seconds
        if hostTime - lastAnchorTime >= 1 {
            lastAnchorTime = hostTime
            let id = result.displayID
            let fileTime = (pts - firstPTS!).seconds
            journal.submit { [journal] in
                var values = ["displayID": Double(id), "videoTime": fileTime, "sourcePTS": pts.seconds]
                values["windowServerMachTime"] = displayMachTime
                return DemoCaptureEvent(kind: "video_anchor", time: hostTime - journal.startHostTime, values: values)
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { if !self.stopping { self.fail(error.localizedDescription) } }
    }

    private func fail(_ message: String) {
        guard result.error == nil else { return }
        result.error = message
        onFailure(message)
    }

    func stop() async -> DemoDisplayResult {
        let stopHost = CMClockGetTime(CMClockGetHostTimeClock())
        await withCheckedContinuation { continuation in
            queue.async { self.stopping = true; continuation.resume() }
        }
        do { try await stream?.stopCapture() }
        catch { /* A disconnected stream may already be stopped; still finalize. */ }
        // Give the asynchronous encoder a bounded chance to accept the final
        // hold frame. Never sleep on the encoder or controller queues.
        for _ in 0..<50 {
            let ready = await withCheckedContinuation { continuation in
                queue.async { continuation.resume(returning: self.writer.status != .writing || self.input.isReadyForMoreMediaData) }
            }
            if ready { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let firstPTS, let lastSample, writer.status == .writing else {
                    if result.error == nil { result.error = writer.error?.localizedDescription ?? "No video frames were recorded." }
                    writer.cancelWriting()
                    continuation.resume(returning: result)
                    return
                }
                // ScreenCaptureKit can skip unchanged screens. Extend the last
                // image to Stop instead of silently trimming the quiet tail.
                let end = max(lastSample.presentationTimeStamp + CMTime(value: 1, timescale: 60),
                              CMSyncConvertTime(stopHost, from: CMClockGetHostTimeClock(), to: sourceClock))
                var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 60),
                    presentationTimeStamp: end, decodeTimeStamp: .invalid)
                var tail: CMSampleBuffer?
                if CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,
                    sampleBuffer: lastSample, sampleTimingEntryCount: 1,
                    sampleTimingArray: &timing, sampleBufferOut: &tail) == noErr,
                   let tail, input.isReadyForMoreMediaData {
                    if !input.append(tail) { result.error = writer.error?.localizedDescription ?? "Could not finish the final frame." }
                }
                else { result.error = "The encoder could not accept the final hold frame; the quiet tail may be incomplete." }
                let finalEnd = end + CMTime(value: 1, timescale: 60)
                writer.endSession(atSourceTime: finalEnd)
                input.markAsFinished()
                self.lastSample = nil
                result.duration = (finalEnd - firstPTS).seconds
                writer.finishWriting { [self] in
                    queue.async { [self] in
                        if writer.status != .completed { result.error = writer.error?.localizedDescription ?? "The video did not finish saving." }
                        continuation.resume(returning: result)
                    }
                }
            }
        }
    }
}
