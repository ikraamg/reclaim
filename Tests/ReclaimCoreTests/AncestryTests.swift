import XCTest
@testable import ReclaimCore

final class AncestryTests: XCTestCase {
    func record(pid: Int32, ppid: Int32) -> ProcessRecord {
        ProcessRecord(pid: pid, ppid: ppid, cpu: 0, rssKB: 0, age: 0, user: "me", command: "x")
    }

    func testFullChainToPid1() {
        let byPid: [Int32: ProcessRecord] = [
            500: record(pid: 500, ppid: 400),
            400: record(pid: 400, ppid: 300),
            300: record(pid: 300, ppid: 1),
        ]
        let result = Ancestry.untouchable(from: 500, in: byPid)
        XCTAssertEqual(result, [0, 1, 500, 400, 300])
        XCTAssertFalse(result.contains(999))
    }

    func testStopsWhenAParentIsMissingFromTheSnapshot() {
        let byPid: [Int32: ProcessRecord] = [
            500: record(pid: 500, ppid: 400),
            400: record(pid: 400, ppid: 350),
            // 350 is absent - its own record was never captured.
        ]
        let result = Ancestry.untouchable(from: 500, in: byPid)
        XCTAssertEqual(result, [0, 1, 500, 400, 350])
    }

    func testCycleTerminates() {
        let byPid: [Int32: ProcessRecord] = [
            500: record(pid: 500, ppid: 400),
            400: record(pid: 400, ppid: 500),
        ]
        let result = Ancestry.untouchable(from: 500, in: byPid)
        XCTAssertEqual(result, [0, 1, 500, 400])
    }
}
