#!/bin/bash

set -euo pipefail

# Force C locale so numbers use '.' as decimal separator everywhere
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OUTPUT_DIR="${PROJECT_ROOT}/data"
OUTPUT_FILE="${OUTPUT_DIR}/dataset.bin"
TXT_OUTPUT="${OUTPUT_DIR}/dataset.txt"

DEFAULT_MIN_VAL="-1e15"
DEFAULT_MAX_VAL="1e15"

NUM_VALUES=""
MIN_VAL="$DEFAULT_MIN_VAL"
MAX_VAL="$DEFAULT_MAX_VAL"

usage()
{
    echo "Usage: $0 -n <num> [-m <min>] [-M <max>]"
    echo "  -n <num>        Number of floats to generate (required)"
    echo "  -m <min>        Minimum value (default: $DEFAULT_MIN_VAL)"
    echo "  -M <max>        Maximum value (default: $DEFAULT_MAX_VAL)"
    exit 1
}

while getopts "n:m:M:" opt; do
    case $opt in
        n) NUM_VALUES="$OPTARG" ;;
        m) MIN_VAL="$OPTARG" ;;
        M) MAX_VAL="$OPTARG" ;;
        *) usage ;;
    esac
done

if [ -z "$NUM_VALUES" ]; then
    echo "Error: -n parameter is required"
    usage
fi

if ! [[ "$NUM_VALUES" =~ ^[0-9]+$ ]] || [ "$NUM_VALUES" -le 0 ]; then
    echo "Error: Number of values must be a positive integer"
    exit 1
fi

if ! command -v python3 > /dev/null 2>&1; then
    echo "Error: python3 is required"
    exit 1
fi

# Validate min/max with Python: handles negatives and scientific notation (e.g. -1e15)
if ! python3 - "$MIN_VAL" "$MAX_VAL" <<'EOF'
import sys
try:
    lo, hi = float(sys.argv[1]), float(sys.argv[2])
except ValueError:
    print("Error: min and max must be numbers")
    sys.exit(2)
if not lo < hi:
    print("Error: min must be less than max")
    sys.exit(1)
EOF
then
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_FILE" "$TXT_OUTPUT"

echo "Generating $NUM_VALUES float values in range [$MIN_VAL, $MAX_VAL]..."

python3 - "$NUM_VALUES" "$MIN_VAL" "$MAX_VAL" "$OUTPUT_FILE" <<'EOF'
import random
import struct
import sys

num = int(sys.argv[1])
min_val = float(sys.argv[2])
max_val = float(sys.argv[3])
path = sys.argv[4]

random.seed()
pack = struct.Struct('<f').pack
chunk = 100000

with open(path, 'wb') as f:
    written = 0
    while written < num:
        n = min(chunk, num - written)
        f.write(b''.join(pack(random.uniform(min_val, max_val)) for _ in range(n)))
        written += n
EOF

ACTUAL_SIZE=$(stat -c%s "$OUTPUT_FILE")
COUNT_TO_READ=$((NUM_VALUES < 100 ? NUM_VALUES : 100))

echo "Binary file created: $OUTPUT_FILE ($ACTUAL_SIZE bytes)"
echo "Extracting first $COUNT_TO_READ values to $TXT_OUTPUT..."

{
    echo "# First $COUNT_TO_READ float values from dataset.bin"
    echo "# Range: [$MIN_VAL, $MAX_VAL]"
    echo ""
    od -An -tf4 -w4 -v -N $((COUNT_TO_READ * 4)) "$OUTPUT_FILE" | awk '{print $1}'
} > "$TXT_OUTPUT"

echo "Done."
