#!/bin/sh
# Detach the poller. Redirecting all three streams matters: Herdr waits for
# the hook's stdout/stderr pipes to close before marking the command finished.
mkdir -p "$HERDR_PLUGIN_STATE_DIR"
nohup ./loop.sh </dev/null >"$HERDR_PLUGIN_STATE_DIR/loop.log" 2>&1 &
