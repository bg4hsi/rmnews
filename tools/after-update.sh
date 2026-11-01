#!/bin/bash
# Bring xovi, AppLoad and rmnews back after a reMarkable firmware update.
# Usage: tools/after-update.sh            (tablet on USB, awake; SSH host "remarkable" or RM_HOST)
#
# A firmware update replaces the system partition: the xovi-tripletap service is gone and
# xovi's hashtable no longer matches xochitl. Everything under /home/root (xovi, AppLoad,
# rmnews, downloaded news, notes, vocabulary) survives.
set -euo pipefail
HOST=${RM_HOST:-remarkable}

say() { printf '\n== %s\n' "$*"; }

say "Connecting to $HOST"
ssh -o ConnectTimeout=8 "$HOST" true || {
    echo "Cannot reach $HOST. Wake the tablet (press the power button) and check the USB cable."
    exit 1
}
ssh "$HOST" 'printf "firmware: "; sed -n "s/^IMG_VERSION=//p" /etc/os-release | tr -d "\""'

say "Rebuilding the xovi hashtable (the screen restarts; unlock the tablet if asked)"
ssh "$HOST" 'echo | timeout 300 /home/root/xovi/rebuild_hashtable 2>&1 | grep -E "Set system version|Hashtab saved|rebuilt" || true'

if ssh "$HOST" 'test -x /home/root/xovi-tripletap/enable.sh'; then
    say "Re-enabling xovi-tripletap (triple-press the power button to start xovi)"
    ssh "$HOST" '/home/root/xovi-tripletap/enable.sh 2>&1 | tail -n 1'
fi

say "Starting xovi"
ssh "$HOST" '/home/root/xovi/start >/dev/null 2>&1 || true'
sleep 15
ssh "$HOST" '
    pid=$(pidof xochitl || true)
    log=$(journalctl -u xochitl --since "-30s" --no-pager)
    echo "$log" | grep -E "Set system version|Hashtab loaded|\[AppLoad\]: Loaded app root" | sed "s/.*\]: //" || true
    sleep 10
    if [ -n "$pid" ] && [ "$pid" = "$(pidof xochitl || true)" ] && echo "$log" | grep -q "AppLoad"; then
        echo "OK: xochitl is stable and AppLoad is loaded. Open AppLoad -> 新闻 News."
    else
        echo "WARNING: AppLoad did not load or xochitl restarted. Reboot the tablet to return to stock;"
        echo "check https://github.com/asivery/rm-appload for support of this firmware."
        exit 1
    fi'
