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

# Sweeps: compare the set of reclaim commands each side emits. Text differs by design.
for mode in disk boot; do
  py_raw=$(/usr/bin/python3 ~/.claude/skills/reclaim/reclaim.py "--$mode" 2>/dev/null) \
    || { echo "parity ($mode): reclaim.py failed"; exit 1; }
  swift_raw=$(.build/release/reclaim "--$mode" --json 2>/dev/null) \
    || { echo "parity ($mode): reclaim failed"; exit 1; }
  case "$swift_raw" in *'"sections"'*) ;; *) echo "parity ($mode): swift output has no sections"; exit 1;; esac
  case "$mode" in
    disk) py_marker="total reclaimable" ;;
    boot) py_marker="nothing below is changed automatically" ;;
  esac
  case "$py_raw" in *"$py_marker"*) ;; *) echo "parity ($mode): python output has no footer"; exit 1;; esac

  py_cmds=$(printf '%s\n' "$py_raw" \
    | grep -oE '(rm -rf [^ ]+|docker (image|container|builder) prune[^ ]*|docker volume rm|mise prune|xcrun simctl delete unavailable|npm cache clean --force|uv cache clean|yarn cache clean|brew cleanup -s|pnpm store prune|pip cache purge|go clean -cache|launchctl bootout [^ ]+ [^ ]+|sudo launchctl bootout [^ ]+ [^ ]+)' \
    | sed -E "s#'##g" | sort -u)
  swift_cmds=$(printf '%s\n' "$swift_raw" \
    | /usr/bin/python3 -c 'import json,sys
for s in json.load(sys.stdin)["sections"]:
    for l in s["lines"]:
        if l["command"]: print(l["command"])' \
    | grep -oE '(rm -rf [^ ]+|docker (image|container|builder) prune[^ ]*|docker volume rm|mise prune|xcrun simctl delete unavailable|npm cache clean --force|uv cache clean|yarn cache clean|brew cleanup -s|pnpm store prune|pip cache purge|go clean -cache|launchctl bootout [^ ]+ [^ ]+|sudo launchctl bootout [^ ]+ [^ ]+)' \
    | sed -E "s#'##g" | sort -u)
  if [ "$py_cmds" = "$swift_cmds" ]; then
    echo "parity ($mode): identical command set ($(printf '%s\n' "$py_cmds" | grep -c . || true) commands)"
  else
    echo "parity ($mode): MISMATCH"; echo "--- python"; echo "$py_cmds"; echo "--- swift"; echo "$swift_cmds"; exit 1
  fi
done
