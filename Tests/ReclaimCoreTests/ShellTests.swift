import XCTest
import Darwin
@testable import ReclaimCore

final class ShellTests: XCTestCase {
    func testReturnsStdout() {
        XCTAssertEqual(shell(["echo", "hi"]), "hi\n")
    }

    func testMissingBinaryReturnsEmpty() {
        XCTAssertEqual(shell(["definitely-not-a-binary-xyz"]), "")
    }

    func testTimeoutReturnsEmptyPromptly() {
        let started = Date()
        XCTAssertNil(shell(["sleep", "5"], timeout: 1))
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testGrandchildHoldingThePipeDoesNotBlockPastTimeout() {
        let started = Date()
        // sh exits at once; the backgrounded sleep inherits stdout and holds EOF open for 5s.
        XCTAssertNil(shell(["sh", "-c", "sleep 5 & echo hi"], timeout: 1))
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testNonZeroExitStillReturnsStdout() {
        XCTAssertEqual(shell(["sh", "-c", "echo partial; exit 3"]), "partial\n")
    }

    func testKilledBySignalIsNil() {
        XCTAssertNil(shell(["sh", "-c", "kill -9 $$"], timeout: 5))
    }

    func testEmptyOutputIsEmptyNotNil() {
        XCTAssertEqual(shell(["true"]), "")
    }

    func testTimeoutsDoNotLeakThreads() {
        func threadCount() -> Int {
            var count: mach_msg_type_number_t = 0
            var list: thread_act_array_t?
            task_threads(mach_task_self_, &list, &count)
            return Int(count)
        }
        let before = threadCount()
        for _ in 1...10 { _ = shell(["sh", "-c", "sleep 4321.5 & echo hi"], timeout: 0.05) }
        XCTAssertLessThanOrEqual(threadCount(), before + 1)
        _ = shell(["pkill", "-f", "sleep 4321\\.5$"])
    }

    func testLargeOutputDrainsFullPipe() {
        XCTAssertEqual((shell(["sh", "-c", "head -c 300000 /dev/zero | tr '\\0' x"]) ?? "").count, 300000)
    }
}
