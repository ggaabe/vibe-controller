import CryptoKit
import Foundation
import Security

struct AppVersion: Comparable, CustomStringConvertible, Equatable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: String) {
        let normalized = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let components = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2]),
              major >= 0,
              minor >= 0,
              patch >= 0 else {
            return nil
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

struct AvailableAppUpdate: Equatable, Sendable {
    let version: AppVersion
    let releasePageURL: URL
    let diskImageURL: URL
    let diskImageFilename: String
    let checksumsURL: URL
}

enum AppUpdateCheckResult: Equatable, Sendable {
    case upToDate(latestVersion: AppVersion)
    case available(AvailableAppUpdate)
}

enum AppUpdateState: Equatable {
    case idle
    case checking
    case upToDate(currentVersion: String, latestVersion: String)
    case available(AvailableAppUpdate)
    case downloading(version: String)
    case preparing(version: String)
    case installing(version: String)
    case failed(message: String)

    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .preparing, .installing:
            return true
        default:
            return false
        }
    }
}

struct AppUpdatePresentation: Equatable {
    let statusText: String
    let buttonTitle: String
    let symbolName: String
    let isBusy: Bool
    let isProminent: Bool

    static func make(
        state: AppUpdateState,
        currentVersion: String,
        canInstallAutomatically: Bool
    ) -> AppUpdatePresentation {
        switch state {
        case .idle:
            return .init(
                statusText: "Vibe Controller v\(currentVersion)",
                buttonTitle: "Check for Updates",
                symbolName: "arrow.triangle.2.circlepath",
                isBusy: false,
                isProminent: false
            )
        case .checking:
            return .init(
                statusText: "Checking GitHub Releases…",
                buttonTitle: "Checking…",
                symbolName: "arrow.triangle.2.circlepath",
                isBusy: true,
                isProminent: false
            )
        case .upToDate(let installed, let latest):
            let status = AppVersion(installed).flatMap { installedVersion in
                AppVersion(latest).map { latestVersion in
                    installedVersion > latestVersion
                        ? "Pre-release v\(installed) · GitHub v\(latest)"
                        : "Vibe Controller v\(installed) is up to date"
                }
            } ?? "Vibe Controller v\(installed) is up to date"
            return .init(
                statusText: status,
                buttonTitle: "Check Again",
                symbolName: "checkmark.circle.fill",
                isBusy: false,
                isProminent: false
            )
        case .available(let update):
            return .init(
                statusText: "Vibe Controller v\(update.version) is available",
                buttonTitle: canInstallAutomatically ? "Update Now" : "View Release",
                symbolName: "arrow.down.circle.fill",
                isBusy: false,
                isProminent: true
            )
        case .downloading(let version):
            return .init(
                statusText: "Downloading Vibe Controller v\(version)…",
                buttonTitle: "Downloading…",
                symbolName: "arrow.down.circle",
                isBusy: true,
                isProminent: true
            )
        case .preparing(let version):
            return .init(
                statusText: "Verifying signed update v\(version)…",
                buttonTitle: "Verifying…",
                symbolName: "checkmark.shield",
                isBusy: true,
                isProminent: true
            )
        case .installing(let version):
            return .init(
                statusText: "Installing v\(version) and relaunching…",
                buttonTitle: "Installing…",
                symbolName: "arrow.clockwise.circle.fill",
                isBusy: true,
                isProminent: true
            )
        case .failed(let message):
            return .init(
                statusText: message,
                buttonTitle: "Try Again",
                symbolName: "exclamationmark.triangle.fill",
                isBusy: false,
                isProminent: false
            )
        }
    }
}

struct PreparedAppUpdate: Sendable {
    let currentApplicationURL: URL
    let stagedApplicationURL: URL
    let backupApplicationURL: URL
    let helperScriptURL: URL
    let helperWorkingDirectoryURL: URL
}

