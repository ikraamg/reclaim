import XCTest
@testable import ReclaimCore

final class BootSweepTests: XCTestCase {
    func fakeShell(_ table: [String: String?]) -> ShellRunner {
        // Not `table.first(where:)?.value ?? ""` - optional chaining flattens a matched nil value
        // to "", which would defeat the "shell returned nil" fixture below.
        { args, _ in
            guard let match = table.first(where: { args.joined(separator: " ").hasPrefix($0.key) }) else { return "" }
            return match.value
        }
    }

    func testAllFiveSectionsFromFixtures() {
        let hog = ProcessRecord(pid: 612, ppid: 1, cpu: 90, rssKB: 0, age: 4000, user: "root",
                                command: "/System/Library/Frameworks/CoreServices.framework/Versions/A/Support/mds_stores")
        let shell = fakeShell([
            "/usr/bin/osascript": "Gifox, Battery Monitor\n",
            "/usr/bin/plutil": "  \"originPath\" => \"/Applications/Gone.app/Contents/Library/SystemExtensions/x.systemextension\"\n  \"state\" => \"activated_enabled\"\n",
            "brew services list": "Name Status User File\npostgresql@16 started me x\n",
            "/usr/bin/du -sxk /opt/homebrew/var/postgresql@14": "200000\tx\n",
        ])
        let fs = FileSystem(contents: { path in
                                switch path {
                                case "/Users/me/Library/LaunchAgents": return ["com.evil.plist", "com.grammarly.x.plist"]
                                case "/opt/homebrew/var": return ["postgresql@14", "postgresql@16"]
                                default: return nil
                                }
                            },
                            exists: { $0 == "/Applications/Present.app" }, isDirectory: { _ in true }, home: "/Users/me")
        let sweep = BootSweep.run(boot: Boot(), header: "swap n/a", processes: [hog], shell: shell, fs: fs)
        XCTAssertEqual(sweep.sections.map(\.title).count, 5)
        XCTAssertEqual(sweep.sections[0].lines, [
            SweepLine(label: "mds_stores", detail: "90% CPU for 1h 6m (pid 612)"),
            SweepLine(label: "", detail: "Spotlight indexing - exclude repo dirs: System Settings > Spotlight > Search Privacy", nested: true)])
        XCTAssertEqual(sweep.sections[1].lines.map(\.label), ["Gifox", "Battery Monitor"])
        XCTAssertEqual(sweep.sections[2].lines, [SweepLine(label: "~/Library/LaunchAgents/com.evil.plist",
                                                           command: "launchctl bootout gui/$(id -u) '/Users/me/Library/LaunchAgents/com.evil.plist'")])
        XCTAssertEqual(sweep.sections[3].lines[0], SweepLine(label: "activated_enabled", detail: "app gone: /Applications/Gone.app"))
        XCTAssertEqual(sweep.sections[4].lines, [SweepLine(bytes: 200000 * 1024, label: "/opt/homebrew/var/postgresql@14",
                                                           detail: "data dir of a version that is not running", command: "rm -rf /opt/homebrew/var/postgresql@14")])
    }

    func testLoginItemsUnavailableIsANote() {
        let shell = fakeShell(["/usr/bin/osascript": nil])
        let fs = FileSystem(contents: { _ in nil }, exists: { _ in false }, isDirectory: { _ in false }, home: "/Users/me")
        let sweep = BootSweep.run(boot: Boot(), header: "", processes: [], shell: shell, fs: fs)
        XCTAssertEqual(sweep.sections[1].lines, [SweepLine(label: "", detail: "could not read login items - System Events did not answer (Automation permission?)")])
    }
}
