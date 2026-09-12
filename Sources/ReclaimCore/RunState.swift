import Foundation

public struct RunState: Codable, Equatable {
    public var quietRuns = 0
    public var signature: String? = nil
    public var hot: [Int32] = []
    public var swapHot = false

    public init() {}

    public static let defaultURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Reclaim/state.json")

    public static func load(from url: URL = defaultURL) -> RunState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(RunState.self, from: data) else { return RunState() }
        return state
    }

    public func save(to url: URL = defaultURL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}

public struct Evaluation: Equatable {
    public var findings: [Finding]
    public var unchanged: Bool
    public var swapJustHot: Bool
    public var state: RunState
}

public enum Session {
    public static func signature(of findings: [Finding]) -> String {
        findings.map { "\($0.process.pid):\($0.category):\($0.verdict.rawValue)" }.sorted().joined(separator: ",")
    }

    /// A wedged daemon is shown only on its second consecutive sighting; an identical
    /// finding set collapses into a quiet-run counter; killing always resets the counter.
    public static func evaluate(_ findings: [Finding], previous: RunState, swapHot: Bool, willKill: Bool) -> Evaluation {
        var state = previous
        state.swapHot = swapHot
        let wasHot = Set(previous.hot)
        state.hot = findings.filter { $0.category == "wedged" }.map(\.process.pid)
        let shown = findings.filter { $0.category != "wedged" || wasHot.contains($0.process.pid) }
        let sig = signature(of: shown)
        let killing = willKill && shown.contains { $0.verdict == .kill }
        let unchanged = !killing && sig == previous.signature
        state.quietRuns = unchanged ? previous.quietRuns + 1 : 0
        state.signature = sig
        return Evaluation(findings: shown, unchanged: unchanged,
                          swapJustHot: swapHot && !previous.swapHot, state: state)
    }
}
