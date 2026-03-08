#!/usr/bin/env bash
# Validates generator output against golden com_generated.zig
# Reports per-method signature differences

set -euo pipefail

BINDGEN_DIR="$HOME/win-zig-bindgen"
GOLDEN="$HOME/ghostty-win/src/apprt/winui3/com_generated.zig"
TMP_DIR="$BINDGEN_DIR/tmp"
TMP_GEN="$TMP_DIR/test_output.zig"

mkdir -p "$TMP_DIR"

# Build generator
echo "Building generator..."
cd "$BINDGEN_DIR"
zig build 2>&1 || { echo "FAIL: zig build failed"; exit 1; }

# Run generator (use the PowerShell regeneration script)
echo "Generating..."
pwsh -NoProfile -File "$HOME/ghostty-win/scripts/winui3-regenerate-com.ps1" -OutPath "$TMP_GEN" 2>&1 | tail -3

if [[ ! -f "$TMP_GEN" ]]; then
    echo "FAIL: No output generated"
    exit 1
fi

# Compare line by line
echo ""
echo "=== ABI Validation ==="

DIFF_OUTPUT=$(diff -u "$GOLDEN" "$TMP_GEN" 2>/dev/null || true)
if [[ -z "$DIFF_OUTPUT" ]]; then
    echo "PASS: Generator output matches golden exactly"
    exit 0
fi

# Extract method-level differences
echo "DRIFT detected. Method-level analysis:"
echo ""

# Find all vtbl function signatures that differ
diff "$GOLDEN" "$TMP_GEN" | grep "^[<>].*fn (" | while IFS= read -r line; do
    direction=$(echo "$line" | cut -c1)
    sig=$(echo "$line" | sed 's/^[<>] *//')
    if [[ "$direction" == "<" ]]; then
        echo "  GOLDEN:    $sig"
    else
        echo "  GENERATED: $sig"
    fi
done

echo ""
DIFF_LINES=$(echo "$DIFF_OUTPUT" | wc -l)
echo "Total diff lines: $DIFF_LINES"
echo ""
echo "Full diff saved to: $TMP_DIR/validation_diff.txt"
echo "$DIFF_OUTPUT" > "$TMP_DIR/validation_diff.txt"

exit 1
