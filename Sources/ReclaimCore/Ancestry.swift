import Foundation

/// Our own pid, launchd, the kernel, and every ancestor up the tree: never candidates for a signal.
public enum Ancestry {
    public static func untouchable(from pid: Int32, in byPid: [Int32: ProcessRecord]) -> Set<Int32> {
        var result: Set<Int32> = [0, 1, pid]
        var cursor = pid
        while let p = byPid[cursor], p.ppid > 1, !result.contains(p.ppid) {
            result.insert(p.ppid)
            cursor = p.ppid
        }
        return result
    }
}
