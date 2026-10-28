#!/bin/bash

set -euo pipefail

export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${PROJECT_ROOT}/data"

DEFAULT_MIN_VAL="-1000"
DEFAULT_MAX_VAL="1000"
DEFAULT_OUTPUT="dataset.bin"

NUM_VALUES=""
MIN_VAL="$DEFAULT_MIN_VAL"
MAX_VAL="$DEFAULT_MAX_VAL"
OUTPUT_NAME="$DEFAULT_OUTPUT"
ALL=false

usage()
{
    echo "Usage: $0 -n <num> [-m <min>] [-M <max>] [-o <file>]"
    echo "       $0 -a [-m <min>] [-M <max>]"
    echo ""
    echo "  -n <num>     Number of floats to generate"
    echo "  -m <min>     Minimum value (default: $DEFAULT_MIN_VAL)"
    echo "  -M <max>     Maximum value (default: $DEFAULT_MAX_VAL)"
    echo "  -o <file>    Output file name inside data/ (default: $DEFAULT_OUTPUT)"
    echo "  -a           Generate all standard datasets used by the program:"
    echo "               100Dataset.bin, 1000Dataset.bin, 1MlnDataset.bin, 10MlnDataset.bin"
    exit 1
}

while getopts "n:m:M:o:ah" opt; do
    case $opt in
        n) NUM_VALUES="$OPTARG" ;;
        m) MIN_VAL="$OPTARG" ;;
        M) MAX_VAL="$OPTARG" ;;
        o) OUTPUT_NAME="$OPTARG" ;;
        a) ALL=true ;;
        *) usage ;;
    esac
done

if ! command -v python3 > /dev/null 2>&1; then
    echo "Error: python3 is required"
    exit 1
fi

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

generate()
{
    local num="$1"
    local name="$2"
    local out="${OUTPUT_DIR}/${name}"

    echo "Generating $num floats in [$MIN_VAL, $MAX_VAL] -> data/$name"

    python3 - "$num" "$MIN_VAL" "$MAX_VAL" "$out" <<'EOF'
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

    echo "  created ($(stat -c%s "$out") bytes)"
}

write_preview()
{
    local name="$1"
    local num="$2"
    local count=$((num < 100 ? num : 100))
    local txt="${OUTPUT_DIR}/${name%.bin}.txt"

    {
        echo "# First $count float values from $name"
        echo "# Range: [$MIN_VAL, $MAX_VAL]"
        echo ""
        od -An -tf4 -w4 -v -N $((count * 4)) "${OUTPUT_DIR}/${name}" | awk '{print $1}'
    } > "$txt"

    echo "  preview: data/$(basename "$txt")"
}

mkdir -p "$OUTPUT_DIR"

if [ "$ALL" = true ]; then
    for spec in "100:100Dataset.bin" "1000:1000Dataset.bin" \
                "1000000:1MlnDataset.bin" "10000000:10MlnDataset.bin"; do
        generate "${spec%%:*}" "${spec#*:}"
    done
    echo "Done."
    exit 0
fi

if [ -z "$NUM_VALUES" ]; then
    echo "Error: -n or -a is required"
    usage
fi

if ! [[ "$NUM_VALUES" =~ ^[0-9]+$ ]] || [ "$NUM_VALUES" -le 0 ]; then
    echo "Error: Number of values must be a positive integer"
    exit 1
fi

if [[ "$OUTPUT_NAME" == */* ]]; then
    echo "Error: -o takes a file name, not a path (files are written to data/)"
    exit 1
fi

generate "$NUM_VALUES" "$OUTPUT_NAME"
write_preview "$OUTPUT_NAME" "$NUM_VALUES"
echo "Done."
