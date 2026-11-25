#!/usr/bin/env bash
# Set the KDE Plasma (Wayland) display scale inside a UTM guest, from the Mac.
#
# Usage: ./set-scale.sh "<vm name or uuid>" <desktop user> <scale>
# Example: ./set-scale.sh "ParrotOS 7.4 security Edition" parrot 2
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 \"<vm name or uuid>\" <desktop user> <scale, e.g. 1.5 or 2>" >&2
  exit 1
fi

VM=$1
DESKTOP_USER=$2
SCALE=$3
OUTPUT=${OUTPUT:-Virtual-1}

if ! [[ $SCALE =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  echo "Scale must be a number such as 1.5 or 2." >&2
  exit 1
fi
if ! [[ $DESKTOP_USER =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "Invalid username: $DESKTOP_USER" >&2
  exit 1
fi

utmctl exec "$VM" --cmd /bin/bash -c "
  uid=\$(id -u $DESKTOP_USER)
  env=\"XDG_RUNTIME_DIR=/run/user/\$uid WAYLAND_DISPLAY=wayland-0\"
  su $DESKTOP_USER -c \"\$env kscreen-doctor output.$OUTPUT.scale.$SCALE\"
  sleep 2
  su $DESKTOP_USER -c \"\$env kscreen-doctor -o\" | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'Geometry|Scale'
"
