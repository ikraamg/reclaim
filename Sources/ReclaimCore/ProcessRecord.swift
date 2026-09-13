import Foundation

public struct ProcessRecord: Equatable {
    public var pid: Int32
    public var ppid: Int32
    public var cpu: Double
    public var rssKB: Int
    public var age: Int
    public var user: String
    public var command: String

    public init(pid: Int32, ppid: Int32, cpu: Double, rssKB: Int, age: Int, user: String, command: String) {
        self.pid = pid; self.ppid = ppid; self.cpu = cpu; self.rssKB = rssKB
        self.age = age; self.user = user; self.command = command
    }
}

public enum ProcessSnapshot {
    static let psColumns = ["pid=", "ppid=", "%cpu=", "rss=", "etime=", "user=", "command="]

    /// ps etime: [[dd-]hh:]mm:ss
    public static func parseElapsed(_ raw: String) -> Int? {
        var rest = raw
        var days = 0
        if let dash = rest.firstIndex(of: "-") {
            guard let d = Int(rest[..<dash]) else { return nil }
            days = d
            rest = String(rest[rest.index(after: dash)...])
        }
        let parts = rest.split(separator: ":").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        var bits = parts.map { $0! }
        while bits.count < 3 { bits.insert(0, at: 0) }
        return days * 86400 + bits[0] * 3600 + bits[1] * 60 + bits[2]
    }

    public static func parse(_ psOutput: String) -> [ProcessRecord] {
        psOutput.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 6, omittingEmptySubsequences: true)
            guard parts.count == 7,
                  let pid = Int32(parts[0]), let ppid = Int32(parts[1]),
                  let cpu = Double(parts[2]), let rss = Int(parts[3]),
                  let age = parseElapsed(String(parts[4])) else { return nil }
            return ProcessRecord(pid: pid, ppid: ppid, cpu: cpu, rssKB: rss, age: age,
                                 user: String(parts[5]),
                                 command: parts[6].trimmingCharacters(in: .whitespaces))
        }
    }

    public static func live() -> [ProcessRecord] {
        parse(shell(["/bin/ps", "-Ao", psColumns.joined(separator: ",")]))
    }
}
