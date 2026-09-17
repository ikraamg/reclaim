# Reclaim for agents

Reclaim finds wasted local processes and reports what eats disk and what starts at login. This
doc is the reference for an agent driving it from a shell.

## First call

    reclaim --dry-run --json

Read-only, never kills, machine-readable. Start here every time.

## Flags and exit codes

| Flag | Does |
|---|---|
| `--dry-run` | Report only, never kills. Wins over `--kill` and `autoKill`. |
| `--json` | Machine-readable output, on any mode below. |
| `--self-check` | Asserts eleven live process shapes are never killed and five dead ones are. |
| `--disk` | Docker, git worktrees, caches. Report only, ~40s. |
| `--boot` | CPU hogs, login items, launch agents, orphaned extensions, stopped postgres dirs. Report only. |
| `--kill` | Processes: kill the dead tier this run. |

Any other argument: stderr `reclaim: unknown flag <x> - refusing to run`, exit 2. No positional
arguments exist. Exit codes: `0` ok, `1` self-check failed, `2` refused (unknown flag, config
present but unreadable, root without `--dry-run`, `--disk` with `--boot`).

## What KILL and REPORT mean

**KILL**: a rule matched the command, the process is older than the rule's `minAgeSeconds`, and
the rule's evidence holds — `orphaned` (parent is launchd, so the shell that started it is gone)
or `portUnbound` (nobody in the process's family listens on the port its command line
advertises). A rule with `minCPU` never kills below it.

**REPORT**: ambiguous — a spin loop that is young or still parented, a rule match below its CPU
floor, a port rule whose listener table could not be read, or a wedged system daemon (>= 40% CPU
for an hour by default) that is not ours to kill. REPORT rows are never killed by `--kill` or
`autoKill`.

A plain `reclaim` only reports unless config `autoKill: true` or `--kill` is passed; `--dry-run`
always wins over both. A kill is SIGTERM, then SIGKILL after 2s; before signaling, the live
`ps -o command=` of the pid must still match the snapshot, else the kill is refused. Never pid
<= 1. Refuses to kill as root.

## The process JSON

`reclaim --dry-run --json` — every key is always present, nulls are written, never omitted:

```json
{
  "header": "swap 2.1/4.0GB (52%)  ·  up 3d 4h  ·  battery 81% discharging",
  "dryRun": true, "unchanged": false, "quietRuns": 0, "swapJustHot": false,
  "findings": [
    { "pid": 48213, "ppid": 1, "category": "dev-server", "verdict": "KILL",
      "reason": "nothing is listening on port 3000",
      "cpu": 0.0, "rssMB": 412, "ageSeconds": 15000, "age": "4h 10m",
      "band": "waking the CPU / idle weight", "user": "me",
      "command": "puma 8.0.2 (tcp://localhost:3000) [core]",
      "action": null }
  ],
  "memoryHogs": [ { "pid": 3301, "rssMB": 6100, "command": "/Applications/Xcode.app/Contents/MacOS/Xcode" } ],
  "hint": null
}
```

- `unchanged`: identical findings to the previous run. `quietRuns`: consecutive unchanged runs.
  `swapJustHot`: swap crossed 80% this run — `memoryHogs` is filled only then.
- `verdict` is `"KILL"` or `"REPORT"`. `category` is the rule's `name` or `wedged`. `band` is
  `"burning CPU"` (cpu >= 20), `"holding memory"` (rss >= 200MB), or `"waking the CPU / idle
  weight"`.
- `action` is null when nothing was done; otherwise `"terminated"`, `"killed (-9, ignored
  TERM)"`, or `"refused: ..."` (e.g. the command changed under the pid).
- `hint` is null or `"reporting only - set \"autoKill\": true in config or pass --kill"` — set
  when a plain run found KILL rows but did not kill them. Nothing found: `"findings": []`,
  `"unchanged": true`.
- Every CLI run, including `--dry-run`, writes `~/Library/Application Support/Reclaim/state.json`,
  which `unchanged`/`quietRuns` compare against — an agent's dry run resets the human's "unchanged
  for N runs" counter, harmless but worth knowing.

