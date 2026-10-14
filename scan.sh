#!/usr/bin/env bash
# One pass: find panes that run a TCP server, count them per workspace,
# and report the counts as colored-dot workspace tokens.
#   green  $srv_up    a process in the pane is listening on a TCP port, or the
#                     pane runs a process manager (overmind, foreman, ...) whose
#                     detached servers listen from inside the pane's directory
#   yellow $srv_wait  pane served before; a command runs but no port (restarting)
#   hollow $srv_down  pane served before; back at the shell prompt (stopped/crashed)
set -euo pipefail

HERDR="${HERDR_BIN_PATH:-herdr}"
STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/herdr-cowbell}"
SEEN="$STATE_DIR/seen"          # pane ids that have ever listened
TTL_MS="${COWBELL_TTL_MS:-15000}"
DRY_RUN="${DRY_RUN:-0}"
LAUNCHERS=" ${COWBELL_LAUNCHERS:-overmind foreman hivemind honcho} "
DOT="${COWBELL_DOT:-●}"            # running / restarting
DOT_DOWN="${COWBELL_DOT_DOWN:-○}"  # served before, now stopped
mkdir -p "$STATE_DIR"; touch "$SEEN"

listener_pids=$(lsof -nP -iTCP -sTCP:LISTEN -Fp 2>/dev/null | sed -n 's/^p//p' | sort -u)
listeners=" $(echo $listener_pids) "
# "<pid> <cwd>" for every listener, used to match servers that run outside
# the pane's process tree (overmind runs them under a detached tmux server).
listener_cwds=""
if [ -n "$listener_pids" ]; then
  listener_cwds=$(lsof -a -p "$(echo $listener_pids | tr ' ' ',')" -d cwd -Fpn 2>/dev/null |
    awk '/^p/ { pid = substr($0, 2) } /^n/ { print pid, substr($0, 2) }')
fi
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

# Pass 1: per pane, check its own process tree and note any launcher cwd.
# rows: "<ws> <pane> <shell> <fg> <up|-> <launcher cwd or empty>"
rows=""; claimed=" "
while read -r ws pane; do
  [ -n "$pane" ] || continue
  info=$("$HERDR" pane process-info --pane "$pane" 2>/dev/null) || continue
  shell=$(echo "$info" | jq -r '.result.process_info.shell_pid // empty')
  fg=$(echo "$info" | jq -r '.result.process_info.foreground_process_group_id // empty')
  [ -n "$shell" ] || continue

  tree=-
  for pid in $(descendants "$shell"); do
    case "$listeners" in *" $pid "*) tree=up; claimed="$claimed$pid ";; esac
  done
  launcher_cwd=$(echo "$info" | jq -r --arg l "$LAUNCHERS" '
    [.result.process_info.foreground_processes[]?
      | select(.cwd and (.name as $n | $l | contains(" " + $n + " ")))][0].cwd // empty')
  rows="$rows$ws $pane $shell ${fg:--} $tree $launcher_cwd"$'\n'
done <<< "$panes"

# Pass 2: classify. A launcher pane also owns unclaimed listeners whose cwd
# is its own directory or below it.
new_seen=""; report=""   # report lines: "<workspace_id> up|wait|down"
while read -r ws pane shell fg tree launcher_cwd; do
  [ -n "$pane" ] || continue
  status=""
  [ "$tree" = up ] && status=up
  if [ -z "$status" ] && [ -n "$launcher_cwd" ]; then
    while read -r lpid lcwd; do
      case "$claimed" in *" $lpid "*) continue;; esac
      case "$lcwd/" in "$launcher_cwd"/*) status=up; break;; esac
    done <<< "$listener_cwds"
  fi
  if [ -z "$status" ] && grep -qx "$pane" "$SEEN"; then
    if [ "$fg" != - ] && [ "$fg" != "$shell" ]; then status=wait; else status=down; fi
  fi
  [ -n "$status" ] || continue
  new_seen="$new_seen$pane"$'\n'
  report="$report$ws $status"$'\n'
done <<< "$rows"
printf '%s' "$new_seen" > "$SEEN"   # closed panes drop out here

dots() { local i out=""; for ((i = 0; i < $1; i++)); do out="$out$2"; done; printf '%s' "$out"; }

for ws in $workspaces; do
  args=()
  for kind in up wait down; do
    n=$(printf '%s' "$report" | grep -c "^$ws $kind$" || true)
    if [ "$n" -eq 0 ]; then args+=(--clear-token "srv_$kind"); continue; fi
    if [ "$kind" = down ]; then sym=$DOT_DOWN; else sym=$DOT; fi
    args+=(--token "srv_$kind=$(dots "$n" "$sym")")
  done
  if [ "$DRY_RUN" = 1 ]; then echo "$ws ${args[*]}"; continue; fi
  "$HERDR" workspace report-metadata "$ws" --source cowbell --ttl-ms "$TTL_MS" "${args[@]}" >/dev/null
done
