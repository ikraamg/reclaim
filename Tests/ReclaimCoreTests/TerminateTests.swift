import XCTest
@testable import ReclaimCore

final class TerminateTests: XCTestCase {
    func spawn(_ script: String) throws -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try p.run()
        Thread.sleep(forTimeInterval: 0.2)
        return p
    }

    func testTermIsEnough() throws {
        let child = try spawn("sleep 30")
        XCTAssertEqual(Terminate.run(pid: child.processIdentifier, grace: 0.5), "terminated")
        child.waitUntilExit()
        XCTAssertFalse(child.isRunning)
    }

    func testFallsBackToKill() throws {
        let child = try spawn("trap '' TERM; sleep 30")
        XCTAssertEqual(Terminate.run(pid: child.processIdentifier, grace: 0.5), "killed (-9, ignored TERM)")
        child.waitUntilExit()
        XCTAssertFalse(child.isRunning)
    }

    func testAlreadyGone() throws {
        let child = try spawn("true")
        child.waitUntilExit()
        XCTAssertEqual(Terminate.run(pid: child.processIdentifier, grace: 0.1), "already gone")
    }

    func testRefusesGroupAndSystemPids() {
        XCTAssertEqual(Terminate.run(pid: 0, grace: 0.1), "refused: pid 0 is not a single user process")
        XCTAssertEqual(Terminate.run(pid: -5, grace: 0.1), "refused: pid -5 is not a single user process")
        XCTAssertEqual(Terminate.run(pid: 1, grace: 0.1), "refused: pid 1 is not a single user process")
    }

    func record(_ pid: Int32, command: String) -> ProcessRecord {
        ProcessRecord(pid: pid, ppid: 1, cpu: 0, rssKB: 0, age: 100, user: "me", command: command)
    }

    func testRefusesWhenThePidRunsSomethingElse() throws {
        let child = try spawn("sleep 30")
        let pid = child.processIdentifier
        let result = Terminate.run(record(pid, command: "sleep 30"), grace: 0.5, currentCommand: { _ in "vim notes.txt" })
        XCTAssertEqual(result, "gone: pid \(pid) now runs something else")
        XCTAssertTrue(child.isRunning)
        child.terminate(); child.waitUntilExit()
    }

    func testProceedsWhenTheCommandStillMatches() throws {
        let child = try spawn("sleep 30")
        let result = Terminate.run(record(child.processIdentifier, command: "sleep 30"), grace: 0.5, currentCommand: { _ in "sleep 30" })
        XCTAssertEqual(result, "terminated")
        child.waitUntilExit()
    }

    func testGoneWhenNothingRunsThere() throws {
        let child = try spawn("true")
        child.waitUntilExit()
        XCTAssertEqual(Terminate.run(record(child.processIdentifier, command: "true"), grace: 0.1, currentCommand: { _ in nil }), "already gone")
        XCTAssertEqual(Terminate.run(record(child.processIdentifier, command: "true"), grace: 0.1, currentCommand: { _ in "" }), "already gone")
    }

    func testLiveCommandMatchesTheSnapshot() throws {
        let child = try spawn("sleep 30")
        defer { child.terminate(); child.waitUntilExit() }
        let record = ProcessSnapshot.live().first { $0.pid == child.processIdentifier }
        XCTAssertNotNil(record)
        XCTAssertEqual(Terminate.currentCommand(child.processIdentifier), record?.command)
    }
}
