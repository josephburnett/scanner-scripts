#!/bin/bash

set -e

FILE=$(realpath "$1")

if [ -f "$FILE" ]; then
    echo "Importing $FILE"
else
    echo "File not found: $FILE"
    exit 1
fi

nixnote2 \
    addNote \
    --notebook='_Unfiled' \
    --title="$1" \
    --noteText='%%' \
    --attachment="$FILE"

