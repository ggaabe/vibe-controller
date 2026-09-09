import AVFoundation
import Foundation

/// A derivative review movie. Full-resolution source movies are never replaced
/// or deleted. Uses the macOS 14-compatible composition API intentionally.
final class DemoFollowExporter: @unchecked Sendable {
    private let lock = NSLock()
    private var session: AVAssetExportSession?
    private var cancelled = false

    func cancel() {
        lock.withLock { cancelled = true; session?.cancelExport() }
    }

    static func fitTransform(size: CGSize, preferred: CGAffineTransform,
                             canvas: CGSize = CGSize(width: 1920, height: 1080)) -> CGAffineTransform {
        let rect = CGRect(origin: .zero, size: size).applying(preferred)
        let scale = min(canvas.width / rect.width, canvas.height / rect.height)
        return preferred.concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: (canvas.width - rect.width * scale) / 2,
                                            y: (canvas.height - rect.height * scale) / 2))
    }

    func export(plan: DemoFollowPlan, folder: URL,
                freeBytes: @escaping @Sendable () -> Int64? = { nil },
                progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> String {
        let budget = DemoCaptureStorage.previewBudget(duration: plan.duration)
        guard let available = freeBytes(), available >= budget + DemoCaptureStorage.stopReserveBytes else {
            throw DemoCaptureError.message("Not enough free space for the follow-cursor review copy. Original recordings and the edit plan are saved.")
        }
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw DemoCaptureError.message("Could not create the follow-cursor edit.")
        }
        var assets: [String: (AVURLAsset, AVAssetTrack, CGSize, CGAffineTransform)] = [:]
        var instructions: [AVMutableVideoCompositionInstruction] = []
        for segment in plan.segments {
            try Task.checkCancellation()
            guard !lock.withLock({ cancelled }) else { throw CancellationError() }
            guard segment.file == URL(fileURLWithPath: segment.file).lastPathComponent else {
                throw DemoCaptureError.message("The edit plan has an invalid source filename.")
            }
            if assets[segment.file] == nil {
                let asset = AVURLAsset(url: folder.appendingPathComponent(segment.file))
                guard let video = try await asset.loadTracks(withMediaType: .video).first else {
                    throw DemoCaptureError.message("A source movie has no video track.")
                }
                let size = try await video.load(.naturalSize)
                let transform = try await video.load(.preferredTransform)
                assets[segment.file] = (asset, video, size, transform)
            }
            let (_, source, size, preferred) = assets[segment.file]!
            let destination = CMTime(seconds: segment.sessionStart - plan.sessionOrigin, preferredTimescale: 60_000)
            let duration = CMTime(seconds: segment.duration, preferredTimescale: 60_000)
            try track.insertTimeRange(CMTimeRange(start: CMTime(seconds: segment.sourceStart, preferredTimescale: 60_000),
                duration: duration), of: source, at: destination)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            layer.setTransform(Self.fitTransform(size: size, preferred: preferred), at: destination)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: destination, duration: duration)
            instruction.backgroundColor = CGColor(gray: 0, alpha: 1)
            instruction.layerInstructions = [layer]
            instructions.append(instruction)
        }
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: 1920, height: 1080)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid
        videoComposition.instructions = instructions
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1920x1080) else {
            throw DemoCaptureError.message("The follow-cursor encoder is unavailable.")
        }
        let temporary = folder.appendingPathComponent(".follow-\(UUID().uuidString).mp4")
        let filename = "follow-cursor.mp4"
        let destination = folder.appendingPathComponent(filename)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw DemoCaptureError.message("A follow-cursor movie already exists; it was not overwritten.")
        }
        exporter.videoComposition = videoComposition
        exporter.outputURL = temporary
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        exporter.fileLengthLimit = budget
        exporter.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: plan.duration, preferredTimescale: 60_000))
        lock.withLock { session = exporter }
        let monitor = Task {
            while !Task.isCancelled {
                progress(lock.withLock { Double(session?.progress ?? 0) })
                if DemoCaptureStorage.shouldStop(available: freeBytes()) { self.cancel(); return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        defer {
            monitor.cancel()
            lock.withLock { session = nil }
            // Only this operation's unfinished derivative is removed. Never a
            // source movie, preexisting export, or user-selected folder.
            try? FileManager.default.removeItem(at: temporary)
        }
        guard !lock.withLock({ cancelled }) else { throw CancellationError() }
        await exporter.export()
        guard exporter.status == .completed else {
            throw DemoCaptureError.message(exporter.error?.localizedDescription
                ?? "Follow-cursor export stopped. Original recordings and the edit plan are saved.")
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        progress(1)
        return filename
    }
}
