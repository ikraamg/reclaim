#!/bin/sh
# Finding-set parity between reclaim.py and the Swift CLI. Both dry-run, both read the same machine.
# State files differ, so the quiet-run collapse is defeated by deleting both first.
set -eu
cd "$(dirname "$0")/.."
swift build -c release || exit 1
rm -f ~/.claude/reclaim-state.json "$HOME/Library/Application Support/Reclaim/state.json"

py_raw=$(/usr/bin/python3 ~/.claude/skills/reclaim/reclaim.py --dry-run) || { echo "parity: reclaim.py failed"; exit 1; }
swift_raw=$(.build/release/reclaim --dry-run --json) || { echo "parity: reclaim failed"; exit 1; }
case "$py_raw" in *swap*) ;; *) echo "parity: python output has no header"; exit 1;; esac
case "$swift_raw" in *'"header"'*) ;; *) echo "parity: swift output has no header"; exit 1;; esac

py=$(echo "$py_raw" | awk '/^(WOULD KILL|KILLED)/{v="KILL"} /^REPORTED/{v="REPORT"} /^    [0-9]+ /{print $1":"$2":"v}' | sort)
swift=$(echo "$swift_raw" \
  | /usr/bin/python3 -c 'import json,sys; [print("%d:%s:%s" % (f["pid"], f["category"], f["verdict"])) for f in json.load(sys.stdin)["findings"]]' \
  | sort)

if [ "$py" = "$swift" ]; then
  echo "parity: identical finding set, verdicts included ($(echo "$py" | grep -c . || true) findings)"
else
  echo "parity: MISMATCH"; echo "--- python"; echo "$py"; echo "--- swift"; echo "$swift"; exit 1
fi
