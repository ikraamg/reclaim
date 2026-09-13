import Foundation
import IOKit.ps

public struct SystemState: Equatable, Sendable {
    public var swapUsedMB: Double?
    public var swapTotalMB: Double?
    public var uptimeSeconds: Int
    public var batteryPercent: Int?
    public var batteryState: String?
    public var thermal: [String]

    public init(swapUsedMB: Double?, swapTotalMB: Double?, uptimeSeconds: Int,
                batteryPercent: Int?, batteryState: String?, thermal: [String]) {
        self.swapUsedMB = swapUsedMB; self.swapTotalMB = swapTotalMB; self.uptimeSeconds = uptimeSeconds
        self.batteryPercent = batteryPercent; self.batteryState = batteryState; self.thermal = thermal
    }

    public var swapPercent: Double? {
        guard let used = swapUsedMB, let total = swapTotalMB, total > 0 else { return nil }
        return 100 * used / total
    }

    public static func read() -> SystemState {
        let swap = readSwap()
        let battery = readBattery()
        return SystemState(swapUsedMB: swap?.used, swapTotalMB: swap?.total, uptimeSeconds: readUptime(),
                           batteryPercent: battery?.percent, batteryState: battery?.state,
                           thermal: parseThermal(shell(["/usr/bin/pmset", "-g", "therm"]) ?? ""))
    }

    /// pmset prints three "No ... has been recorded" notes when idle; anything else is pressure.
    public static func parseThermal(_ pmsetOutput: String) -> [String] {
        pmsetOutput.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains("No thermal") && !$0.contains("No performance")
                      && !$0.contains("No CPU power") }
    }

    public func header() -> String {
        var parts: [String] = []
        if let pct = swapPercent, let used = swapUsedMB, let total = swapTotalMB {
            parts.append(String(format: "swap %.1f/%.1fGB (%.0f%%)", used / 1024, total / 1024, pct))
        } else {
            parts.append("swap n/a")
        }
        parts.append("up " + human(age: uptimeSeconds))
        if let pct = batteryPercent, let state = batteryState {
            var battery = "battery \(pct)% \(state)"
            if !thermal.isEmpty { battery += "  THERMAL: " + thermal.joined(separator: "; ") }
            parts.append(battery)
        } else if !thermal.isEmpty {
            parts.append("THERMAL: " + thermal.joined(separator: "; "))
        }
        return parts.joined(separator: "  ·  ")
    }

    static func readSwap() -> (used: Double, total: Double)? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0, usage.xsu_total > 0 else { return nil }
        return (Double(usage.xsu_used) / 1_048_576, Double(usage.xsu_total) / 1_048_576)
    }

    static func readUptime() -> Int {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0 else { return 0 }
        return Int(Date().timeIntervalSince1970) - Int(boot.tv_sec)
    }

    static func readBattery() -> (percent: Int, state: String)? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let percent = d[kIOPSCurrentCapacityKey] as? Int,
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            let charged = d[kIOPSIsChargedKey] as? Bool ?? false
            let onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let state = charged ? "charged" : charging ? "charging" : onAC ? "AC attached" : "discharging"
            return (percent, state)
        }
        return nil
    }
}
