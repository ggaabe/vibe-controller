import Foundation

/// Serializes the fixed-width command stream written to the privileged helper.
/// Pointer reports come from the real-time motion queue while buttons and keys
/// can originate on the main actor, so writes must never interleave.
final class VirtualHIDCommandTransport: @unchecked Sendable {
    enum CommandKind: UInt8 {
        case pointing = 1
        case keyboard = 2
        case function = 3
    }

    private let lock = NSLock()
    private var fileHandle: FileHandle?
    private var pointingReady = false
    private var keyboardReady = false
    private var failureHandler: (@Sendable () -> Void)?

    func setFailureHandler(_ handler: (@Sendable () -> Void)?) {
        lock.lock()
        failureHandler = handler
        lock.unlock()
    }

    func connect(fileHandle: FileHandle) {
        lock.lock()
        self.fileHandle = fileHandle
        pointingReady = false
        keyboardReady = false
        lock.unlock()
    }

    func updateReadiness(pointing: Bool, keyboard: Bool) {
        lock.lock()
        pointingReady = pointing
        keyboardReady = keyboard
        lock.unlock()
    }

    func disconnect() {
        lock.lock()
        fileHandle = nil
        pointingReady = false
        keyboardReady = false
        lock.unlock()
    }

    var isPointingReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pointingReady && fileHandle != nil
    }

    func postPointing(
        x: Int8,
        y: Int8,
        verticalWheel: Int8 = 0,
        horizontalWheel: Int8 = 0,
        buttons: UInt32
    ) -> Bool {
        sendCommand(
            kind: .pointing,
            x: x,
            y: y,
            verticalWheel: verticalWheel,
            horizontalWheel: horizontalWheel,
            buttons: buttons
        )
    }

    func postKeyboard(modifiers: UInt8, usage: UInt16) -> Bool {
        sendCommand(kind: .keyboard, modifiers: modifiers, usage: usage)
    }

    func postFunction(usage: UInt16) -> Bool {
        sendCommand(kind: .function, usage: usage)
    }

    private func sendCommand(
        kind: CommandKind,
        x: Int8 = 0,
        y: Int8 = 0,
        verticalWheel: Int8 = 0,
        horizontalWheel: Int8 = 0,
        modifiers: UInt8 = 0,
        usage: UInt16 = 0,
        buttons: UInt32 = 0
    ) -> Bool {
        lock.lock()
        let isReady = kind == .pointing ? pointingReady : keyboardReady
        guard isReady, let fileHandle else {
            lock.unlock()
            return false
        }

        var command = Data(repeating: 0, count: 16)
        command[0] = kind.rawValue
        command[1] = UInt8(bitPattern: x)
        command[2] = UInt8(bitPattern: y)
        command[3] = UInt8(bitPattern: verticalWheel)
        command[4] = UInt8(bitPattern: horizontalWheel)
        command[5] = modifiers
        command.replaceSubrange(6..<8, with: withUnsafeBytes(of: usage.littleEndian, Array.init))
        command.replaceSubrange(8..<12, with: withUnsafeBytes(of: buttons.littleEndian, Array.init))

        do {
            try fileHandle.write(contentsOf: command)
            lock.unlock()
            return true
        } catch {
            self.fileHandle = nil
            pointingReady = false
            keyboardReady = false
            let failureHandler = self.failureHandler
            lock.unlock()
            failureHandler?()
            return false
        }
    }
}

/// A narrow client for the installed, root-owned virtual-HID bridge. The
/// privileged process is installed separately and accepts commands only from a
/// valid Vibe Controller app signed by the same development team.
@MainActor
final class PrivilegedVirtualHIDBridge {
    static let installedHelperPath = "/Library/PrivilegedHelperTools/com.vibe-controller.virtual-hid-bridge"

    nonisolated let commandTransport = VirtualHIDCommandTransport()

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var outputBuffer = Data()
    private var lastStartAttempt = Date.distantPast

    private(set) var isKeyboardReady = false
    private(set) var isPointingReady = false
    private(set) var isDriverActivated = false
    private(set) var isDriverConnected = false
    private(set) var isDriverVersionMismatched = false
    private(set) var hasReceivedDriverStatus = false
    private(set) var statusMessage = "Virtual hardware support is not installed."
    var onStatusChange: (() -> Void)?

