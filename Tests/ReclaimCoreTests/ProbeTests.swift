import XCTest
@testable import ReclaimCore

final class ProbeTests: XCTestCase {
    func testParsesLsofListenTable() {
        let out = """
            p77
            n*:3000
            n127.0.0.1:3000
            p4242
            n[::1]:5432
            pnotanumber
            """
        XCTAssertEqual(Probe.parseListeners(out), [3000: [77], 5432: [4242]])
    }

    func testParsesCwd() {
        XCTAssertEqual(Probe.parseCwd("p500\nfcwd\nn/Users/me/repo\n"), "/Users/me/repo")
        XCTAssertNil(Probe.parseCwd(""))
    }

    func testLiveListenersSeesABoundSocket() throws {
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        server.arguments = ["-l", "127.0.0.1", "38471"]
        try server.run()
        defer { server.terminate() }
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(Probe.listeners()?[38471], [server.processIdentifier])
    }

    func testWorktreeNoteForMissingDirectory() {
        XCTAssertEqual(Worktree.note(cwd: "/definitely/not/here/.worktrees/x"),
                       " (its worktree /definitely/not/here/.worktrees/x is gone)")
        XCTAssertEqual(Worktree.note(cwd: nil), "")
        XCTAssertEqual(Worktree.note(cwd: FileManager.default.temporaryDirectory.path), "")
    }
}
