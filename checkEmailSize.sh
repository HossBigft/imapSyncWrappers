#!/bin/bash
# Check if input file is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <input_file>"
    exit 1
fi

INPUT_FILE="$1"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Skip header line and prepare input file
tail -n +2 "$INPUT_FILE" > "$TEMP_DIR/accounts.txt"
TOTAL_ACCOUNTS=$(wc -l < "$TEMP_DIR/accounts.txt")
echo "Processing $TOTAL_ACCOUNTS accounts..."

# Function to process a single account
process_account() {
    IFS=';' read -r HOST USER PASS <<< "$1"
    SIZE_LINE=$(imapsync --host1 "$HOST" --user1 "$USER" --password1 "$PASS" \
                --host2 "$HOST" --user2 "$USER" --password2 "$PASS" \
                --dry --justfolders --justfoldersizes | grep "Total size" | head -n1)
    
    BYTES=$(echo "$SIZE_LINE" | awk '{print int($4)}')
    MB=$(awk -v b="$BYTES" 'BEGIN { printf "%.2f", b / (1024 * 1024) }')
    
    echo "$USER:$BYTES:$MB"
}

export -f process_account

# Run processes in parallel and capture output
parallel --progress -a "$TEMP_DIR/accounts.txt" process_account > "$TEMP_DIR/results.txt"

# Generate user-friendly output and calculate total
TOTAL_BYTES=0
while IFS=':' read -r USER BYTES MB; do
    echo "$USER: $MB MB"
    TOTAL_BYTES=$((TOTAL_BYTES + BYTES))
done < "$TEMP_DIR/results.txt"

TOTAL_MB=$(awk -v b="$TOTAL_BYTES" 'BEGIN { printf "%.2f", b / (1024 * 1024) }')
echo "Total size: $TOTAL_MB MB"
