#!/bin/sh
# Hermes shell hook: forwards the hook payload (JSON on stdin) to the Agent Workshop bridge.
#
# Hermes runs hook commands synchronously and without a shell, so this is a script: it must be
# quick and must never fail. It exits 0 and prints nothing, even when the bridge is down.
# Set ARENA_BRIDGE_HTTP to use another bridge address.

BRIDGE="${ARENA_BRIDGE_HTTP:-http://127.0.0.1:8787}"
curl -s -m 1 -o /dev/null -X POST -H 'content-type: application/json' \
  --data-binary @- "${BRIDGE%/}/hook/hermes" >/dev/null 2>&1
exit 0
