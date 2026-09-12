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
}
