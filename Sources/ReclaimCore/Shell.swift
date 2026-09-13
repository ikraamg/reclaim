import Foundation
import Darwin

/// Runs a command and returns its stdout. nil on timeout, kill-by-signal, or failure to launch;
/// "" if it ran and printed nothing. stderr is discarded.
public func shell(_ args: [String], timeout: TimeInterval = 20) -> String? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    task.arguments = args
    let stdout = Pipe()
    task.standardOutput = stdout
    task.standardError = FileHandle.nullDevice
    do { try task.run() } catch { return nil }

    // poll() with a deadline instead of a blocking read: a grandchild that inherits the pipe
    // can hold EOF open forever, and a thread parked on read() would leak per call.
    let fd = stdout.fileHandleForReading.fileDescriptor
    let deadline = Date().addingTimeInterval(timeout)
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 65536)
    reading: while true {
        let remaining = deadline.timeIntervalSinceNow
        if remaining <= 0 { if task.isRunning { task.terminate() }; return nil }
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let ready = poll(&pfd, 1, Int32(min(remaining * 1000, 1000)))
        if ready > 0 {
            let n = read(fd, &buffer, buffer.count)
            if n > 0 { data.append(buffer, count: n) } else { break reading }
        } else if ready < 0 && errno != EINTR { break reading }
    }
    task.waitUntilExit()
    return task.terminationReason == .exit ? String(decoding: data, as: UTF8.self) : nil
}

public typealias ShellRunner = (_ args: [String], _ timeout: TimeInterval) -> String?
public let realShell: ShellRunner = { shell($0, timeout: $1) }

/// The file-system questions the sweeps ask, injectable so tests never touch the disk.
public struct FileSystem {
    public var contents: (String) -> [String]?
    public var exists: (String) -> Bool
    public var isDirectory: (String) -> Bool
    public var home: String

    public init(contents: @escaping (String) -> [String]?, exists: @escaping (String) -> Bool,
                isDirectory: @escaping (String) -> Bool, home: String = NSHomeDirectory()) {
        self.contents = contents; self.exists = exists; self.isDirectory = isDirectory; self.home = home
    }

    public func expand(_ path: String) -> String { path.hasPrefix("~") ? home + path.dropFirst(1) : path }
    public func tilde(_ path: String) -> String { path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path }

    public static let real = FileSystem(
        contents: { try? FileManager.default.contentsOfDirectory(atPath: $0) },
        exists: { FileManager.default.fileExists(atPath: $0) },
        isDirectory: { path in
            var d: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &d) && d.boolValue
        })
}
