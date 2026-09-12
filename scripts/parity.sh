#!/bin/sh
# Finding-set parity between reclaim.py and the Swift CLI. Both dry-run, both read the same machine.
# State files differ, so the quiet-run collapse is defeated by deleting both first.
set -eu
cd "$(dirname "$0")/.."
rm -f ~/.claude/reclaim-state.json ~/Library/Application\ Support/Reclaim/state.json
swift build -c release 2>/dev/null

py=$(/usr/bin/python3 ~/.claude/skills/reclaim/reclaim.py --dry-run \
  | awk '/^    [0-9]+ /{print $1":"$2}' | sort)
swift=$(.build/release/reclaim --dry-run --json \
  | /usr/bin/python3 -c 'import json,sys; [print("%d:%s" % (f["pid"], f["category"])) for f in json.load(sys.stdin)["findings"]]' \
  | sort)

if [ "$py" = "$swift" ]; then
  echo "parity: identical finding set ($(echo "$py" | grep -c . || true) findings)"
else
  echo "parity: MISMATCH"; echo "--- python"; echo "$py"; echo "--- swift"; echo "$swift"; exit 1
fi
