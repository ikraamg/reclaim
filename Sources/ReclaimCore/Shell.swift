import Foundation

/// Runs a command and returns its stdout. Empty string on failure or timeout; stderr is discarded.
public func shell(_ args: [String], timeout: TimeInterval = 20) -> String {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    task.arguments = args
    let stdout = Pipe()
    task.standardOutput = stdout
    task.standardError = FileHandle.nullDevice
    do { try task.run() } catch { return "" }

    let killer = DispatchWorkItem { if task.isRunning { task.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    let timedOut = killer.isCancelled == false && task.terminationReason == .uncaughtSignal
    killer.cancel()
    return timedOut ? "" : String(decoding: data, as: UTF8.self)
}
