import Foundation
import Darwin

/// Runs a command and returns its stdout. Empty string on failure or timeout; stderr is discarded.
public func shell(_ args: [String], timeout: TimeInterval = 20) -> String {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    task.arguments = args
    let stdout = Pipe()
    task.standardOutput = stdout
    task.standardError = FileHandle.nullDevice
    do { try task.run() } catch { return "" }

    // poll() with a deadline instead of a blocking read: a grandchild that inherits the pipe
    // can hold EOF open forever, and a thread parked on read() would leak per call.
    let fd = stdout.fileHandleForReading.fileDescriptor
    let deadline = Date().addingTimeInterval(timeout)
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 65536)
    reading: while true {
        let remaining = deadline.timeIntervalSinceNow
        if remaining <= 0 { if task.isRunning { task.terminate() }; return "" }
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let ready = poll(&pfd, 1, Int32(min(remaining * 1000, 1000)))
        if ready > 0 {
            let n = read(fd, &buffer, buffer.count)
            if n > 0 { data.append(buffer, count: n) } else { break reading }
        } else if ready < 0 && errno != EINTR { break reading }
    }
    task.waitUntilExit()
    return task.terminationReason == .exit ? String(decoding: data, as: UTF8.self) : ""
}