    init() {
        commandTransport.setFailureHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleTransportFailure()
            }
        }
        startIfInstalled()
    }

    deinit {
        commandTransport.disconnect()
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
    }

    func startIfInstalled() {
        guard process?.isRunning != true else { return }
        guard Date().timeIntervalSince(lastStartAttempt) >= 2 else { return }
        lastStartAttempt = Date()
        guard Self.isInstalledSecurely else {
            hasReceivedDriverStatus = false
            updateStatus(
                driverActivated: false,
                driverConnected: false,
                driverVersionMismatched: false,
                keyboardReady: false,
                pointingReady: false,
                message: "Install Virtual Hardware Support to enable seamless Universal Control."
            )
            return
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: Self.installedHelperPath)
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.consumeOutput(data)
            }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTermination()
            }
        }

        do {
            try process.run()
            self.process = process
            self.inputPipe = inputPipe
            self.outputPipe = outputPipe
            commandTransport.connect(fileHandle: inputPipe.fileHandleForWriting)
            hasReceivedDriverStatus = false
            updateStatus(
                driverActivated: false,
                driverConnected: false,
                driverVersionMismatched: false,
                keyboardReady: false,
                pointingReady: false,
                message: "Starting virtual mouse hardware…"
            )
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            hasReceivedDriverStatus = false
            updateStatus(
                driverActivated: false,
                driverConnected: false,
                driverVersionMismatched: false,
                keyboardReady: false,
                pointingReady: false,
                message: "Could not start Virtual Hardware Support: \(error.localizedDescription)"
            )
        }
    }

    nonisolated func postPointing(
        x: Int8,
        y: Int8,
        verticalWheel: Int8 = 0,
        horizontalWheel: Int8 = 0,
        buttons: UInt32
    ) -> Bool {
        commandTransport.postPointing(
            x: x,
            y: y,
            verticalWheel: verticalWheel,
            horizontalWheel: horizontalWheel,
            buttons: buttons
        )
    }

    func postKeyboard(modifiers: UInt8, usage: UInt16) -> Bool {
        startIfInstalled()
        guard isKeyboardReady else { return false }
        return commandTransport.postKeyboard(modifiers: modifiers, usage: usage)
    }

    func postFunction(isDown: Bool) -> Bool {
        startIfInstalled()
        guard isKeyboardReady else { return false }
        // Apple Vendor Top Case usage 0x0003 is the hardware Fn key.
        return commandTransport.postFunction(usage: isDown ? 0x0003 : 0)
    }

    private func consumeOutput(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0a) {
            let lineData = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard let line = String(data: lineData, encoding: .utf8) else { continue }
            handleOutputLine(line)
        }
    }

    private func handleOutputLine(_ line: String) {
        if line.hasPrefix("STATUS ") {
            hasReceivedDriverStatus = true
            let driverActivated = line.contains("activated=1")
            let driverConnected = line.contains("connected=1")
            let driverVersionMismatched = line.contains("mismatch=1")
            let keyboardReady = line.contains("keyboard=1")
            let pointingReady = line.contains("pointing=1")
            let message: String
            if driverVersionMismatched {
                message = "The installed virtual hardware driver version does not match this app."
            } else if line.contains("activated=0") {
                message = "Virtual hardware is installed but still needs Driver Extension approval."
            } else if line.contains("connected=0") {
                message = "Waiting for macOS to connect the virtual hardware driver…"
            } else if keyboardReady && pointingReady {
                message = "Virtual mouse and keyboard ready for Universal Control."
            } else {
                message = "Waiting for the virtual mouse and keyboard to become ready…"
            }
            updateStatus(
                driverActivated: driverActivated,
                driverConnected: driverConnected,
                driverVersionMismatched: driverVersionMismatched,
                keyboardReady: keyboardReady,
                pointingReady: pointingReady,
                message: message
            )
        } else if line.hasPrefix("ERROR ") {
            hasReceivedDriverStatus = false
            updateStatus(
                driverActivated: false,
                driverConnected: false,
                driverVersionMismatched: false,
                keyboardReady: false,
                pointingReady: false,
                message: String(line.dropFirst("ERROR ".count))
            )
        }
    }

    private func handleTermination() {
        commandTransport.disconnect()
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        inputPipe = nil
        outputPipe = nil
        hasReceivedDriverStatus = false
        updateStatus(
            driverActivated: false,
            driverConnected: false,
            driverVersionMismatched: false,
            keyboardReady: false,
            pointingReady: false,
            message: "Virtual hardware support is not running."
        )
    }

    private func updateStatus(
        driverActivated: Bool,
        driverConnected: Bool,
        driverVersionMismatched: Bool,
        keyboardReady: Bool,
        pointingReady: Bool,
        message: String
    ) {
        let changed = isDriverActivated != driverActivated ||
            isDriverConnected != driverConnected ||
            isDriverVersionMismatched != driverVersionMismatched ||
            isKeyboardReady != keyboardReady ||
            isPointingReady != pointingReady ||
            statusMessage != message
        isDriverActivated = driverActivated
        isDriverConnected = driverConnected
        isDriverVersionMismatched = driverVersionMismatched
        isKeyboardReady = keyboardReady
        isPointingReady = pointingReady
        statusMessage = message
        commandTransport.updateReadiness(pointing: pointingReady, keyboard: keyboardReady)
        if changed {
            onStatusChange?()
        }
    }

    private func handleTransportFailure() {
        hasReceivedDriverStatus = false
        updateStatus(
            driverActivated: false,
            driverConnected: false,
            driverVersionMismatched: false,
            keyboardReady: false,
            pointingReady: false,
            message: "Virtual hardware connection was interrupted."
        )
    }

    static var isInstalledSecurely: Bool {
        let path = installedHelperPath
        guard FileManager.default.isExecutableFile(atPath: path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let ownerID = attributes[.ownerAccountID] as? NSNumber,
              let permissions = attributes[.posixPermissions] as? NSNumber else {
            return false
        }
        return ownerID.uint32Value == 0 && (permissions.uint16Value & 0o4000) != 0
    }
}
