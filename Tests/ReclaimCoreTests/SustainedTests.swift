import XCTest
@testable import ReclaimCore

final class SustainedTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_789_043_200)
    func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }
    func proc(_ pid: Int32, cpu: Double = 0, gb: Double = 0, command: String = "/Applications/Xcode.app/Contents/MacOS/Xcode -foo") -> ProcessRecord {
        ProcessRecord(pid: pid, ppid: 1, cpu: cpu, rssKB: Int(gb * 1_048_576), age: 100, user: "me", command: command)
    }
    func system(swap: Double? = 10, thermal: [String] = [], battery: (Int, String)? = nil) -> SystemState {
        SystemState(swapUsedMB: swap.map { $0 * 10 }, swapTotalMB: swap == nil ? nil : 1000, uptimeSeconds: 0,
                    batteryPercent: battery?.0, batteryState: battery?.1, thermal: thermal)
    }
    var alerts: Alerts { var a = Alerts(); a.cpu.minutes = 30; a.memory.minutes = 10; return a }

    func testProcessNameIsTheExecutable() {
        XCTAssertEqual(proc(1).name, "Xcode")
        XCTAssertEqual(proc(1, command: "puma 8.0.2 (tcp://localhost:3000)").name, "puma")
    }

    func testCPUFiresOnceAfterTheWindowAndRearmsWhenItClears() {
        var s = Sustained()
        XCTAssertEqual(s.observe(hot: [proc(9, cpu: 60)], system: system(), alerts: alerts, at: at(0)), [])
        XCTAssertEqual(s.observe(hot: [proc(9, cpu: 60)], system: system(), alerts: alerts, at: at(29)), [])
        let fired = s.observe(hot: [proc(9, cpu: 62)], system: system(), alerts: alerts, at: at(30))
        XCTAssertEqual(fired, [Alert(kind: .cpu, pid: 9, title: "CPU · Xcode", detail: "62% for 30m (pid 9)")])
        XCTAssertEqual(s.observe(hot: [proc(9, cpu: 60)], system: system(), alerts: alerts, at: at(31)), [])
        XCTAssertEqual(s.observe(hot: [], system: system(), alerts: alerts, at: at(32)), [])
        XCTAssertEqual(s.observe(hot: [proc(9, cpu: 60)], system: system(), alerts: alerts, at: at(33)), [])
        XCTAssertEqual(s.observe(hot: [proc(9, cpu: 60)], system: system(), alerts: alerts, at: at(63)).count, 1)
    }

    func testMemoryUsesItsOwnWindowAndFloor() {
        var s = Sustained()
        XCTAssertEqual(s.observe(hot: [proc(3, gb: 6.1)], system: system(), alerts: alerts, at: at(0)), [])
        XCTAssertEqual(s.observe(hot: [proc(3, gb: 6.1)], system: system(), alerts: alerts, at: at(10)),
                       [Alert(kind: .memory, pid: 3, title: "Memory · Xcode", detail: "6.1GB for 10m (pid 3)")])
        XCTAssertEqual(s.observe(hot: [proc(3, gb: 3.9)], system: system(), alerts: alerts, at: at(20)), [])
    }

    func testSwapAndThermalFireOnCrossingOnly() {
        var s = Sustained()
        XCTAssertEqual(s.observe(hot: [], system: system(swap: 91, thermal: ["CPU_Speed_Limit = 60"]), alerts: alerts, at: at(0)),
                       [Alert(kind: .swap, pid: nil, title: "Swap 91%", detail: "biggest residents are in the popover"),
                        Alert(kind: .thermal, pid: nil, title: "Thermal pressure", detail: "CPU_Speed_Limit = 60")])
        XCTAssertEqual(s.observe(hot: [], system: system(swap: 95, thermal: ["CPU_Speed_Limit = 50"]), alerts: alerts, at: at(1)), [])
        XCTAssertEqual(s.observe(hot: [], system: system(swap: 50), alerts: alerts, at: at(2)), [])
        XCTAssertEqual(s.observe(hot: [], system: system(swap: 85), alerts: alerts, at: at(3)).map(\.kind), [.swap])
    }

    func testThermalCanBeTurnedOff() {
        var s = Sustained(); var quiet = alerts; quiet.thermal = false
        XCTAssertEqual(s.observe(hot: [], system: system(thermal: ["hot"]), alerts: quiet, at: at(0)), [])
    }

    func testBatteryDrainRateOverFifteenMinutes() {
        var s = Sustained()
        for (minute, pct) in [(0, 81), (5, 79), (10, 77)] {
            XCTAssertEqual(s.observe(hot: [], system: system(battery: (pct, "discharging")), alerts: alerts, at: at(Double(minute))), [])
        }
        XCTAssertEqual(s.observe(hot: [], system: system(battery: (75, "discharging")), alerts: alerts, at: at(15)),
                       [Alert(kind: .battery, pid: nil, title: "Battery draining 24%/h", detail: "from 81% to 75% in 15m")])
        XCTAssertEqual(s.observe(hot: [], system: system(battery: (74, "discharging")), alerts: alerts, at: at(20)), [])
        XCTAssertEqual(s.observe(hot: [], system: system(battery: (74, "charging")), alerts: alerts, at: at(21)), [])
        XCTAssertEqual(s.observe(hot: [], system: system(battery: (65, "discharging")), alerts: alerts, at: at(22)), [])
        XCTAssertEqual(s.observe(hot: [], system: system(battery: (64, "discharging")), alerts: alerts, at: at(30)), [])
    }

    func testSlowDrainNeverFires() {
        var s = Sustained()
        for (minute, pct) in [(0, 80), (15, 78), (30, 76), (60, 72)] {
            XCTAssertEqual(s.observe(hot: [], system: system(battery: (pct, "discharging")), alerts: alerts, at: at(Double(minute))), [])
        }
    }
}
