#!/usr/bin/env bash
# One pass: find panes that run a TCP server, count them per workspace,
# and report the counts as colored-dot workspace tokens.
#   green  $srv_up    a process in the pane is listening on a TCP port
#   yellow $srv_wait  pane served before; a command runs but no port (restarting)
#   red    $srv_down  pane served before; back at the shell prompt (stopped/crashed)
set -euo pipefail

HERDR="${HERDR_BIN_PATH:-herdr}"
STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/herdr-cowbell}"
SEEN="$STATE_DIR/seen"          # pane ids that have ever listened
TTL_MS="${COWBELL_TTL_MS:-15000}"
DRY_RUN="${DRY_RUN:-0}"
mkdir -p "$STATE_DIR"; touch "$SEEN"

listeners=" $(lsof -nP -iTCP -sTCP:LISTEN -Fp 2>/dev/null | sed -n 's/^p//p' | sort -u | tr '\n' ' ') "
ps_tree=$(ps -axo pid=,ppid=)

# Print root pid and every descendant pid.
descendants() {
  echo "$ps_tree" | awk -v root="$1" '
    { pid[NR]=$1; ppid[NR]=$2 }
    END { s[root]=1; grew=1
          while (grew) { grew=0
            for (i=1;i<=NR;i++) if ((ppid[i] in s) && !(pid[i] in s)) { s[pid[i]]=1; grew=1 } }
          for (k in s) print k }'
}

panes=$("$HERDR" pane list | jq -r '.result.panes[] | select(.agent == null) | "\(.workspace_id) \(.pane_id)"')
workspaces=$("$HERDR" workspace list | jq -r '.result.workspaces[].workspace_id')

new_seen=""; report=""   # report lines: "<workspace_id> up|wait|down"
while read -r ws pane; do
  [ -n "$pane" ] || continue
  info=$("$HERDR" pane process-info --pane "$pane" 2>/dev/null) || continue
  shell=$(echo "$info" | jq -r '.result.process_info.shell_pid // empty')
  fg=$(echo "$info" | jq -r '.result.process_info.foreground_process_group_id // empty')
  [ -n "$shell" ] || continue

  status=""
  for pid in $(descendants "$shell"); do
    case "$listeners" in *" $pid "*) status=up; break;; esac
  done
  if [ -z "$status" ] && grep -qx "$pane" "$SEEN"; then
    if [ -n "$fg" ] && [ "$fg" != "$shell" ]; then status=wait; else status=down; fi
  fi
  [ -n "$status" ] || continue
  new_seen="$new_seen$pane"$'\n'
  report="$report$ws $status"$'\n'
done <<< "$panes"
printf '%s' "$new_seen" > "$SEEN"   # closed panes drop out here

dots() { [ "$1" -gt 0 ] && printf '●%.0s' $(seq 1 "$1"); }

for ws in $workspaces; do
  args=()
  for kind in up wait down; do
    n=$(printf '%s' "$report" | grep -c "^$ws $kind$" || true)
    if [ "$n" -gt 0 ]; then args+=(--token "srv_$kind=$(dots "$n")"); else args+=(--clear-token "srv_$kind"); fi
  done
  if [ "$DRY_RUN" = 1 ]; then echo "$ws ${args[*]}"; continue; fi
  "$HERDR" workspace report-metadata "$ws" --source cowbell --ttl-ms "$TTL_MS" "${args[@]}" >/dev/null
done
