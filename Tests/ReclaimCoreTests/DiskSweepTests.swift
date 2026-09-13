import XCTest
@testable import ReclaimCore

final class DiskSweepTests: XCTestCase {
    /// A fake shell keyed by the first argument(s); unknown commands return "" (printed nothing).
    func fakeShell(_ table: [String: String?]) -> ShellRunner {
        { args, _ in
            let key = args.joined(separator: " ")
            if let hit = table.first(where: { key.hasPrefix($0.key) }) { return hit.value }
            return ""
        }
    }

    let fs = FileSystem(contents: { path in path.hasSuffix("GitHub") ? ["core.worktrees", "notes.txt"] : nil },
                        exists: { $0.hasSuffix("/Homebrew") || $0.hasSuffix("/core") },
                        isDirectory: { $0.hasSuffix("/core") }, home: "/Users/me")

    var disk: Disk {
        var d = Disk()
        d.worktreeRoot = "/Users/me/Documents/GitHub"
        d.caches = [CacheEntry(path: "~/Library/Caches/Homebrew", command: "brew cleanup -s", note: "downloaded bottles")]
        return d
    }

    func testDockerSectionFromFixtures() {
        let shell = fakeShell([
            "sh -c command -v docker": "/usr/local/bin/docker\n",
            "docker system df --format": #"{"Active":"3","Reclaimable":"1.452GB (60%)","Size":"2.4GB","TotalCount":"9","Type":"Images"}"# + "\n",
            "docker system df -v": "VOLUME NAME   LINKS   SIZE\ntrmnl_pgdata  1  54.2GB\napp_node_modules  0  812MB\n",
        ])
        let docker = DiskSweep.run(disk: disk, shell: shell, fs: fs).sections.first { $0.title == "docker" }!
        XCTAssertEqual(docker.bytes, 1_452_000_000 + 812_000_000)
        XCTAssertEqual(docker.lines[0], SweepLine(bytes: 1_452_000_000, label: "images", detail: "9 total, 3 active", command: "docker image prune -a"))
        XCTAssertEqual(docker.lines[1], SweepLine(bytes: 812_000_000, label: "volumes", detail: "1 unused and rebuildable", command: "docker volume rm app_node_modules"))
        XCTAssertEqual(docker.lines[2], SweepLine(bytes: 54_200_000_000, label: "volumes", detail: "1 look like data (trmnl_pgdata) - leave alone, never `docker volume prune`"))
    }

    func testDockerNotRunningIsANote() {
        let shell = fakeShell(["sh -c command -v docker": "/usr/local/bin/docker\n", "docker system df": ""])
        let docker = DiskSweep.run(disk: disk, shell: shell, fs: fs).sections.first { $0.title == "docker" }!
        XCTAssertEqual(docker.lines, [SweepLine(label: "", detail: "docker is installed but not running")])
    }

    func testWorktreesUseFloatDaysAndFullCommands() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let staleAt = Int(now.timeIntervalSince1970) - Int(21.5 * 86400)   // 21.5 days: stale under float compare
        let shell = fakeShell([
            "sh -c /usr/bin/du -sxk '/Users/me/Documents/GitHub/core.worktrees'/*/": "1000\t/Users/me/Documents/GitHub/core.worktrees/old/\n2000\t/Users/me/Documents/GitHub/core.worktrees/live/\n",
            "git -C /Users/me/Documents/GitHub/core worktree list": "worktree /Users/me/Documents/GitHub/core\nworktree /Users/me/Documents/GitHub/core.worktrees/live\n",
            "git -C /Users/me/Documents/GitHub/core.worktrees/old log": "\(staleAt)\n",
            "git -C /Users/me/Documents/GitHub/core.worktrees/live log": "\(Int(now.timeIntervalSince1970) - 3600)\n",
            "git -C /Users/me/Documents/GitHub/core.worktrees/old status": "",
            "git -C /Users/me/Documents/GitHub/core.worktrees/live status": "",
            "sh -c /usr/bin/du -sxk '/Users/me/Documents/GitHub/core.worktrees'/*/tmp": "0\tx\n",
        ])
        let wt = DiskSweep.run(disk: disk, shell: shell, fs: fs, now: now).sections.first { $0.title == "git worktrees" }!
        XCTAssertEqual(wt.bytes, 1000 * 1024)
        XCTAssertEqual(wt.lines[0], SweepLine(bytes: 3000 * 1024, label: "core", detail: "2 worktrees, 1 clean and untouched for 21+ days (0.00GB)"))
        XCTAssertEqual(wt.lines[1], SweepLine(bytes: 1000 * 1024, label: "old", detail: "21d, untracked by git", command: "rm -rf '/Users/me/Documents/GitHub/core.worktrees/old'", nested: true))
        XCTAssertEqual(wt.lines.last, SweepLine(label: "", detail: "check each one first - a worktree is unpushed work until proven otherwise"))
    }

    func testSkippedDuIsANoteNotASmallerNumber() {
        let shell = fakeShell(["/usr/bin/du -sxk /Users/me/Library/Caches/Homebrew": nil])   // nil = timed out
        var fs = self.fs
        fs.exists = { _ in true }
        let caches = DiskSweep.run(disk: disk, shell: shell, fs: fs).sections.first { $0.title == "caches" }!
        XCTAssertEqual(caches.bytes, 0)
        XCTAssertEqual(caches.lines, [SweepLine(label: "~/Library/Caches/Homebrew", detail: "skipped - du timed out")])
    }

    func testCacheBelowThresholdIsOmitted() {
        let shell = fakeShell(["/usr/bin/du -sxk": "50000\tx\n"])   // 51MB < 100MB
        var fs = self.fs
        fs.exists = { _ in true }
        let caches = DiskSweep.run(disk: disk, shell: shell, fs: fs).sections.first { $0.title == "caches" }!
        XCTAssertEqual(caches.lines, [])
    }
}
