#!/usr/bin/env bash
set -uo pipefail

GROUP="omatouch"
UDEV_RULE="/etc/udev/rules.d/99-omatouch-uinput.rules"
UNIT_NAME="omatouch-ydotoold.service"

pkg="false"
pacman -Qi ydotool >/dev/null 2>&1 && pkg="true"

rule="false"
[ -f "$UDEV_RULE" ] && rule="true"

group_member="false"
id -nG "$USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$GROUP" && group_member="true"

service_active="false"
pgrep -x ydotoold >/dev/null 2>&1 && service_active="true"

printf '{"pkg":%s,"rule":%s,"groupMember":%s,"serviceActive":%s}\n' \
  "$pkg" "$rule" "$group_member" "$service_active"
