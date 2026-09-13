import XCTest
@testable import ReclaimCore

final class MonitorTests: XCTestCase {
    let utc = TimeZone(identifier: "UTC")!
    let t0 = Date(timeIntervalSince1970: 1_789_043_200)   // 12:26:40 UTC
    func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func record(_ pid: Int32, cpu: Double = 1, rssKB: Int = 1000, command: String = "x") -> ProcessRecord {
        ProcessRecord(pid: pid, ppid: 1, cpu: cpu, rssKB: rssKB, age: 7200, user: "me", command: command)
    }
    func finding(_ pid: Int32, _ category: String = "busy-loop", _ verdict: Verdict = .kill, cpu: Double = 1, rssKB: Int = 1000) -> Finding {
        Finding(process: record(pid, cpu: cpu, rssKB: rssKB), category: category, verdict: verdict, reason: "because")
    }
    func report(_ findings: [Finding], unchanged: Bool = false, dryRun: Bool = true, actions: [Int32: String] = [:],
                hogs: [ProcessRecord] = [], processCount: Int = 412, invalidRules: [Rule] = []) -> RunReport {
        RunReport(header: "swap n/a  ·  up 1h 0m", evaluation: Evaluation(findings: findings, unchanged: unchanged, swapJustHot: false, state: RunState()),
                  dryRun: dryRun, actions: actions, memoryHogs: hogs, processCount: processCount, invalidRules: invalidRules)
    }
    func monitor() -> Monitor { Monitor(config: Config(), timeZone: utc) }

    func testKillCountCountsKillRowsOnly() {
        var m = monitor()
        m.apply(report([finding(1, "busy-loop", .kill), finding(2, "busy-loop", .report), finding(3, "wedged", .report)]), at: t0)
        XCTAssertEqual(m.killCount, 1)
        XCTAssertEqual(m.killRows.map(\.process.pid), [1])
        XCTAssertEqual(m.reportRows.map(\.process.pid), [2, 3])
    }

    func testRowsSortLikeTheCLI() {
        var m = monitor()
        let idle = finding(1, rssKB: 1000), memory = finding(2, rssKB: 300 * 1024), cpu = finding(3, cpu: 50)
        m.apply(report([idle, memory, cpu]), at: t0)
        XCTAssertEqual(m.killRows.map(\.process.pid), [3, 2, 1])
    }

    func testKillTitleFollowsDryRun() {
        var m = monitor()
        m.apply(report([finding(1)], dryRun: true), at: t0)
        XCTAssertEqual(m.killTitle, "WOULD KILL")
        XCTAssertTrue(m.showsKillAll)
        m.apply(report([finding(1)], dryRun: false, actions: [1: "terminated"]), at: t0)
        XCTAssertEqual(m.killTitle, "KILLED")
        XCTAssertFalse(m.showsKillAll)
        XCTAssertEqual(m.action(for: 1), "terminated")
    }

    func testChangedAtMovesOnlyWhenTheSetChanges() {
        var m = monitor()
        m.apply(report([finding(1)]), at: t0)
        XCTAssertEqual(m.footer, "12:26:40")
        m.apply(report([finding(1)], unchanged: true), at: at(30))
        XCTAssertEqual(m.changedAt, t0)
        XCTAssertEqual(m.footer, "12:27:10 · same since 12:26")
        m.apply(report([finding(1), finding(2)]), at: at(60))
        XCTAssertEqual(m.changedAt, at(60))
        XCTAssertEqual(m.footer, "12:27:40")
    }

    func testEmptyState() {
        var m = monitor()
        XCTAssertTrue(m.isEmpty)
        XCTAssertEqual(m.footer, "checking…")
        m.apply(report([]), at: t0)
        XCTAssertTrue(m.isEmpty)
        XCTAssertEqual(m.emptyDetail, "412 processes checked at 12:26:40.")
        XCTAssertEqual(m.footer, "every 30s")
    }

    func testBadConfigKeepsTheLastGoodOneAndTheFirstTime() {
        var m = monitor()
        var custom = Config(); custom.pollSeconds = 10
        m.apply(config: custom)
        m.reject(configMessage: "typeMismatch", at: t0)
        m.reject(configMessage: "again", at: at(60))
        XCTAssertEqual(m.config.pollSeconds, 10)
        XCTAssertEqual(m.banner, "config.json invalid since 12:26 · using the last good one")
        m.apply(config: Config())
        XCTAssertNil(m.banner)
        XCTAssertEqual(m.config.pollSeconds, 30)
    }

    func testBadConfigAtLaunchSaysDefaults() {
        var m = monitor()
        m.reject(configMessage: "dataCorrupted", at: t0)
        XCTAssertEqual(m.banner, "config.json invalid · using defaults")
    }

    func testBannerListsInvalidRulesAndPipelineFailures() {
        var m = monitor()
        m.apply(report([], invalidRules: [Rule(name: "bad", match: "(", minAgeSeconds: 0, evidence: .orphaned)]), at: t0)
        XCTAssertEqual(m.banner, "rule \"bad\" ignored - invalid regex")
        m.apply(failure: .unknownUser, at: at(30))
        XCTAssertEqual(m.banner, "could not check processes: unknownUser")
        m.apply(report([]), at: at(60))
        XCTAssertNil(m.banner)
    }

    func testWedgedRowsAreNeverKillable() {
        XCTAssertFalse(Monitor.canKill(finding(1, "wedged", .report)))
        XCTAssertTrue(Monitor.canKill(finding(1, "busy-loop", .report)))
        XCTAssertTrue(Monitor.canKill(finding(1, "dev-server", .kill)))
    }

    func testManualKillShowsProgressThenTheResult() {
        var m = monitor()
        m.apply(report([finding(1), finding(2)]), at: t0)
        m.beginKill(1)
        XCTAssertEqual(m.action(for: 1), "killing…")
        m.finishKill(1, result: "terminated")
        XCTAssertEqual(m.action(for: 1), "terminated")
        m.apply(report([finding(2)]), at: at(30))
        XCTAssertNil(m.action(for: 1))   // row is gone, so is its note
    }

    func testHogsGroup() {
        var m = monitor()
        XCTAssertNil(m.hogsTitle)
        m.apply(report([], hogs: [record(9, rssKB: 2_000_000)]), at: t0)
        XCTAssertEqual(m.hogsTitle, "SWAP OVER 80% · biggest residents, whoever they belong to")
        XCTAssertFalse(m.isEmpty)
    }
}
