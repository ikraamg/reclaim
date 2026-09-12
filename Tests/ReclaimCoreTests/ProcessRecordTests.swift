import XCTest
@testable import ReclaimCore

final class ProcessRecordTests: XCTestCase {
    func testParseElapsedHandlesEveryShape() {
        XCTAssertEqual(ProcessSnapshot.parseElapsed("10-04:49:39"), 10 * 86400 + 4 * 3600 + 49 * 60 + 39)
        XCTAssertEqual(ProcessSnapshot.parseElapsed("01:55"), 115)
        XCTAssertEqual(ProcessSnapshot.parseElapsed("04:49:39"), 4 * 3600 + 49 * 60 + 39)
        XCTAssertNil(ProcessSnapshot.parseElapsed("garbage"))
    }

    func testParsesPsRows() {
        let ps = """
            48213     1  98.0   12288 04:10:00 ikraam  zsh -c while :; do :; done
            31007   400   0.1  421888 02:03:11 ikraam  puma 8.0.2 (tcp://localhost:3000) [core]
              612     1  44.0   92160 10-06:20:00 root  /usr/libexec/duetexpertd
            bad line
            """
        let procs = ProcessSnapshot.parse(ps)
        XCTAssertEqual(procs.count, 3)
        XCTAssertEqual(procs[0], ProcessRecord(pid: 48213, ppid: 1, cpu: 98.0, rssKB: 12288,
                                               age: 4 * 3600 + 10 * 60, user: "ikraam",
                                               command: "zsh -c while :; do :; done"))
        XCTAssertEqual(procs[2].age, 10 * 86400 + 6 * 3600 + 20 * 60)
        XCTAssertEqual(procs[2].user, "root")
    }

    func testLiveSnapshotContainsThisProcess() {
        let me = ProcessInfo.processInfo.processIdentifier
        XCTAssertTrue(ProcessSnapshot.live().contains { $0.pid == me })
    }
}
