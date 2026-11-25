#!/usr/bin/env bash
# Create a desktop user inside a UTM Linux guest and make it the auto-login user.
# Runs from the Mac; needs UTM running and the QEMU guest agent in the guest.
#
# Usage: ./create-user.sh "<vm name or uuid>" <username>
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 \"<vm name or uuid>\" <username>" >&2
  exit 1
fi

VM=$1
NEW_USER=$2
STOCK_USER=${STOCK_USER:-user}
AUTOLOGIN_CONF=/etc/lightdm/lightdm.conf.d/50-autologin.conf

if ! [[ $NEW_USER =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "Invalid username: $NEW_USER" >&2
  exit 1
fi

read -r -s -p "Password for $NEW_USER: " PASS; echo
read -r -s -p "Repeat password: " PASS2; echo
if [ "$PASS" != "$PASS2" ] || [ -z "$PASS" ]; then
  echo "Passwords empty or do not match." >&2
  exit 1
fi
case $PASS in
  *$'\n'*|*:*) echo "Password must not contain ':' or a newline." >&2; exit 1 ;;
esac

guest() { utmctl exec "$VM" --cmd /bin/bash -c "$1"; }

guest "id $NEW_USER >/dev/null 2>&1 || {
  G=\$(id -nG $STOCK_USER | tr ' ' '\n' | grep -vx $STOCK_USER | paste -sd,)
  useradd -m -s /bin/bash -G \"\$G\" $NEW_USER
}"

# Send the password base64-encoded so shell quoting cannot alter it.
B64=$(printf '%s:%s' "$NEW_USER" "$PASS" | base64)
guest "echo $B64 | base64 -d | chpasswd"

guest "[ -f $AUTOLOGIN_CONF ] && sed -i 's/^autologin-user=.*/autologin-user=$NEW_USER/' $AUTOLOGIN_CONF || true"

guest "id $NEW_USER"
echo "Done. Reboot the guest to log in as $NEW_USER:"
echo "  utmctl exec \"$VM\" --cmd /sbin/reboot"
