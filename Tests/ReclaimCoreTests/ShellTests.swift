import XCTest
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
        XCTAssertEqual(shell(["sleep", "5"], timeout: 1), "")
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }
}
