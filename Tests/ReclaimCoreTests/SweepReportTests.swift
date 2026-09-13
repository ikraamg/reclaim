import XCTest
@testable import ReclaimCore

final class SweepReportTests: XCTestCase {
    let sweep = Sweep(kind: "disk",
                      header: ["disk: 454GB used, 435GB free (52% full)  ·  nothing below is deleted automatically"],
                      sections: [
                          SweepSection(title: "caches", bytes: 2_100_000_000, lines: [
                              SweepLine(text: "    1.96GB  ~/Library/Caches/Homebrew                      brew cleanup -s", command: "brew cleanup -s"),
                              SweepLine(text: "            downloaded bottles", command: nil)]),
                          SweepSection(title: "docker", bytes: 0, lines: []),
                      ],
                      footer: ["total reclaimable: 1.96GB"])

    func testGigabytes() {
        XCTAssertEqual(gigabytes(2_100_000_000), "  1.96GB")
        XCTAssertEqual(gigabytes(0), "  0.00GB")
    }

    func testTextSkipsEmptySections() {
        XCTAssertEqual(SweepReport.text(sweep), """
            disk: 454GB used, 435GB free (52% full)  ·  nothing below is deleted automatically

            caches - 1.96GB reclaimable
                1.96GB  ~/Library/Caches/Homebrew                      brew cleanup -s
                        downloaded bottles

            total reclaimable: 1.96GB

            """)
    }

    func testJSONCarriesCommandsAndNullForNotes() throws {
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(SweepReport.json(sweep).utf8)) as? [String: Any])
        XCTAssertEqual(obj["kind"] as? String, "disk")
        let sections = try XCTUnwrap(obj["sections"] as? [[String: Any]])
        XCTAssertEqual(sections.count, 2)
        let lines = try XCTUnwrap(sections[0]["lines"] as? [[String: Any]])
        XCTAssertEqual(lines[0]["command"] as? String, "brew cleanup -s")
        XCTAssertTrue(lines[1]["command"] is NSNull)
        XCTAssertFalse(SweepReport.json(sweep).contains("\\/"))
    }

    func testJSONEmitsNullBytesForNilSections() throws {
        let bootSweep = Sweep(kind: "boot", header: [], sections: [
            SweepSection(title: "x", bytes: nil, lines: [])
        ], footer: [])
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(SweepReport.json(bootSweep).utf8)) as? [String: Any])
        let sections = try XCTUnwrap(obj["sections"] as? [[String: Any]])
        let section = sections[0]
        XCTAssertTrue(section.keys.contains("bytes"))
        XCTAssertTrue(section["bytes"] is NSNull)
    }
}