## The sweeps JSON

`reclaim --disk --json` (~40s) or `reclaim --boot --json` (seconds):

```json
{
  "kind": "disk",
  "header": ["disk: 503GB used, 387GB free (57% full)  ·  nothing below is deleted automatically"],
  "sections": [
    { "title": "docker", "bytes": 18512990000,
      "lines": [
        { "bytes": 9355000000, "label": "images", "detail": "9 total, 0 active",
          "command": "docker image prune -a", "nested": false },
        { "bytes": null, "label": "", "detail": "check each one first - a worktree is unpushed work until proven otherwise",
          "command": null, "nested": false }
      ] }
  ],
  "footer": ["total reclaimable: 26.90GB"]
}
```

- `kind` is `"disk"` or `"boot"`. `bytes` on a section is what its commands could reclaim; null
  for boot sections. `label == ""` marks a note row — read `detail`, nothing to act on. `command`
  is null when nothing should be run (data volumes, cpu hogs, login items, notes). `nested: true`
  means the line belongs under the previous top-level line (a stale worktree under its repo).
- Disk sections: `docker`, `git worktrees`, `caches`. Boot sections: cpu hogs, login items,
  launch agents/daemons outside `boot.keep`, orphaned system extensions, homebrew data dirs of
  stopped postgres versions.
- Sweeps only read (`du`, `docker system df`, `git status`, `osascript`, `plutil`) and never run
  a command. **An agent must not run a `command` either**: processes come back with one command,
  deleted bytes do not. Show the command to the human and let them run it.

## The config is the API

`~/Library/Application Support/Reclaim/config.json`. Missing file or missing keys: defaults.
Unknown keys survive a save. Empty or mistyped file: the CLI refuses with exit 2 (`config
unreadable, refusing to guess`); the app keeps its last good config.

Top-level keys: `pollSeconds` (app only), `autoKill`, `rules`, `wedged {percent,
minAgeSeconds}`, `neverKill`, `respawnsClean`, `busyByDesign`, `boot {keep, cpuHog{percent,
minAgeSeconds}}`, `disk {worktreeRoot, worktreeStaleDays, regenerableInRepo, volumeIsData,
volumeIsRebuildable, caches[{path, command, note}]}`, `alerts {notify, cpu{percent,minutes},
memory{gigabytes,minutes}, swapPercent, thermal, batteryDrainPerHour}`.

A rule: `{ "name": "vite", "match": "vite --port (\\d+)", "minAgeSeconds": 600, "evidence":
"portUnbound" }`. `evidence` is `orphaned` or `portUnbound`; `minCPU` is optional. Rules are
first-match in order. A bad regex is reported on stderr (`reclaim: ignoring rule "x" - invalid
regex`) and skipped.

Safe edit pattern:

    jq '.rules += [ ... ]' config.json > tmp && mv tmp config.json
    reclaim --dry-run --json

The dry run proves the file still parses; the app picks the change up on its own.
`respawnsClean` defaults: `duetexpertd`, `System Events`, `mdworker`, `mds_stores`, `sharingd` —
daemons that come back clean if killed; an agent may offer `killall <name>` for a REPORT row
naming one. `neverKill` defaults: `launchd`, `kernel_task`, `loginwindow`, `WindowServer`.

## Running it on a loop

Under a `/loop`, run plain `reclaim` and say nothing beyond its output — identical runs collapse
to one `unchanged` line. Do not run `--disk` on a loop interval. Interactively, after a while
away: `--dry-run` first, show the human, then `--kill` if they agree. Never offer to kill
`WindowServer` or `loginwindow`. Login items, SMAppService and the app's Settings need the GUI;
root steps from a tool sandbox need `SUDO_ASKPASS`.

## Guarantees

`reclaim --self-check` asserts eleven live process shapes are never killed and five dead ones
are (exit 1 if not). PPID 1 alone is never a kill signal on macOS — launchd adopts everything —
age plus evidence does the work.
