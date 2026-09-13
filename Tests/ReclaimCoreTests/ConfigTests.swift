import XCTest
@testable import ReclaimCore

final class ConfigTests: XCTestCase {
    func testDefaultsMatchTheScript() {
        let c = Config()
        XCTAssertEqual(c.pollSeconds, 30)
        XCTAssertFalse(c.autoKill)
        XCTAssertEqual(c.rules.map(\.name), ["dev-server", "busy-loop", "file-watcher", "mcp-server"])
        XCTAssertEqual(c.rules[0].evidence, .portUnbound)
        XCTAssertEqual(c.rules[0].minAgeSeconds, 900)
        XCTAssertEqual(c.rules[1].minAgeSeconds, 3600)
        XCTAssertEqual(c.wedged.percent, 40)
        XCTAssertEqual(c.neverKill, ["launchd", "kernel_task", "loginwindow", "WindowServer"])
        XCTAssertTrue(c.respawnsClean.contains("duetexpertd"))
    }

    func testBootAndDiskDefaultsMatchTheScript() {
        let c = Config()
        XCTAssertEqual(c.boot.keep, ["homebrew.mxcl.", "com.grammarly.", "com.ikraam.", "com.logi.optionsplus",
                                     "com.docker.", "com.nordvpn.macos.helper", "us.zoom.ZoomDaemon"])
        XCTAssertEqual(c.boot.cpuHog.percent, 50); XCTAssertEqual(c.boot.cpuHog.minAgeSeconds, 1800)
        XCTAssertEqual(c.disk.worktreeStaleDays, 21)
        XCTAssertEqual(c.disk.regenerableInRepo, ["tmp", "log", "node_modules", "coverage"])
        XCTAssertTrue(c.disk.volumeIsData.contains("pgdata")); XCTAssertTrue(c.disk.volumeIsRebuildable.contains("node_modules"))
        XCTAssertEqual(c.disk.caches.count, 11)
        XCTAssertEqual(c.disk.caches[0].path, "~/Library/Developer/Xcode/DerivedData")
        XCTAssertEqual(c.disk.caches[0].command, "rm -rf ~/Library/Developer/Xcode/DerivedData/*")
    }

    func testPartialDiskSectionKeepsOtherDefaults() throws {
        let c = try JSONDecoder().decode(Config.self, from: Data(#"{"disk":{"worktreeStaleDays":7}}"#.utf8))
        XCTAssertEqual(c.disk.worktreeStaleDays, 7)
        XCTAssertEqual(c.disk.caches.count, 11)
        XCTAssertEqual(c.boot.keep.count, 7)
    }

    func testRoundTripsThroughJSON() throws {
        var c = Config()
        c.autoKill = true
        c.rules.append(Rule(name: "vite", match: "vite --port (\\d+)", minAgeSeconds: 600, evidence: .portUnbound))
        c.disk.worktreeStaleDays = 3
        let data = try JSONEncoder().encode(c)
        XCTAssertEqual(try JSONDecoder().decode(Config.self, from: data), c)
    }

    func testMissingKeysTakeDefaults() throws {
        let partial = Data(#"{"autoKill": true}"#.utf8)
        let c = try JSONDecoder().decode(Config.self, from: partial)
        XCTAssertTrue(c.autoKill)
        XCTAssertEqual(c.pollSeconds, 30)
        XCTAssertEqual(c.rules.count, 4)
    }

    func testUnknownEvidenceIsRejected() {
        let bad = Data(#"{"rules":[{"name":"x","match":"x","minAgeSeconds":1,"evidence":"vibes"}]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Config.self, from: bad))
    }

    func testLoadOfMissingFileReturnsDefaults() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID()).json")
        XCTAssertEqual(try? Config.load(from: url).get(), Config())
    }

    func testLoadOfInvalidJSONReturnsError() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bad-\(UUID()).json")
        try Data("{not json".utf8).write(to: url)
        guard case .failure(.invalid) = Config.load(from: url) else { return XCTFail("expected .invalid") }
    }

    func testSaveThenLoad() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cfg-\(UUID())/config.json")
        var c = Config(); c.pollSeconds = 5
        try c.save(to: url)
        XCTAssertEqual(try Config.load(from: url).get(), c)
    }
}
