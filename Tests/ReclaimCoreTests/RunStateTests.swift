import XCTest
@testable import ReclaimCore

final class RunStateTests: XCTestCase {
    func finding(_ pid: Int32, _ category: String, _ verdict: Verdict) -> Finding {
        Finding(process: ProcessRecord(pid: pid, ppid: 1, cpu: 0, rssKB: 0, age: 0, user: "me", command: "x"),
                category: category, verdict: verdict, reason: "")
    }

    func testWedgedNeedsTwoSightings() {
        let wedged = finding(612, "wedged", .report)
        let first = Session.evaluate([wedged], previous: RunState(), swapHot: false, willKill: false)
        XCTAssertEqual(first.findings, [])
        XCTAssertEqual(first.state.hot, [612])
        let second = Session.evaluate([wedged], previous: first.state, swapHot: false, willKill: false)
        XCTAssertEqual(second.findings, [wedged])
    }

    func testUnchangedSetIncrementsQuietRuns() {
        let f = finding(1, "busy-loop", .report)
        let a = Session.evaluate([f], previous: RunState(), swapHot: false, willKill: false)
        XCTAssertFalse(a.unchanged)
        XCTAssertEqual(a.state.quietRuns, 0)
        let b = Session.evaluate([f], previous: a.state, swapHot: false, willKill: false)
        XCTAssertTrue(b.unchanged)
        XCTAssertEqual(b.state.quietRuns, 1)
        let c = Session.evaluate([f], previous: b.state, swapHot: false, willKill: false)
        XCTAssertEqual(c.state.quietRuns, 2)
    }

    func testKillingIsNeverQuiet() {
        let f = finding(1, "busy-loop", .kill)
        let a = Session.evaluate([f], previous: RunState(), swapHot: false, willKill: true)
        let b = Session.evaluate([f], previous: a.state, swapHot: false, willKill: true)
        XCTAssertFalse(b.unchanged)
        XCTAssertEqual(b.state.quietRuns, 0)
    }

    func testSwapJustHotFiresOnce() {
        let a = Session.evaluate([], previous: RunState(), swapHot: true, willKill: false)
        XCTAssertTrue(a.swapJustHot)
        let b = Session.evaluate([], previous: a.state, swapHot: true, willKill: false)
        XCTAssertFalse(b.swapJustHot)
    }

    func testSignatureIsOrderIndependent() {
        let a = [finding(2, "x", .kill), finding(1, "y", .report)]
        XCTAssertEqual(Session.signature(of: a), Session.signature(of: a.reversed()))
        XCTAssertEqual(Session.signature(of: a), "1:y:REPORT,2:x:KILL")
    }

    func testFirstEverRunIsNeverUnchanged() {
        let first = Session.evaluate([], previous: RunState(), swapHot: false, willKill: false)
        XCTAssertFalse(first.unchanged)
        XCTAssertEqual(first.state.quietRuns, 0)
        let second = Session.evaluate([], previous: first.state, swapHot: false, willKill: false)
        XCTAssertTrue(second.unchanged)
        XCTAssertEqual(second.state.quietRuns, 1)
    }

    func testPersistsRoundTrip() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("st-\(UUID())/state.json")
        var s = RunState(); s.quietRuns = 7; s.hot = [3]
        s.save(to: url)
        XCTAssertEqual(RunState.load(from: url), s)
        XCTAssertEqual(RunState.load(from: url.appendingPathExtension("missing")), RunState())
    }
}
