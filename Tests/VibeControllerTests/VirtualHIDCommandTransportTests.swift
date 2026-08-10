@testable import VibeController
import Foundation
import XCTest

final class VirtualHIDCommandTransportTests: XCTestCase {
    func testConcurrentPointerCommandsRemainCompleteFixedWidthFrames() throws {
        let transport = VirtualHIDCommandTransport()
        let pipe = Pipe()
        transport.connect(fileHandle: pipe.fileHandleForWriting)
        transport.updateReadiness(pointing: true, keyboard: true)

        let commandCount = 100
        let successfulWrites = LockedCounter()
        DispatchQueue.concurrentPerform(iterations: commandCount) { index in
            if transport.postPointing(
                x: Int8(index % 100),
                y: Int8(-(index % 100)),
                buttons: UInt32(index)
            ) {
                successfulWrites.increment()
            }
        }

        transport.disconnect()
        try pipe.fileHandleForWriting.close()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        XCTAssertEqual(successfulWrites.value, commandCount)
        XCTAssertEqual(data.count, commandCount * 16)
        for offset in stride(from: 0, to: data.count, by: 16) {
            XCTAssertEqual(data[offset], VirtualHIDCommandTransport.CommandKind.pointing.rawValue)
        }
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
