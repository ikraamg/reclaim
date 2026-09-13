import XCTest
@testable import ReclaimCore

final class DiskParseTests: XCTestCase {
    func testSizeMatchesThePythonPins() {
        XCTAssertEqual(DiskParse.size("1.452GB"), 1_452_000_000)
        XCTAssertEqual(DiskParse.size("13.65kB"), 13_650)
        XCTAssertEqual(DiskParse.size("0B"), 0)
        XCTAssertEqual(DiskParse.size("garbage"), 0)
        XCTAssertEqual(DiskParse.size("2.5MB (40%)"), 2_500_000)
    }

    func testVolumeKindPins() {
        let d = Disk()
        XCTAssertEqual(DiskParse.volumeKind("trmnl_pgdata", disk: d), .data)
        XCTAssertEqual(DiskParse.volumeKind("app_ch_data", disk: d), .data)
        XCTAssertEqual(DiskParse.volumeKind("app_minio_data", disk: d), .data)
        XCTAssertEqual(DiskParse.volumeKind("app_node_modules", disk: d), .rebuildable)
        XCTAssertEqual(DiskParse.volumeKind("app_bundle_web", disk: d), .rebuildable)
        XCTAssertEqual(DiskParse.volumeKind("fb7eb6f8e8ff35", disk: d), .unknown)
    }

    func testDuParsing() {
        let out = "511740\t/Users/me/x.worktrees/a/\n160364\t/Users/me/x.worktrees/b/\nbad line\n"
        XCTAssertEqual(DiskParse.duChildren(out), ["/Users/me/x.worktrees/a": 511740 * 1024, "/Users/me/x.worktrees/b": 160364 * 1024])
        XCTAssertEqual(DiskParse.duTotal(out), (511740 + 160364) * 1024)
        XCTAssertEqual(DiskParse.duTotal(""), 0)
    }

    func testDockerSummary() {
        let out = """
            {"Active":"3","Reclaimable":"1.452GB (60%)","Size":"2.4GB","TotalCount":"9","Type":"Images"}
            {"Active":"1","Reclaimable":"0B (0%)","Size":"12MB","TotalCount":"1","Type":"Containers"}
            not json
            """
        let rows = DiskParse.dockerSummary(out)
        XCTAssertEqual(rows["Images"], DockerSummaryRow(type: "Images", totalCount: 9, active: "3", reclaimableBytes: 1_452_000_000))
        XCTAssertEqual(rows["Containers"]?.reclaimableBytes, 0)
        XCTAssertEqual(rows.count, 2)
    }

    func testDockerVolumeTable() {
        let out = """
            Images space usage:
            REPOSITORY   TAG   IMAGE ID   CREATED   SIZE   SHARED SIZE   UNIQUE SIZE   CONTAINERS
            VOLUME NAME               LINKS   SIZE
            trmnl_pgdata              1       54.2GB
            app_node_modules          0       812MB
            fb7eb6f8e8ff35            0       120MB

            Build cache usage: 0B
            """
        XCTAssertEqual(DiskParse.dockerVolumes(out), [
            DockerVolume(name: "trmnl_pgdata", links: 1, bytes: 54_200_000_000),
            DockerVolume(name: "app_node_modules", links: 0, bytes: 812_000_000),
            DockerVolume(name: "fb7eb6f8e8ff35", links: 0, bytes: 120_000_000),
        ])
    }

    func testSimulatorUDIDs() {
        let json = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-5":[],"com.apple.CoreSimulator.SimRuntime.iOS-17-0":[{"udid":"AAAA-1","name":"iPhone 15"},{"name":"no udid"}]}}"#
        XCTAssertEqual(DiskParse.simulatorUDIDs(json), ["AAAA-1"])
        XCTAssertEqual(DiskParse.simulatorUDIDs("nope"), [])
    }

    func testMisePrunable() {
        let out = "ruby    3.2.2   ~/.local/share/mise/installs/ruby/3.2.2\nnode    18.20.0\n\nbad\n"
        XCTAssertEqual(DiskParse.misePrunable(out).map { "\($0.tool)/\($0.version)" }, ["ruby/3.2.2", "node/18.20.0"])
    }
}
