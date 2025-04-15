#!/bin/bash
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <input_file>"
    exit 1
fi

INPUT_FILE="$1"
TEMP_DIR=$(mktemp -d)
CACHE_DIR="$HOME/.cache/imapsync_sizes"
mkdir -p "$CACHE_DIR"
trap 'rm -rf "$TEMP_DIR"' EXIT

tail -n +2 "$INPUT_FILE" > "$TEMP_DIR/accounts.txt"
TOTAL_ACCOUNTS=$(wc -l < "$TEMP_DIR/accounts.txt")
echo "Processing $TOTAL_ACCOUNTS accounts..."

process_account() {
    IFS=';' read -r HOST USER PASS <<< "$1"
    CACHE_FILE="$CACHE_DIR/${USER//\//_}.size"
    
    # Check cache age - use if less than 24 hours old
    if [ -f "$CACHE_FILE" ] && [ $(($(date +%s) - $(stat -c %Y "$CACHE_FILE"))) -lt 86400 ]; then
        cat "$CACHE_FILE"
        return
    fi
    
    SIZE_LINE=$(timeout 60 imapsync --host1 "$HOST" --user1 "$USER" --password1 "$PASS" \
                --host2 "$HOST" --user2 "$USER" --password2 "$PASS" \
                --dry --justfolders --justfoldersizes | grep "Total size" | head -n1)
    
    if [ -z "$SIZE_LINE" ]; then
        echo "$USER:0:0.00"
        return
    fi
    
    BYTES=$(echo "$SIZE_LINE" | awk '{print int($4)}')
    MB=$(awk -v b="$BYTES" 'BEGIN { printf "%.2f", b / (1024 * 1024) }')
    
    echo "$USER:$BYTES:$MB" | tee "$CACHE_FILE"
}

export -f process_account
export CACHE_DIR

# Increase number of jobs with -j flag (e.g., -j 8)
parallel --progress -j 8 -a "$TEMP_DIR/accounts.txt" process_account > "$TEMP_DIR/results.txt"

TOTAL_BYTES=0
while IFS=':' read -r USER BYTES MB; do
    echo "$USER: $MB MB"
    TOTAL_BYTES=$((TOTAL_BYTES + BYTES))
done < "$TEMP_DIR/results.txt"

TOTAL_MB=$(awk -v b="$TOTAL_BYTES" 'BEGIN { printf "%.2f", b / (1024 * 1024) }')
echo "Total size: $TOTAL_MB MB"
