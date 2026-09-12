import XCTest
@testable import ReclaimCore

final class ClassifierTests: XCTestCase {
    func testEverySelfCheckShape() {
        for shape in SelfCheck.shapes {
            let verdict = shape.run()
            if shape.expectKill {
                XCTAssertEqual(verdict, .kill, "PREDICATE BLIND: missed dead process (\(shape.name))")
            } else {
                XCTAssertNotEqual(verdict, .kill, "PREDICATE UNSAFE: would kill a live process (\(shape.name))")
            }
        }
    }

    func testFailuresIsEmpty() {
        XCTAssertEqual(SelfCheck.failures(), [])
    }

    func testWedgedForeignProcessIsReportedWithRespawnHint() {
        let p = ProcessRecord(pid: 612, ppid: 1, cpu: 44, rssKB: 1000, age: 6 * 3600,
                              user: "root", command: "/usr/libexec/duetexpertd")
        let f = Classifier(config: Config()).classify(p, in: Context.forTests(processes: [p]))
        XCTAssertEqual(f?.category, "wedged")
        XCTAssertEqual(f?.verdict, .report)
        XCTAssertTrue(f?.reason.contains("killall respawns it clean") ?? false)
    }

    func testWedgedUnknownDaemonHasNoKillAdvice() {
        let p = ProcessRecord(pid: 613, ppid: 1, cpu: 90, rssKB: 1000, age: 6 * 3600,
                              user: "root", command: "/usr/libexec/somethingelse")
        let f = Classifier(config: Config()).classify(p, in: Context.forTests(processes: [p]))
        XCTAssertTrue(f?.reason.contains("not safe to kill") ?? false)
    }

    func testBoundPumaIsIgnoredEntirely() {
        let p = ProcessRecord(pid: 77, ppid: 1, cpu: 1, rssKB: 300_000, age: 864_000,
                              user: "me", command: "puma 8.0.2 (tcp://localhost:3000) [core]")
        let ctx = Context.forTests(processes: [p], listeners: [3000: [77]])
        XCTAssertNil(Classifier(config: Config()).classify(p, in: ctx))
    }

    func testInvalidRuleRegexIsExposedNotSwallowed() {
        var config = Config()
        config.rules = [Rule(name: "broken", match: "(", minAgeSeconds: 1, evidence: .orphaned)]
        let classifier = Classifier(config: config)
        XCTAssertEqual(classifier.invalidRules.map(\.name), ["broken"])

        let p = ProcessRecord(pid: 700, ppid: 1, cpu: 1, rssKB: 1000, age: 10,
                              user: "me", command: "(")
        XCTAssertNil(classifier.classify(p, in: Context.forTests(processes: [p])))
    }

    func testPortUnboundRuleWithNoCaptureGroupIsReportedNotJudged() {
        var config = Config()
        config.rules = [Rule(name: "dev-server", match: "^puma", minAgeSeconds: 900, evidence: .portUnbound)]
        let p = ProcessRecord(pid: 701, ppid: 1, cpu: 1, rssKB: 300_000, age: 864_000,
                              user: "me", command: "puma 8.0.2 (tcp://localhost:3111) [gone]")
        let f = Classifier(config: config).classify(p, in: Context.forTests(processes: [p], listeners: [3000: [77]]))
        XCTAssertEqual(f?.verdict, .report)
        XCTAssertTrue(f?.reason.contains("no port capture group") ?? false)
    }

    func testDevServerReasonCarriesWorktreeNote() {
        let p = ProcessRecord(pid: 500, ppid: 1, cpu: 1, rssKB: 300_000, age: 864_000,
                              user: "me", command: "puma 8.0.2 (tcp://localhost:3111) [gone]")
        var ctx = Context.forTests(processes: [p], listeners: [3000: [77]])
        ctx.cwds = [500: "/repo/.worktrees/old"]
        ctx.worktreeNote = { _ in " (its worktree /repo/.worktrees/old is gone)" }
        let f = Classifier(config: Config()).classify(p, in: ctx)
        XCTAssertEqual(f?.reason, "nothing is listening on port 3111 (its worktree /repo/.worktrees/old is gone)")
    }
}

extension Context {
    static func forTests(processes: [ProcessRecord], listeners: [Int: Set<Int32>]? = [3000: [77]]) -> Context {
        Context(processes: processes, me: "me", untouchable: [1], listeners: listeners,
                cwds: [:], worktreeNote: { _ in "" })
    }
}
