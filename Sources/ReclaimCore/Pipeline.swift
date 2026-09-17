import Foundation

public enum PipelineError: Error, Equatable {
    case unknownUser
    case rootWithoutDryRun
}

/// One process pass: gather, classify, evaluate, terminate. The CLI and the app both run this.
/// The returned report carries the next RunState; saving it is the caller's decision.
public enum Pipeline {
    public static func run(config: Config, dryRun: Bool, previous: RunState, on machine: Machine = .live) -> Result<RunReport, PipelineError> {
        let processes = machine.processes()
        let byPid = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        guard let me = machine.user(), !me.isEmpty else { return .failure(.unknownUser) }
        if machine.isRoot && !dryRun { return .failure(.rootWithoutDryRun) }

        // Never touch ourselves or anything above us in the tree.
        var untouchable = Ancestry.untouchable(from: machine.selfPid, in: byPid)
        untouchable.insert(machine.parentPid)  // belt and braces: covers our own pid being absent from the snapshot

        let classifier = Classifier(config: config)
        let candidates = classifier.portCandidates(in: processes)
        let cwds = Dictionary(candidates.compactMap { p in machine.cwd(p.pid).map { (p.pid, $0) } }, uniquingKeysWith: { a, _ in a })
        let context = Context(processes: processes, me: me, untouchable: untouchable,
                              listeners: candidates.isEmpty ? [:] : machine.listeners(),
                              cwds: cwds, worktreeNote: machine.worktreeNote)

        let findings = processes.compactMap { classifier.classify($0, in: context) }
        let system = machine.system()
        let swapHot = (system.swapPercent ?? 0) >= 80
        let evaluation = Session.evaluate(findings, previous: previous, swapHot: swapHot, willKill: !dryRun)

        var actions: [Int32: String] = [:]
        if !dryRun && !evaluation.unchanged {
            for f in evaluation.findings where f.verdict == .kill {
                actions[f.process.pid] = machine.terminate(f.process)
            }
        }
        let hogs = swapHot ? Array(processes.sorted { $0.rssKB > $1.rssKB }.prefix(5)) : []
        return .success(RunReport(header: system.header(), evaluation: evaluation, dryRun: dryRun, actions: actions,
                                  memoryHogs: hogs, processCount: processes.count, invalidRules: classifier.invalidRules))
    }
}
