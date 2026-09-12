import XCTest
@testable import ReclaimCore

final class ReportTests: XCTestCase {
    let loop = ProcessRecord(pid: 48213, ppid: 1, cpu: 98.0, rssKB: 12 * 1024, age: 4 * 3600 + 10 * 60,
                             user: "me", command: "zsh -c while :; do :; done")
    let puma = ProcessRecord(pid: 31007, ppid: 1, cpu: 0.1, rssKB: 412 * 1024, age: 2 * 3600 + 3 * 60,
                             user: "me", command: "puma 8.0.2 (tcp://localhost:3000) [core]")
    let daemon = ProcessRecord(pid: 612, ppid: 1, cpu: 44.0, rssKB: 90 * 1024, age: 6 * 3600 + 20 * 60,
                               user: "root", command: "/usr/libexec/duetexpertd")

    var findings: [Finding] {
        [Finding(process: puma, category: "dev-server", verdict: .kill, reason: "nothing is listening on port 3000"),
         Finding(process: loop, category: "busy-loop", verdict: .kill, reason: "orphaned busy-loop, parent long gone"),
         Finding(process: daemon, category: "wedged", verdict: .report, reason: "44% CPU for 6h 20m - killall respawns it clean")]
    }

    func report(dryRun: Bool, unchanged: Bool = false) -> RunReport {
        var state = RunState(); state.quietRuns = unchanged ? 14 : 0
        let evaluation = Evaluation(findings: findings, unchanged: unchanged, swapJustHot: false, state: state)
        return RunReport(header: "swap n/a  ·  up 3d 4h", evaluation: evaluation, dryRun: dryRun,
                         actions: dryRun ? [:] : [31007: "terminated", 48213: "terminated"], memoryHogs: [])
    }

    func testBands() {
        XCTAssertEqual(band(of: loop), .burningCPU)
        XCTAssertEqual(band(of: puma), .holdingMemory)
        XCTAssertEqual(band(of: ProcessRecord(pid: 1, ppid: 1, cpu: 0, rssKB: 10, age: 0, user: "", command: "")), .idleWeight)
    }

    func testTextDryRunGroupsByVerdictThenBand() {
        let text = TextReport.render(report(dryRun: true))
        XCTAssertEqual(text, """
            swap n/a  ·  up 3d 4h

            WOULD KILL (2)
              ~ burning CPU
                48213  busy-loop     98.0%cpu     12MB  4h 10m    zsh -c while :; do :; done
                       orphaned busy-loop, parent long gone
              ~ holding memory
                31007  dev-server     0.1%cpu    412MB  2h 3m     puma 8.0.2 (tcp://localhost:3000) [core]
                       nothing is listening on port 3000

            REPORTED - your call (1)
              ~ burning CPU
                612    wedged        44.0%cpu     90MB  6h 20m    /usr/libexec/duetexpertd
                       44% CPU for 6h 20m - killall respawns it clean

            """)
    }

    func testTextLiveRunAppendsActions() {
        let text = TextReport.render(report(dryRun: false))
        XCTAssertTrue(text.hasPrefix("swap n/a  ·  up 3d 4h\n\nKILLED (2)"))
        XCTAssertTrue(text.contains("nothing is listening on port 3000  -> terminated"))
    }

    func testTextUnchangedCollapsesToOneLine() {
        XCTAssertEqual(TextReport.render(report(dryRun: true, unchanged: true)),
                       "reclaim: same 3 item(s) as last run, unchanged for 14 runs.  swap n/a  ·  up 3d 4h\n")
    }

    func testTextNothingToClean() {
        let evaluation = Evaluation(findings: [], unchanged: false, swapJustHot: false, state: RunState())
        let r = RunReport(header: "swap n/a  ·  up 1m", evaluation: evaluation, dryRun: true, actions: [:], memoryHogs: [])
        XCTAssertEqual(TextReport.render(r), "reclaim: nothing to clean.  swap n/a  ·  up 1m\n")
    }

    func testJSONShape() throws {
        let data = Data(JSONReport.render(report(dryRun: false)).utf8)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["header"] as? String, "swap n/a  ·  up 3d 4h")
        XCTAssertEqual(obj["dryRun"] as? Bool, false)
        XCTAssertEqual(obj["unchanged"] as? Bool, false)
        let rows = try XCTUnwrap(obj["findings"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 3)
        let first = try XCTUnwrap(rows.first { ($0["pid"] as? Int) == 31007 })
        XCTAssertEqual(first["category"] as? String, "dev-server")
        XCTAssertEqual(first["verdict"] as? String, "KILL")
        XCTAssertEqual(first["band"] as? String, "holding memory")
        XCTAssertEqual(first["rssMB"] as? Int, 412)
        XCTAssertEqual(first["action"] as? String, "terminated")
    }
}
