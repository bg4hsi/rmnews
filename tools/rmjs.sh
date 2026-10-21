#!/bin/bash
# Run JavaScript inside the running rmnews app on the tablet (needs the debug flag file).
# Usage: tools/rmjs.sh 'return root.items.length'   or   tools/rmjs.sh -f script.js
# The code runs as a function body with root, News, body, popup and Qt in scope.
HOST=${RM_HOST:-remarkable}
D=/home/root/.local/share/rmnews
if [ "$1" = "-f" ]; then CODE=$(cat "$2"); else CODE="$1"; fi
ssh "$HOST" "test -f $D/debug" || { echo "debug flag missing: ssh $HOST touch $D/debug (then reopen the app)"; exit 1; }
ssh "$HOST" "rm -f $D/out.txt; cat > $D/cmd.js" <<< "$CODE"
for _ in $(seq 1 "${WAIT:-20}"); do
    sleep 1
    if ssh "$HOST" "test -s $D/out.txt"; then ssh "$HOST" "cat $D/out.txt"; echo; exit 0; fi
done
echo "timeout: is the app open?"
exit 1
