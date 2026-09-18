import XCTest
@testable import ReclaimCore

final class BootParseTests: XCTestCase {
    func rec(_ pid: Int32, cpu: Double, age: Int, _ cmd: String) -> ProcessRecord {
        ProcessRecord(pid: pid, ppid: 1, cpu: cpu, rssKB: 0, age: age, user: "me", command: cmd)
    }

    func testCpuHogsFilterAndHints() {
        let procs = [rec(1, cpu: 90, age: 4000, "/System/Library/Frameworks/CoreServices.framework/Frameworks/Metadata.framework/Versions/A/Support/mds_stores"),
                     rec(2, cpu: 60, age: 4000, "/Library/Application Support/Nord/Shield --filter"),
                     rec(3, cpu: 60, age: 100, "/usr/bin/young"),
                     rec(4, cpu: 10, age: 9000, "/usr/bin/idle"),
                     rec(5, cpu: 55, age: 4000, "/usr/bin/other")]
        let hogs = BootParse.cpuHogs(procs, boot: Boot())
        XCTAssertEqual(hogs.map { $0.0.pid }, [1, 2, 5])   // sorted by cpu desc, young and idle excluded
        XCTAssertTrue(hogs[0].hint.contains("Spotlight"))
        XCTAssertTrue(hogs[1].hint.contains("NordVPN"))
        XCTAssertEqual(hogs[2].hint, "")
    }

    func testLaunchItemsSkipAppleAndKeepList() {
        let items = BootParse.launchItems(folder: "/Users/me/Library/LaunchAgents",
                                          names: ["com.apple.foo.plist", "homebrew.mxcl.redis.plist", "com.evil.plist", "notes.txt", "com.docker.vmnetd.plist"],
                                          keep: Boot().keep)
        XCTAssertEqual(items.map(\.path), ["/Users/me/Library/LaunchAgents/com.evil.plist"])
        XCTAssertEqual(items[0].unloadCommand, "launchctl bootout gui/$(id -u) '/Users/me/Library/LaunchAgents/com.evil.plist'")
        let daemon = BootParse.launchItems(folder: "/Library/LaunchDaemons", names: ["com.evil.plist"], keep: [])
        XCTAssertEqual(daemon[0].unloadCommand, "sudo launchctl bootout system '/Library/LaunchDaemons/com.evil.plist'")
    }

    func testOrphanedExtensionsFromPlutil() {
        let plutil = """
              "originPath" => "/Applications/TotalAV.app/Contents/Library/SystemExtensions/net.totalav.systemextension"
              "state" => "activated_disabled"
              "originPath" => "/Applications/Gone.app/Contents/Library/SystemExtensions/com.gone.ext.systemextension"
              "state" => "activated_enabled"
              "originPath" => "/Applications/AlsoGone.app/Contents/Library/SystemExtensions/x.systemextension"
              "state" => "terminated_waiting_to_uninstall_on_reboot"
            """
        let orphans = BootParse.orphanedExtensions(plutil) { $0 == "/Applications/TotalAV.app" }
        XCTAssertEqual(orphans, [OrphanedExtension(state: "activated_enabled", originApp: "/Applications/Gone.app")])
    }

    func testStartedServices() {
        let out = "Name          Status  User   File\natuin         none\npostgresql@16 started me ~/Library/LaunchAgents/homebrew.mxcl.postgresql@16.plist\nredis         error  256 me x\n"
        XCTAssertEqual(BootParse.startedServices(out), ["postgresql@16"])
    }
}
