import XCTest
@testable import ReclaimCore

final class CommandLineInterfaceTests: XCTestCase {
    func run(_ args: [String]) -> (status: Int32, out: String, err: String) {
        var out = "", err = ""
        let status = CommandLineInterface.run(args, stdout: { out += $0 }, stderr: { err += $0 })
        return (status, out, err)
    }

    func testRefusesUnknownFlag() {
        let r = run(["--dry-run", "--nope"])
        XCTAssertEqual(r.status, 2)
        XCTAssertEqual(r.err, "reclaim: unknown flag --nope - refusing to run\n")
        XCTAssertEqual(r.out, "")
    }

    func testRefusesBothSweepsAtOnce() {
        let r = run(["--disk", "--boot"])
        XCTAssertEqual(r.status, 2)
        XCTAssertEqual(r.err, "reclaim: pick one of --disk or --boot\n")
    }

    func testSelfCheckReportsTheContract() {
        let r = run(["--self-check"])
        XCTAssertEqual(r.status, 0)
        XCTAssertEqual(r.out, "self-check passed: 11 live shapes protected, 5 dead shapes caught\n")
        XCTAssertEqual(r.err, "")
    }
}
