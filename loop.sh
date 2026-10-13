#!/usr/bin/env bash
# Single-instance poller: a newer instance takes over the pidfile and the
# older one exits on its next tick.
PIDFILE="$HERDR_PLUGIN_STATE_DIR/loop.pid"
INTERVAL="${COWBELL_INTERVAL:-5}"
echo $$ > "$PIDFILE"
failures=0
while [ "$(cat "$PIDFILE" 2>/dev/null)" = "$$" ]; do
  if ./scan.sh; then failures=0; else failures=$((failures + 1)); fi
  [ "$failures" -lt 5 ] || exit 0   # Herdr server is gone
  sleep "$INTERVAL"
done