enum AppUpdateError: LocalizedError, Equatable {
    case invalidCurrentVersion(String)
    case invalidReleaseResponse
    case releaseDoesNotContainInstaller(String)
    case releaseDoesNotContainChecksums
    case invalidServerResponse
    case checksumNotFound(String)
    case checksumMismatch
    case currentApplicationIsNotProduction
    case currentApplicationIsNotWritable
    case mountedApplicationMissing
    case downloadedApplicationHasWrongIdentity
    case downloadedApplicationHasWrongVersion
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidCurrentVersion(let version):
            return "This build has an invalid version number: \(version)."
        case .invalidReleaseResponse:
            return "GitHub returned an invalid Vibe Controller release."
        case .releaseDoesNotContainInstaller(let version):
            return "Release v\(version) does not contain the macOS disk image."
        case .releaseDoesNotContainChecksums:
            return "The release is missing its published checksums."
        case .invalidServerResponse:
            return "GitHub did not return a valid update download."
        case .checksumNotFound(let filename):
            return "The published checksum does not include \(filename)."
        case .checksumMismatch:
            return "The downloaded update did not match its published checksum."
        case .currentApplicationIsNotProduction:
            return "Automatic installation is available from the signed Vibe Controller release app."
        case .currentApplicationIsNotWritable:
            return "Vibe Controller cannot update this app in place. Move it to Applications and try again."
        case .mountedApplicationMissing:
            return "The downloaded disk image does not contain Vibe Controller.app."
        case .downloadedApplicationHasWrongIdentity:
            return "The downloaded app is not signed as this Vibe Controller installation."
        case .downloadedApplicationHasWrongVersion:
            return "The downloaded app version does not match the GitHub release."
        case .commandFailed(let command):
            return "The update could not complete while running \(command)."
        }
    }
}

