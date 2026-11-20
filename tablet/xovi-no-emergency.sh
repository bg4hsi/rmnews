#!/bin/bash
# xovi pre-start: firmware 3.30's stock xochitl segfaults when it is stopped, and systemd
# then runs rm-emergency, which reboots the tablet before xovi can start. Mask it for this
# boot only (/run is cleared on reboot). While xovi runs, a real xochitl crash will not
# reboot by itself: hold the power button to restart.
systemctl mask --runtime rm-emergency.service >/dev/null 2>&1 || true
