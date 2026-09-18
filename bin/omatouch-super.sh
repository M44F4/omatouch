#!/usr/bin/env bash
export LC_ALL=C
set -euo pipefail

GROUP="omatouch"
UDEV_RULE="/etc/udev/rules.d/99-omatouch-uinput.rules"
UNIT_NAME="omatouch-ydotoold.service"
UNIT_PATH="/etc/systemd/system/$UNIT_NAME"
OLD_USER_UNIT_PATH="$HOME/.config/systemd/user/$UNIT_NAME"
STATE_DIR="$HOME/.local/state/omarchy/omatouch"
PKG_MARKER="$STATE_DIR/super-installed-ydotool-pkg"
GROUP_MARKER="$STATE_DIR/super-added-omatouch-group"

remove_old_user_unit() {
  if [ -f "$OLD_USER_UNIT_PATH" ]; then
    systemctl --user disable --now "$UNIT_NAME" 2>/dev/null || true
    rm -f "$OLD_USER_UNIT_PATH"
    systemctl --user daemon-reload 2>/dev/null || true
  fi
}

install() {
  echo "This needs your password for a few of the steps below."
  sudo -v

  mkdir -p "$STATE_DIR"
  echo "==> [1/6] ydotool"
  if pacman -Qi ydotool >/dev/null 2>&1; then
    echo "    already installed -- leaving it as yours, not ours"
    rm -f "$PKG_MARKER"
  else
    sudo pacman -S --needed --noconfirm ydotool
    touch "$PKG_MARKER"
  fi

  echo "==> [2/6] Creating the '$GROUP' group"
  if getent group "$GROUP" >/dev/null; then
    echo "    already exists, nothing to do"
  else
    sudo groupadd --system "$GROUP"
  fi

  echo "==> [3/6] Adding $USER to '$GROUP'"
  if id -nG "$USER" | tr ' ' '\n' | grep -qx "$GROUP"; then
    echo "    already a member, nothing to do"
    rm -f "$GROUP_MARKER"
  else
    sudo usermod -aG "$GROUP" "$USER"
    touch "$GROUP_MARKER"
  fi

  echo "==> [4/6] Granting '$GROUP' access to the virtual-input device"
  printf 'KERNEL=="uinput", GROUP="%s", MODE="0660", OPTIONS+="static_node=uinput"\n' "$GROUP" \
    | sudo tee "$UDEV_RULE" >/dev/null
  sudo udevadm control --reload-rules
  sudo udevadm trigger --subsystem-match=misc || true
  if [ -e /dev/uinput ]; then
    sudo chgrp "$GROUP" /dev/uinput || true
    sudo chmod 0660 /dev/uinput || true
  fi

  echo "==> [5/6] Background service"
  if [ -f "$UNIT_PATH" ] || ! pgrep -x ydotoold >/dev/null 2>&1; then
    USER_UID="$(id -u "$USER")"
    remove_old_user_unit
    sudo tee "$UNIT_PATH" >/dev/null <<EOF
[Unit]
Description=OmaTouch virtual-input daemon (ydotoold)
Documentation=https://github.com/ReimuNotMoe/ydotool
StartLimitIntervalSec=0

[Service]
User=$USER
Group=$GROUP
Environment=XDG_RUNTIME_DIR=/run/user/$USER_UID
ExecStart=/usr/bin/ydotoold
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable "$UNIT_NAME"
    sudo systemctl restart "$UNIT_NAME"
  else
    echo "    ydotoold is already running (started some other way, not by"
    echo "    OmaTouch) -- leaving it alone. Super support already works."
  fi

  echo "==> [6/6] Verifying"
  sleep 1
  echo
  if pgrep -x ydotoold >/dev/null 2>&1; then
    echo "Done -- Super Key Support is active right now, no log-out needed."
    echo "Go back to OmaTouch's Settings -> Advanced and tap \"Check Now\"."
  else
    echo "Setup finished, but ydotoold isn't running -- check the errors"
    echo "above (run \"systemctl status $UNIT_NAME\" for details). It's"
    echo "safe to re-run this command; every step skips anything already done."
  fi
}

uninstall() {
  echo "This needs your password for a few of the steps below."
  sudo -v

  echo "==> [1/4] Stopping the background service"
  remove_old_user_unit
  sudo systemctl disable --now "$UNIT_NAME" 2>/dev/null || true
  sudo rm -f "$UNIT_PATH"
  sudo systemctl daemon-reload

  echo "==> [2/4] Removing the udev rule"
  sudo rm -f "$UDEV_RULE"
  sudo udevadm control --reload-rules || true

  echo "==> [3/4] Removing $USER from '$GROUP'"
  if [ -f "$GROUP_MARKER" ]; then
    sudo gpasswd -d "$USER" "$GROUP" >/dev/null 2>&1 || true
    rm -f "$GROUP_MARKER"
  else
    echo "    leaving it as is -- you were already in '$GROUP' before this"
    echo "    script added anything, so it isn't ours to remove."
  fi

  echo "==> [4/4] ydotool package"
  if [ -f "$PKG_MARKER" ]; then
    sudo pacman -Rns --noconfirm ydotool || true
    rm -f "$PKG_MARKER"
  else
    echo "    leaving it installed -- it was already on your system before"
    echo "    OmaTouch touched it, so it isn't ours to remove."
  fi

  echo
  echo "Done. Super Key Support has been fully removed."
  echo "Go back to OmaTouch's Settings -> Advanced and tap \"Check Now\"."
}

case "${1:-}" in
  install) install ;;
  uninstall) uninstall ;;
  *) echo "usage: $0 install|uninstall" >&2; exit 2 ;;
esac
