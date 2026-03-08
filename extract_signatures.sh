#!/usr/bin/env bash
# Extracts vtbl method signatures from a com_generated.zig file
# Usage: ./extract_signatures.sh <file>

FILE="${1:?Usage: $0 <zig_file>}"

# Extract interface name and vtbl entries
awk '
/^pub const I[A-Z]/ { iface=$3 }
/callconv\(.winapi\)/ {
    # Get the method name (field before the colon)
    match($0, /([A-Za-z_0-9]+):/, arr)
    if (arr[1] != "") {
        gsub(/^[[:space:]]+/, "")
        printf "%s.%s: %s\n", iface, arr[1], $0
    }
}
' "$FILE" | sort
