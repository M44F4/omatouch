#!/usr/bin/env bash
export LC_ALL=C
set -euo pipefail

GROUP="input"
UNIT_NAME="omatouch-gesture.service"
UNIT_PATH="/etc/systemd/system/$UNIT_NAME"
STATE_DIR="$HOME/.local/state/omarchy/omatouch"
GROUP_MARKER="$STATE_DIR/gesture-added-input-group"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

install() {
  echo "This needs your password for a couple of the steps below."
  sudo -v

  mkdir -p "$STATE_DIR"

  echo "==> [1/3] Adding $USER to the '$GROUP' group"
  if id -nG "$USER" | tr ' ' '\n' | grep -qx "$GROUP"; then
    echo "    already a member, nothing to do"
    rm -f "$GROUP_MARKER"
  else
    sudo usermod -aG "$GROUP" "$USER"
    touch "$GROUP_MARKER"
  fi

  echo "==> [2/3] Setting up the background service"
  USER_UID="$(id -u "$USER")"
  sudo tee "$UNIT_PATH" >/dev/null <<EOF
[Unit]
Description=OmaTouch three-finger double-tap gesture daemon
StartLimitIntervalSec=0

[Service]
User=$USER
Group=$GROUP
Environment=XDG_RUNTIME_DIR=/run/user/$USER_UID
ExecStart=/usr/bin/python3 $PLUGIN_DIR/bin/omatouch-gesture-daemon.py
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable "$UNIT_NAME"
  sudo systemctl restart "$UNIT_NAME"
  sleep 1

  echo "==> [3/3] Verifying"
  echo
  if systemctl is-active --quiet "$UNIT_NAME"; then
    echo "Done -- try it: tap three fingers on the screen twice, quickly."
    echo "Go back to OmaTouch's Settings -> Advanced and tap \"Check Now\"."
  else
    echo "Setup finished, but the service didn't start -- check the errors"
    echo "above (run \"systemctl status $UNIT_NAME\" for details). It's"
    echo "safe to re-run this command; every step skips anything already done."
  fi
}

uninstall() {
  echo "This needs your password for a couple of the steps below."
  sudo -v

  echo "==> [1/2] Stopping the background service"
  sudo systemctl disable --now "$UNIT_NAME" 2>/dev/null || true
  sudo rm -f "$UNIT_PATH"
  sudo systemctl daemon-reload

  echo "==> [2/2] '$GROUP' group membership"
  if [ -f "$GROUP_MARKER" ]; then
    sudo gpasswd -d "$USER" "$GROUP" >/dev/null 2>&1 || true
    rm -f "$GROUP_MARKER"
  else
    echo "    leaving it as is -- you were already in '$GROUP' before this"
    echo "    script added anything, so it isn't ours to remove."
  fi

  echo
  echo "Done. The three-finger gesture has been fully removed."
  echo "Go back to OmaTouch's Settings -> Advanced and tap \"Check Now\"."
}

case "${1:-}" in
  install) install ;;
  uninstall) uninstall ;;
  *) echo "usage: $0 install|uninstall" >&2; exit 2 ;;
esac
