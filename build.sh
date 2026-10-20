#!/bin/bash
# Package the AppLoad app into build/rmnews and optionally deploy it (./build.sh deploy).
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build/rmnews && mkdir -p build/rmnews
python3 -I tools/mkrcc.py build/rmnews/resources.rcc app/ui ui
cp app/manifest.json app/icon.png build/rmnews/
echo "built build/rmnews"
if [[ ! -d build/dict ]]; then
    echo "building offline dictionary from ECDICT ..."
    curl -sfLo build/ecdict.csv https://raw.githubusercontent.com/skywind3000/ECDICT/master/ecdict.csv
    python3 -I tools/build_dict.py build/ecdict.csv build/dict
    rm build/ecdict.csv
fi
if [[ "${1:-}" == "deploy" ]]; then
    HOST=${RM_HOST:-remarkable}
    DEST=/home/root/xovi/exthome/appload/rmnews
    ssh "$HOST" "mkdir -p $DEST /home/root/.local/share/rmnews/cache"
    scp -q build/rmnews/* "$HOST:$DEST/"
    scp -q tablet/rmnews-cleanup.sh "$HOST:/home/root/xovi/scripts/pre-start/"
    if [[ -d build/dict ]] && ! ssh "$HOST" "test -f $DEST/dict/ab.json"; then
        echo "uploading dictionary ..."
        scp -qr build/dict "$HOST:$DEST/"
    fi
    echo "restarting xochitl with xovi ..."
    ssh "$HOST" "/home/root/xovi/start >/dev/null 2>&1"
    echo "deployed"
fi
