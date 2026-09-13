import XCTest
@testable import ReclaimCore

final class FileSystemTests: XCTestCase {
    let fs = FileSystem(contents: { _ in nil }, exists: { _ in false }, isDirectory: { _ in false }, home: "/Users/me")

    func testExpandsTilde() {
        XCTAssertEqual(fs.expand("~/x"), "/Users/me/x")
    }

    func testTildeContractsHomePrefixedPath() {
        XCTAssertEqual(fs.tilde("/Users/me/x"), "~/x")
    }

    func testTildeLeavesBarePrefixMatchAlone() {
        XCTAssertEqual(fs.tilde("/Users/me-old/x"), "/Users/me-old/x")
    }
}