actor AppUpdateService {
    static let productionBundleIdentifier = "com.vibe-controller.app"
    static let releasesPageURL = URL(string: "https://github.com/ggaabe/vibe-controller/releases")!

    private let session: URLSession
    private let fileManager: FileManager
    private let latestReleaseURL = URL(
        string: "https://api.github.com/repos/ggaabe/vibe-controller/releases/latest"
    )!

    init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
    }

    func checkForUpdate(currentVersion: String) async throws -> AppUpdateCheckResult {
        guard let installedVersion = AppVersion(currentVersion) else {
            throw AppUpdateError.invalidCurrentVersion(currentVersion)
        }

        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Vibe-Controller/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        return try Self.resolve(release: release, currentVersion: installedVersion)
    }

    func prepare(
        update: AvailableAppUpdate,
        currentApplicationURL: URL,
        onDownloadsFinished: (@Sendable () async -> Void)? = nil
    ) async throws -> PreparedAppUpdate {
        guard Bundle(url: currentApplicationURL)?.bundleIdentifier == Self.productionBundleIdentifier else {
            throw AppUpdateError.currentApplicationIsNotProduction
        }

        let parentURL = currentApplicationURL.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: parentURL.path) else {
            throw AppUpdateError.currentApplicationIsNotWritable
        }

        let identifier = UUID().uuidString
        let downloadDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("VibeControllerUpdate-\(identifier)", isDirectory: true)
        let diskImageURL = downloadDirectory.appendingPathComponent(update.diskImageFilename)
        let checksumsURL = downloadDirectory.appendingPathComponent("SHA256SUMS.txt")
        let stagedApplicationURL = parentURL
            .appendingPathComponent(".Vibe Controller.update-\(identifier).app", isDirectory: true)
        let backupApplicationURL = parentURL
            .appendingPathComponent(".Vibe Controller.backup-\(identifier).app", isDirectory: true)

        try fileManager.createDirectory(
            at: downloadDirectory,
            withIntermediateDirectories: true
        )

        do {
            try await download(update.diskImageURL, to: diskImageURL)
            try await download(update.checksumsURL, to: checksumsURL)
            await onDownloadsFinished?()
            try Self.verifyChecksum(
                diskImageURL: diskImageURL,
                checksumsURL: checksumsURL,
                expectedFilename: update.diskImageFilename
            )
            try run("hdiutil verify", executable: "/usr/bin/hdiutil", arguments: ["verify", diskImageURL.path])

            let mountURL = try mount(diskImageURL)
            defer {
                _ = try? run(
                    "hdiutil detach",
                    executable: "/usr/bin/hdiutil",
                    arguments: ["detach", mountURL.path, "-quiet"]
                )
            }

            let mountedApplicationURL = mountURL
                .appendingPathComponent("Vibe Controller.app", isDirectory: true)
            guard fileManager.fileExists(atPath: mountedApplicationURL.path) else {
                throw AppUpdateError.mountedApplicationMissing
            }

            try Self.verifyIdentity(
                candidateApplicationURL: mountedApplicationURL,
                currentApplicationURL: currentApplicationURL
            )
            try Self.verifyVersion(
                candidateApplicationURL: mountedApplicationURL,
                expectedVersion: update.version
            )
            try run(
                "Gatekeeper verification",
                executable: "/usr/sbin/spctl",
                arguments: ["--assess", "--type", "execute", "--verbose=2", mountedApplicationURL.path]
            )

            try? fileManager.removeItem(at: stagedApplicationURL)
            try run(
                "application staging",
                executable: "/usr/bin/ditto",
                arguments: [mountedApplicationURL.path, stagedApplicationURL.path]
            )
            try Self.verifyIdentity(
                candidateApplicationURL: stagedApplicationURL,
                currentApplicationURL: currentApplicationURL
            )

            let helperScriptURL = downloadDirectory.appendingPathComponent("install-update.sh")
            try Self.replacementScript.write(
                to: helperScriptURL,
                atomically: true,
                encoding: .utf8
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: helperScriptURL.path
            )

            return PreparedAppUpdate(
                currentApplicationURL: currentApplicationURL,
                stagedApplicationURL: stagedApplicationURL,
                backupApplicationURL: backupApplicationURL,
                helperScriptURL: helperScriptURL,
                helperWorkingDirectoryURL: downloadDirectory
            )
        } catch {
            try? fileManager.removeItem(at: stagedApplicationURL)
            try? fileManager.removeItem(at: backupApplicationURL)
            try? fileManager.removeItem(at: downloadDirectory)
            throw error
        }
    }

    func launchReplacement(_ prepared: PreparedAppUpdate, processIdentifier: Int32) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            prepared.helperScriptURL.path,
            prepared.currentApplicationURL.path,
            prepared.stagedApplicationURL.path,
            prepared.backupApplicationURL.path,
            String(processIdentifier),
            prepared.helperWorkingDirectoryURL.path,
        ]
        do {
            try process.run()
        } catch {
            throw AppUpdateError.commandFailed("the replacement helper")
        }
    }

    func discard(_ prepared: PreparedAppUpdate) {
        try? fileManager.removeItem(at: prepared.stagedApplicationURL)
        try? fileManager.removeItem(at: prepared.backupApplicationURL)
        try? fileManager.removeItem(at: prepared.helperWorkingDirectoryURL)
    }

    func removeAbandonedArtifacts(beside currentApplicationURL: URL) {
        let parentURL = currentApplicationURL.deletingLastPathComponent()
        guard let contents = try? fileManager.contentsOfDirectory(
            at: parentURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for url in contents where
            url.lastPathComponent.hasPrefix(".Vibe Controller.update-") ||
            url.lastPathComponent.hasPrefix(".Vibe Controller.backup-") {
            try? fileManager.removeItem(at: url)
        }
    }

    static func resolve(
        release: GitHubRelease,
        currentVersion: AppVersion
    ) throws -> AppUpdateCheckResult {
        guard !release.draft,
              !release.prerelease,
              let releaseVersion = AppVersion(release.tagName),
              let releasePageURL = URL(string: release.htmlURL) else {
            throw AppUpdateError.invalidReleaseResponse
        }

        guard releaseVersion > currentVersion else {
            return .upToDate(latestVersion: releaseVersion)
        }

        let expectedDiskImageName = "Vibe-Controller-\(releaseVersion)-arm64.dmg"
        guard let diskImageAsset = release.assets.first(where: { $0.name == expectedDiskImageName }),
              let diskImageURL = URL(string: diskImageAsset.browserDownloadURL) else {
            throw AppUpdateError.releaseDoesNotContainInstaller(releaseVersion.description)
        }
        guard let checksumAsset = release.assets.first(where: { $0.name == "SHA256SUMS.txt" }),
              let checksumsURL = URL(string: checksumAsset.browserDownloadURL) else {
            throw AppUpdateError.releaseDoesNotContainChecksums
        }

        return .available(
            AvailableAppUpdate(
                version: releaseVersion,
                releasePageURL: releasePageURL,
                diskImageURL: diskImageURL,
                diskImageFilename: expectedDiskImageName,
                checksumsURL: checksumsURL
            )
        )
    }

    static func expectedChecksum(named filename: String, in contents: String) -> String? {
        for line in contents.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2 else { continue }
            let listedFilename = fields[1].trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            if listedFilename == filename {
                return String(fields[0]).lowercased()
            }
        }
        return nil
    }

    static func shouldAutomaticallyCheck(lastCheckedAt: Date?, now: Date) -> Bool {
        guard let lastCheckedAt else { return true }
        return now.timeIntervalSince(lastCheckedAt) >= 24 * 60 * 60
    }

    private func download(_ sourceURL: URL, to destinationURL: URL) async throws {
        var request = URLRequest(url: sourceURL)
        request.setValue("Vibe-Controller-Updater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 120
        let (temporaryURL, response) = try await session.download(for: request)
        try Self.validate(response: response)
        try? fileManager.removeItem(at: destinationURL)
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
    }

    private func mount(_ diskImageURL: URL) throws -> URL {
        let data = try run(
            "hdiutil attach",
            executable: "/usr/bin/hdiutil",
            arguments: ["attach", diskImageURL.path, "-nobrowse", "-readonly", "-plist"]
        )
        guard let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any],
              let entities = propertyList["system-entities"] as? [[String: Any]],
              let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).last else {
            throw AppUpdateError.commandFailed("hdiutil attach")
        }
        return URL(fileURLWithPath: mountPoint, isDirectory: true)
    }

    @discardableResult
    private func run(
        _ name: String,
        executable: String,
        arguments: [String]
    ) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            throw AppUpdateError.commandFailed(name)
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AppUpdateError.commandFailed(name)
        }
        return data
    }

    private static func validate(response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw AppUpdateError.invalidServerResponse
        }
    }

    private static func verifyChecksum(
        diskImageURL: URL,
        checksumsURL: URL,
        expectedFilename: String
    ) throws {
        let contents = try String(contentsOf: checksumsURL, encoding: .utf8)
        guard let expected = expectedChecksum(named: expectedFilename, in: contents) else {
            throw AppUpdateError.checksumNotFound(expectedFilename)
        }
        let data = try Data(contentsOf: diskImageURL, options: [.mappedIfSafe])
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else {
            throw AppUpdateError.checksumMismatch
        }
    }

    private static func verifyVersion(
        candidateApplicationURL: URL,
        expectedVersion: AppVersion
    ) throws {
        guard let version = Bundle(url: candidateApplicationURL)?
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              AppVersion(version) == expectedVersion else {
            throw AppUpdateError.downloadedApplicationHasWrongVersion
        }
    }

    private static func verifyIdentity(
        candidateApplicationURL: URL,
        currentApplicationURL: URL
    ) throws {
        guard Bundle(url: candidateApplicationURL)?.bundleIdentifier == productionBundleIdentifier else {
            throw AppUpdateError.downloadedApplicationHasWrongIdentity
        }

        var currentCode: SecStaticCode?
        var candidateCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            currentApplicationURL as CFURL,
            SecCSFlags(),
            &currentCode
        ) == errSecSuccess,
              let currentCode,
              SecStaticCodeCreateWithPath(
                candidateApplicationURL as CFURL,
                SecCSFlags(),
                &candidateCode
              ) == errSecSuccess,
              let candidateCode else {
            throw AppUpdateError.downloadedApplicationHasWrongIdentity
        }

        let validationFlags = SecCSFlags(
            rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate
        )
        guard SecStaticCodeCheckValidity(currentCode, validationFlags, nil) == errSecSuccess else {
            throw AppUpdateError.downloadedApplicationHasWrongIdentity
        }

        var designatedRequirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(
            currentCode,
            SecCSFlags(),
            &designatedRequirement
        ) == errSecSuccess,
              let designatedRequirement,
              SecStaticCodeCheckValidity(
                candidateCode,
                validationFlags,
                designatedRequirement
              ) == errSecSuccess else {
            throw AppUpdateError.downloadedApplicationHasWrongIdentity
        }
    }

    private static let replacementScript = """
    #!/bin/sh
    set -eu
    current="$1"
    staged="$2"
    backup="$3"
    pid="$4"
    working="$5"
    attempts=0

    while /bin/kill -0 "$pid" 2>/dev/null && [ "$attempts" -lt 300 ]; do
      /bin/sleep 0.1
      attempts=$((attempts + 1))
    done

    if /bin/kill -0 "$pid" 2>/dev/null; then
      /bin/rm -rf "$staged" "$backup" "$working"
      exit 1
    fi

    if [ -e "$current" ]; then
      /bin/mv "$current" "$backup"
    fi

    if ! /bin/mv "$staged" "$current"; then
      if [ -e "$backup" ]; then
        /bin/mv "$backup" "$current"
      fi
      /bin/rm -rf "$staged" "$working"
      exit 1
    fi

    if ! /usr/bin/open "$current"; then
      /bin/rm -rf "$current"
      if [ -e "$backup" ]; then
        /bin/mv "$backup" "$current"
        /usr/bin/open "$current" || true
      fi
      /bin/rm -rf "$working"
      exit 1
    fi

    /bin/rm -rf "$working"
    """
}

struct GitHubRelease: Decodable, Equatable, Sendable {
    struct Asset: Decodable, Equatable, Sendable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }
}
