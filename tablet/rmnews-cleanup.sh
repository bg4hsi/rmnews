#!/bin/sh
# xovi pre-start hook: drop cached articles and pictures older than 14 days.
find /home/root/.local/share/rmnews/cache -type f \( -name 'art-*' -o -name 'img-*' \) -mtime +14 -delete 2>/dev/null
exit 0
