import XCTest
@testable import ReclaimCore

final class PipelineTests: XCTestCase {
    final class Calls { var terminated: [Int32] = []; var listenerReads = 0 }

    static let tenDays = 10 * 86400
    let spinLoop = ProcessRecord(pid: 500, ppid: 1, cpu: 99, rssKB: 4_000, age: tenDays, user: "me", command: "zsh -c 'while :; do :; done'")
    let youngLoop = ProcessRecord(pid: 501, ppid: 1, cpu: 99, rssKB: 4_000, age: 30, user: "me", command: "zsh -c 'while :; do :; done'")
    let puma = ProcessRecord(pid: 77, ppid: 1, cpu: 0, rssKB: 300_000, age: tenDays, user: "me", command: "puma 8.0.2 (tcp://localhost:3111) [gone]")

    func machine(_ processes: [ProcessRecord], user: String? = "me", isRoot: Bool = false, selfPid: Int32 = 999,
                 swapPercent: Double = 10, calls: Calls = Calls()) -> Machine {
        Machine(processes: { processes },
                user: { user },
                listeners: { calls.listenerReads += 1; return [3000: [1]] },
                cwd: { _ in nil },
                worktreeNote: { _ in "" },
                system: { SystemState(swapUsedMB: swapPercent * 10, swapTotalMB: 1000, uptimeSeconds: 60,
                                      batteryPercent: nil, batteryState: nil, thermal: []) },
                terminate: { calls.terminated.append($0.pid); return "terminated" },
                selfPid: selfPid, parentPid: 998, isRoot: isRoot)
    }

    func testDryRunNeverTerminates() throws {
        let calls = Calls()
        let report = try Pipeline.run(config: Config(), dryRun: true, previous: RunState(), on: machine([spinLoop], calls: calls)).get()
        XCTAssertEqual(report.evaluation.findings.map(\.verdict), [.kill])
        XCTAssertEqual(report.actions, [:])
        XCTAssertEqual(calls.terminated, [])
        XCTAssertTrue(report.dryRun)
    }

    func testKillsOnlyKillVerdicts() throws {
        let calls = Calls()
        let report = try Pipeline.run(config: Config(), dryRun: false, previous: RunState(), on: machine([spinLoop, youngLoop], calls: calls)).get()
        XCTAssertEqual(report.actions, [500: "terminated"])
        XCTAssertEqual(calls.terminated, [500])
        XCTAssertEqual(Set(report.evaluation.findings.map(\.verdict)), [.kill, .report])
    }

    func testRefusesRootUnlessDryRun() {
        XCTAssertEqual(Pipeline.run(config: Config(), dryRun: false, previous: RunState(), on: machine([spinLoop], isRoot: true)).failure, .rootWithoutDryRun)
        XCTAssertNotNil(try? Pipeline.run(config: Config(), dryRun: true, previous: RunState(), on: machine([spinLoop], isRoot: true)).get())
    }

    func testRefusesUnknownUser() {
        XCTAssertEqual(Pipeline.run(config: Config(), dryRun: true, previous: RunState(), on: machine([spinLoop], user: nil)).failure, .unknownUser)
        XCTAssertEqual(Pipeline.run(config: Config(), dryRun: true, previous: RunState(), on: machine([spinLoop], user: "")).failure, .unknownUser)
    }

    func testNeverJudgesItself() throws {
        let calls = Calls()
        let report = try Pipeline.run(config: Config(), dryRun: false, previous: RunState(), on: machine([spinLoop], selfPid: 500, calls: calls)).get()
        XCTAssertEqual(report.evaluation.findings, [])
        XCTAssertEqual(calls.terminated, [])
    }

    func testReadsListenersOnlyWhenAPortRuleMatched() throws {
        let quiet = Calls()
        _ = try Pipeline.run(config: Config(), dryRun: true, previous: RunState(), on: machine([spinLoop], calls: quiet)).get()
        XCTAssertEqual(quiet.listenerReads, 0)
        let probed = Calls()
        let report = try Pipeline.run(config: Config(), dryRun: true, previous: RunState(), on: machine([puma], calls: probed)).get()
        XCTAssertEqual(probed.listenerReads, 1)
        XCTAssertEqual(report.evaluation.findings.map(\.verdict), [.kill])
    }

    func testReportsCountAndInvalidRules() throws {
        var config = Config()
        config.rules.append(Rule(name: "broken", match: "(", minAgeSeconds: 0, evidence: .orphaned))
        let report = try Pipeline.run(config: config, dryRun: true, previous: RunState(), on: machine([spinLoop, youngLoop])).get()
        XCTAssertEqual(report.processCount, 2)
        XCTAssertEqual(report.invalidRules.map(\.name), ["broken"])
    }

    func testListsMemoryHogsWhenSwapIsHot() throws {
        let hog = ProcessRecord(pid: 9, ppid: 1, cpu: 0, rssKB: 2_000_000, age: 100, user: "root", command: "big")
        let report = try Pipeline.run(config: Config(), dryRun: true, previous: RunState(), on: machine([spinLoop, hog], swapPercent: 90)).get()
        XCTAssertEqual(report.memoryHogs.map(\.pid), [9, 500])
        XCTAssertTrue(report.evaluation.swapJustHot)
    }

    func testReportsHotProcessesAndSystemState() throws {
        let cold = ProcessRecord(pid: 11, ppid: 1, cpu: 1, rssKB: 1000, age: 100, user: "me", command: "idle")
        let hotCPU = ProcessRecord(pid: 12, ppid: 1, cpu: 55, rssKB: 1000, age: 100, user: "root", command: "WindowServer")
        let hotMemory = ProcessRecord(pid: 13, ppid: 1, cpu: 0, rssKB: 5 * 1024 * 1024, age: 100, user: "me", command: "Xcode")
        let report = try Pipeline.run(config: Config(), dryRun: true, previous: RunState(), on: machine([cold, hotCPU, hotMemory], swapPercent: 30)).get()
        XCTAssertEqual(report.hotProcesses.map(\.pid), [12, 13])
        XCTAssertEqual(report.system.swapPercent, 30)
    }
}

private extension Result where Failure == PipelineError {
    var failure: PipelineError? { if case .failure(let e) = self { return e } else { return nil } }
}
