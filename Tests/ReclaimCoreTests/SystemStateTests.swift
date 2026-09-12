import XCTest
@testable import ReclaimCore

final class SystemStateTests: XCTestCase {
    func testParseThermalDropsTheNoLines() {
        let quiet = """
            Note: No thermal warning level has been recorded
            Note: No performance warning level has been recorded
            Note: No CPU power status has been recorded
            """
        XCTAssertEqual(SystemState.parseThermal(quiet), [])
        let hot = quiet + "\nCPU_Speed_Limit \t= 60\nCPU_Available_CPUs \t= 8\n"
        XCTAssertEqual(SystemState.parseThermal(hot), ["CPU_Speed_Limit \t= 60", "CPU_Available_CPUs \t= 8"])
    }

    func testHeaderFormatsEveryPart() {
        let s = SystemState(swapUsedMB: 6246, swapTotalMB: 8192, uptimeSeconds: 3 * 86400 + 4 * 3600,
                            batteryPercent: 81, batteryState: "discharging", thermal: ["CPU_Speed_Limit = 60"])
        XCTAssertEqual(s.header(), "swap 6.1/8.0GB (76%)  ·  up 3d 4h  ·  battery 81% discharging  THERMAL: CPU_Speed_Limit = 60")
    }

    func testHeaderWithoutSwapOrBattery() {
        let s = SystemState(swapUsedMB: nil, swapTotalMB: nil, uptimeSeconds: 600,
                            batteryPercent: nil, batteryState: nil, thermal: [])
        XCTAssertEqual(s.header(), "swap n/a  ·  up 10m")
    }

    func testLiveReadIsSane() {
        let s = SystemState.read()
        XCTAssertGreaterThan(s.uptimeSeconds, 0)
        if let pct = s.batteryPercent { XCTAssertTrue((0...100).contains(pct)) }
        if let total = s.swapTotalMB { XCTAssertGreaterThanOrEqual(total, s.swapUsedMB ?? 0) }
    }
}
