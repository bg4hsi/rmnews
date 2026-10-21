#!/bin/sh
# xovi pre-start hook: drop cached articles and pictures older than 14 days,
# except those the reader annotated (note-<id>.json).
cd /home/root/.local/share/rmnews/cache 2>/dev/null || exit 0
find . -type f \( -name 'art-*' -o -name 'img-*' \) -mtime +14 | while read -r f; do
    id=${f#./???-}; id=${id%%.*}
    [ -f "note-$id.json" ] || rm -f "$f"
done
exit 0
