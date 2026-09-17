# reclaim

Finds and kills wasted local processes on a Mac, and reports what is eating disk and what starts at login.
Swift, no dependencies. Ships as a menu bar app and a CLI that share one core.

## What it does

- `reclaim` — processes. Two tiers. **KILL**: a rule matched, the process is past the rule's age floor, and
  the evidence holds (`orphaned`: parent is launchd; `portUnbound`: nobody in its family listens on the port
  it advertises). **REPORT**: a spin loop that is young or still parented, a rule match below its CPU floor,
  a port rule whose listener table could not be read, or a wedged system daemon that is not ours to kill.
  Other rules say nothing when their evidence is missing. A plain run only reports until you set
  `"autoKill": true` in the config or pass `--kill`. `--dry-run` never kills.
- `reclaim --disk` — docker, git worktrees, caches. Report only; every line carries the command that would
  reclaim it. ~35s.
- `reclaim --boot` — cpu hogs since boot, login items, launch agents outside your keep-list, orphaned system
  extensions, stopped postgres data dirs. Report only.
- `--json` on any of the above. `--self-check` proves eleven live process shapes are never killed and five
  dead ones are.

## Install

    scripts/install.sh      # builds release, copies to ~/.local/bin/reclaim, runs --self-check

## App

    scripts/build-app.sh    # xcodegen + xcodebuild; prints the bundle path, then `open` it

A status item: a hollow square when there is nothing to kill, a filled one with the count when there is. The
popover shows the same findings as the CLI; Kill asks twice. It runs the process pass every 30s (`pollSeconds`),
reloads `config.json` when it changes and keeps the last good one if the file breaks. Settings covers the
interval, `autoKill`, start at login, and installing `~/.local/bin/reclaim` as a shim that runs the app's
binary (`Reclaim --dry-run` and every other flag work on the bundle's executable directly).

Alerts (Settings > Alerts): a notification with a Kill button for each new row it would kill, one for each automatic
kill, and one when something has held too long: CPU over 50% for 30m, memory over 4GB for 10m, swap over 80%, thermal
pressure, battery draining over 20%/h. Each fires once and again only after it cleared. Thresholds live under
`"alerts"` in the config.

Sweep (popover footer, or "Sweep…" in the menu) opens a window that runs `--disk` and `--boot` and shows their
sections: each line's reclaim command with a Copy button, nothing that runs one. The first open runs both; Run again
replaces the result.

The app is ad-hoc signed for now, so a login item registered by one build may stop launching after the next
build until it is toggled again; a stable signing identity fixes that.

    Reclaim --render findings out.png [--dark]   # draw a fixture; fixtures: findings killed empty unchanged badConfig swap disk boot
    scripts/render-fixtures.sh [dir]             # all of them, light and dark

## Config

`~/Library/Application Support/Reclaim/config.json`. Missing keys take defaults; unknown keys survive a save.

    {
      "autoKill": false,
      "rules": [
        { "name": "dev-server", "match": "^puma\\s[\\d.]+\\s\\(tcp://[^:]+:(\\d+)\\)", "minAgeSeconds": 900, "evidence": "portUnbound" },
        { "name": "busy-loop", "match": "(?:zsh|bash|sh|dash)\\b.*-c\\b.*while\\s+(?::|true)\\s*;?\\s*do", "minAgeSeconds": 3600, "evidence": "orphaned", "minCPU": 20 }
      ],
      "neverKill": ["launchd", "kernel_task", "loginwindow", "WindowServer"],
      "boot": { "keep": ["homebrew.mxcl.", "com.ikraam."] },
      "disk": { "worktreeRoot": "~/Documents/GitHub", "worktreeStaleDays": 21 },
      "alerts": { "notify": true, "cpu": { "percent": 50, "minutes": 30 }, "memory": { "gigabytes": 4, "minutes": 10 }, "swapPercent": 80, "thermal": true, "batteryDrainPerHour": 20 }
    }

Rules are first-match. A rule with `minCPU` never kills below it. A bad regex is reported on stderr and skipped.

## Safety

PPID 1 is not an orphan signal on macOS — launchd adopts everything — so it is only ever a necessary
condition; age plus evidence does the work. The CLI refuses unknown flags, refuses to kill as root, and
never signals pid <= 1. Sweeps only read (du, docker system df, git status); they never run a reclaim command.

## For agents

`reclaim --dry-run --json` is the safe first call. The JSON schemas, what KILL and REPORT mean, the config as the
API, and how to run it on a loop are in [docs/agents.md](docs/agents.md).
