import Foundation

struct DemoStorageSummary: Sendable {
    var availableBytes: Int64?
    var takeBytes: Int64 = 0
    var takeCount: Int = 0
    var olderTakes: [URL] = []
    var currentTakeBytes: Int64 = 0
}

enum DemoCaptureStorage {
    static let minimumStartBytes: Int64 = 5_000_000_000
    static let stopReserveBytes: Int64 = 2_000_000_000
    static let reviewAge: TimeInterval = 14 * 24 * 60 * 60

    static func availableBytes(at url: URL) -> Int64? {
        var existing = url
        while !FileManager.default.fileExists(atPath: existing.path) && existing.path != "/" {
            existing.deleteLastPathComponent()
        }
        // Actual free space, not a promise that macOS can purge other data.
        return ((try? FileManager.default.attributesOfFileSystem(forPath: existing.path))?[.systemFreeSize] as? NSNumber)?.int64Value
    }

    static func canStart(available: Int64?) -> Bool { available.map { $0 >= minimumStartBytes } ?? false }
    static func shouldStop(available: Int64?) -> Bool { available.map { $0 < stopReserveBytes } ?? true }
    static func previewBudget(duration: Double) -> Int64 {
        max(256_000_000, Int64(max(0, duration) * 4_000_000))
    }

    private struct TakeHeader: Decodable {
        var schemaVersion: Int
        var take: String
        var startedAt: String
        var appVersion: String
        var status: String
        var displays: [DemoDisplayResult]
    }

    /// Read-only inventory, limited to recognized capture folders. No purge,
    /// scheduled deletion or Trash operation is performed by the application.
    static func inspect(root: URL, currentTake: URL? = nil, now: Date = Date()) -> DemoStorageSummary {
        var summary = DemoStorageSummary(availableBytes: availableBytes(at: root))
        let children = (try? FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? []
        for child in children {
            guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let manifest = child.appendingPathComponent("session.json")
            guard let size = try? manifest.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey]),
                  size.isSymbolicLink != true, (size.fileSize ?? Int.max) < 2_000_000,
                  let data = try? Data(contentsOf: manifest),
                  let header = try? JSONDecoder().decode(TakeHeader.self, from: data),
                  header.schemaVersion == 1,
                  ["complete", "incomplete", "recording-not-finalized"].contains(header.status) else { continue }
            let bytes = allocatedSize(of: child)
            summary.takeCount += 1
            summary.takeBytes += bytes
            if child.resolvingSymlinksInPath().standardizedFileURL.path == currentTake?.resolvingSymlinksInPath().standardizedFileURL.path {
                summary.currentTakeBytes = bytes
            }
            else if let date = ISO8601DateFormatter().date(from: header.startedAt), now.timeIntervalSince(date) >= reviewAge {
                summary.olderTakes.append(child)
            }
        }
        summary.olderTakes.sort { $0.lastPathComponent < $1.lastPathComponent }
        return summary
    }

    private static func allocatedSize(of directory: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return 0 }
        var size: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: keys), values.isSymbolicLink != true,
                  values.isRegularFile == true else { continue }
            size += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return size
    }
}
