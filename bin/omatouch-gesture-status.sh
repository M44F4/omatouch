#!/usr/bin/env bash
set -uo pipefail

UNIT_NAME="omatouch-gesture.service"
UNIT_PATH="/etc/systemd/system/$UNIT_NAME"
GROUP="input"

unit_installed="false"
[ -f "$UNIT_PATH" ] && unit_installed="true"

group_member="false"
id -nG "$USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$GROUP" && group_member="true"

service_active="false"
systemctl is-active --quiet "$UNIT_NAME" 2>/dev/null && service_active="true"

STATE_DIR="$HOME/.local/state/omarchy/omatouch"
HEARTBEAT_PATH="$STATE_DIR/gesture-heartbeat.json"

python3 - "$unit_installed" "$group_member" "$service_active" "$HEARTBEAT_PATH" <<'PYEOF'
import json
import sys
import time

unit_installed, group_member, service_active, heartbeat_path = sys.argv[1:5]

heartbeat_age = None
device = None
try:
    with open(heartbeat_path) as f:
        d = json.load(f)
    heartbeat_age = max(0, time.time() - float(d.get("ts", 0)))
    device = d.get("device") or None
except (OSError, ValueError, TypeError):
    pass

print(json.dumps({
    "unitInstalled": unit_installed == "true",
    "groupMember": group_member == "true",
    "serviceActive": service_active == "true",
    "heartbeatAgeSec": heartbeat_age,
    "device": device,
}))
PYEOF
