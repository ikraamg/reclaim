import XCTest
@testable import ReclaimCore

final class SweepReportTests: XCTestCase {
    let sweep = Sweep(kind: "disk",
                      header: ["disk: 454GB used, 435GB free (52% full)  ·  nothing below is deleted automatically"],
                      sections: [
                          SweepSection(title: "caches", bytes: 2_100_000_000, lines: [
                              SweepLine(bytes: 2_100_000_000, label: "~/Library/Caches/Homebrew", detail: "downloaded bottles", command: "brew cleanup -s"),
                              SweepLine(bytes: 150_000_000, label: "~/.Trash", command: "rm -rf ~/.Trash/*"),
                              SweepLine(label: "", detail: "check each one first")]),
                          SweepSection(title: "git worktrees", bytes: 600_000_000, lines: [
                              SweepLine(bytes: 9_000_000_000, label: "core", detail: "47 worktrees, 1 stale"),
                              SweepLine(bytes: 600_000_000, label: "old-feature", detail: "31d, tracked", command: "git -C ~/core worktree remove ~/core.worktrees/old-feature", nested: true)]),
                          SweepSection(title: "docker", bytes: 0, lines: []),
                      ],
                      footer: ["total reclaimable: 2.51GB"])

    func testGigabytes() {
        XCTAssertEqual(gigabytes(2_100_000_000), "  1.96GB")
        XCTAssertEqual(gigabytes(0), "  0.00GB")
    }

    func testTextRendersColumnsPerSection() {
        XCTAssertEqual(SweepReport.text(sweep), """
            disk: 454GB used, 435GB free (52% full)  ·  nothing below is deleted automatically

            caches - 1.96GB reclaimable
                1.96GB  ~/Library/Caches/Homebrew  downloaded bottles   brew cleanup -s
                0.14GB  ~/.Trash                      rm -rf ~/.Trash/*
                        check each one first

            git worktrees - 0.56GB reclaimable
                8.38GB  core         47 worktrees, 1 stale
                  0.56GB  old-feature  31d, tracked   git -C ~/core worktree remove ~/core.worktrees/old-feature

            total reclaimable: 2.51GB

            """)
    }

    func testJSONCarriesEveryKeyWithNulls() throws {
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(SweepReport.json(sweep).utf8)) as? [String: Any])
        let sections = try XCTUnwrap(obj["sections"] as? [[String: Any]])
        let lines = try XCTUnwrap(sections[0]["lines"] as? [[String: Any]])
        XCTAssertEqual(Set(lines[0].keys), ["bytes", "label", "detail", "command", "nested"])
        XCTAssertEqual(lines[0]["command"] as? String, "brew cleanup -s")
        XCTAssertTrue(lines[2]["bytes"] is NSNull)
        XCTAssertTrue(lines[2]["command"] is NSNull)
        XCTAssertTrue(sections[2]["bytes"] is NSNull == false)   // 0, not null
        XCTAssertFalse(SweepReport.json(sweep).contains("\\/"))
    }

    func testEmptyHeaderDoesNotPrintBlankLines() {
        let s = Sweep(kind: "boot", header: [], sections: [SweepSection(title: "x", bytes: nil, lines: [SweepLine(label: "a")])], footer: [])
        XCTAssertTrue(SweepReport.text(s).hasPrefix("x\n"))
    }
}
