#!/bin/bash

set -e

read -p "Enter title : " TITLE
if [[ -z "${TITLE?}" ]]; then
    echo "Usage: scan-to-nixnote2.sh <title>"
    exit 1
fi
ID=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
DIR="/tmp/scan/$ID"
echo "Scanning \"${TITLE?}\" to ${ID?} in ${DIR}"

mkdir -p $DIR
cd $DIR
function finish {
    cd /
    rm $DIR/*
    rmdir $DIR
}
trap finish EXIT

scanimage --device 'fujitsu:ScanSnap iX500:316724' --batch --source 'ADF Duplex'

convert *.pnm out.pdf

nixnote2 \
    addNote \
    --notebook='_Unfiled' \
    --title="$TITLE" \
    --noteText="%%" \
    --attachment="$DIR/out.pdf"

