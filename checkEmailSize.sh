#!/bin/bash
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <input_file>"
    exit 1
fi

INPUT_FILE="$1"
TEMP_DIR=$(mktemp -d)
CACHE_DIR="$HOME/.cache/imapsync_sizes"
CACHE_VALIDITY=86400  # 24 hours in seconds
mkdir -p "$CACHE_DIR"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Function to check and retrieve cached values
get_cached_size() {
    local USER="$1"
    local CACHE_FILE="$CACHE_DIR/${USER//\//_}.size"
    
    # Check if cache exists and is fresh
    if [ -f "$CACHE_FILE" ] && [ $(($(date +%s) - $(stat -c %Y "$CACHE_FILE"))) -lt "$CACHE_VALIDITY" ]; then
        cat "$CACHE_FILE"
        return 0
    fi
    
    return 1  # Cache miss
}

# Function to save to cache
save_to_cache() {
    local USER="$1"
    local DATA="$2"
    local CACHE_FILE="$CACHE_DIR/${USER//\//_}.size"
    
    echo "$DATA" > "$CACHE_FILE"
}

# Function to process a single account
process_account() {
    IFS=';' read -r HOST USER PASS <<< "$1"
    
    # 
    # CACHED_RESULT=$(get_cached_size "$USER")
    # if [ -n "$CACHED_RESULT" ]; then
    #     echo "$CACHED_RESULT"
    #     return
    # fi
    
    # Cache miss - fetch from server
    # Look for any line containing "Total size" (more flexible)
    SIZE_LINE=$(timeout 120 imapsync --host1 "$HOST" --user1 "$USER" --password1 "$PASS" \
                --host2 "$HOST" --user2 "$USER" --password2 "$PASS" \
                --dry --justfolders --justfoldersizes | grep -i "total size" | head -n1)
    
    if [ -z "$SIZE_LINE" ]; then
        RESULT="$USER:0:0.00"
    else
        # Extract bytes from "Host1 Total size: XXXXXXXXX bytes (X.XXX GiB)"
        # The bytes value is the 4th field when split by spaces
        BYTES=$(echo "$SIZE_LINE" | awk '{print int($4)}')
        MB=$(awk -v b="$BYTES" 'BEGIN { printf "%.2f", b / (1024 * 1024) }')
        RESULT="$USER:$BYTES:$MB"
    fi
    
    # Save to cache
    save_to_cache "$USER" "$RESULT"
    echo "$RESULT"
}

# read file
tail -n +1 "$INPUT_FILE" > "$TEMP_DIR/accounts.txt"
TOTAL_ACCOUNTS=$(wc -l < "$TEMP_DIR/accounts.txt")
echo "Processing $TOTAL_ACCOUNTS accounts..."

export -f process_account
export -f get_cached_size
export -f save_to_cache
export CACHE_DIR
export CACHE_VALIDITY

# Run processes in parallel with customizable job count
PARALLEL_JOBS=${PARALLEL_JOBS:-8}  # Default to 8 parallel jobs, override with environment variable
parallel --progress -j "$PARALLEL_JOBS" -a "$TEMP_DIR/accounts.txt" process_account > "$TEMP_DIR/results.txt"

# Generate output and calculate total
TOTAL_BYTES=0
while IFS=':' read -r USER BYTES MB; do
    echo "$USER: $MB MB"
    TOTAL_BYTES=$((TOTAL_BYTES + BYTES))
done < "$TEMP_DIR/results.txt"

TOTAL_MB=$(awk -v b="$TOTAL_BYTES" 'BEGIN { printf "%.2f", b / (1024 * 1024) }')
TOTAL_GB=$(awk -v b="$TOTAL_BYTES" 'BEGIN { printf "%.2f", b / (1024 * 1024 * 1024) }')
echo "Total size: $TOTAL_MB MB ($TOTAL_GB GB)"