#!/bin/bash

# Check if the input file is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <input_file>"
    exit 1
fi

INPUT_FILE="$1"
TOTAL_BYTES=0

# Read the input file line by line, skipping the header
while IFS=';' read -r HOST USER PASS; do
    SIZE_LINE=$(./imapsync --host1 "$HOST" --user1 "$USER" --password1 "$PASS" \
               --host2 "$HOST" --user2 "$USER" --password2 "$PASS" \
               --dry --justfolders --justfoldersizes | grep "Total size" | head -n1)

    BYTES=$(echo "$SIZE_LINE" | awk '{print int($4)}')
    MB=$(awk -v b="$BYTES" 'BEGIN { printf "%.2f", b / (1024 * 1024) }')
    echo "$USER: $MB MB"
    TOTAL_BYTES=$((TOTAL_BYTES+BYTES))
done < <(tail -n +2 "$INPUT_FILE")

TOTAL_MB=$(awk -v b="$TOTAL_BYTES" 'BEGIN { printf "%.2f", b / (1024 * 1024) }')
echo "Total size: $TOTAL_MB MB"
