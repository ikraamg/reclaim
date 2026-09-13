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

    func testParseTracked() {
        XCTAssertEqual(Worktree.parseTracked("worktree /a\nHEAD x\nworktree /b\n"), ["/a", "/b"])
    }

    func testWorktreeNoteForMissingDirectory() {
        XCTAssertEqual(Worktree.note(cwd: "/definitely/not/here/.worktrees/x"),
                       " (its worktree /definitely/not/here/.worktrees/x is gone)")
        XCTAssertEqual(Worktree.note(cwd: nil), "")
        XCTAssertEqual(Worktree.note(cwd: FileManager.default.temporaryDirectory.path), "")
    }

    func testWorktreeNoteDistinguishesTrackedFromUntracked() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("wt-\(UUID())")
        let repo = base.appendingPathComponent("repo").path
        let worktrees = base.appendingPathComponent("repo.worktrees").path
        try FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
        _ = shell(["git", "-C", repo, "init", "-q"])
        _ = shell(["git", "-C", repo, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "init"])
        _ = shell(["git", "-C", repo, "worktree", "add", "-q", "\(worktrees)/live", "-b", "live"])
        try FileManager.default.createDirectory(atPath: "\(worktrees)/stale", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        // Resolve symlinks on macOS temp dirs which may have /var/folders vs /private/var/folders.
        // git worktree list returns resolved paths; we must resolve both input and output paths
        // using the same method git uses (realpath).
        let resolveSymlinks = { (path: String) in
            (shell(["realpath", path]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let repoResolved = resolveSymlinks(repo)
        let staleResolved = resolveSymlinks("\(worktrees)/stale")
        let liveResolved = resolveSymlinks("\(worktrees)/live")

        XCTAssertEqual(Worktree.note(cwd: staleResolved), " (git no longer tracks worktree stale)")
        XCTAssertEqual(Worktree.note(cwd: liveResolved), "")
        XCTAssertTrue(Worktree.tracked(in: repoResolved).contains(liveResolved))
    }
}
