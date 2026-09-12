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

    func testRoundTripsThroughJSON() throws {
        var c = Config()
        c.autoKill = true
        c.rules.append(Rule(name: "vite", match: "vite --port (\\d+)", minAgeSeconds: 600, evidence: .portUnbound))
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
