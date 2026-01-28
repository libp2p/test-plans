#!/usr/bin/env bash
# Update README.md files with test results between markers.
# Usage: update-readme-results.sh <readme_path> <results_path>

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: update-readme-results.sh <readme_path> <results_path>" >&2
    exit 1
fi

README_PATH="$1"
RESULTS_PATH="$2"

# Check if files exist
if [ ! -f "$RESULTS_PATH" ]; then
    echo "Error: Results file not found: $RESULTS_PATH" >&2
    exit 1
fi

if [ ! -f "$README_PATH" ]; then
    echo "Error: README file not found: $README_PATH" >&2
    exit 1
fi

START_MARKER="<!-- TEST_RESULTS_START -->"
END_MARKER="<!-- TEST_RESULTS_END -->"

# Check if markers exist in README
if ! grep -q "$START_MARKER" "$README_PATH" || ! grep -q "$END_MARKER" "$README_PATH"; then
    echo "→ Adding test results section to $README_PATH"
    cat >> "$README_PATH" <<EOF

## Latest Test Results

$START_MARKER
$END_MARKER
EOF
fi

# Create temporary file for the new content
TEMP_FILE=$(mktemp)
trap 'rm -f "$TEMP_FILE"' EXIT

# Read README line by line and build new content
IN_SECTION=false
while IFS= read -r line; do
    case "$line" in
        *"$START_MARKER"*)
            # Write start marker
            echo "$line" >> "$TEMP_FILE"
            # Write results content
            cat "$RESULTS_PATH" >> "$TEMP_FILE"
            IN_SECTION=true
            ;;
        *"$END_MARKER"*)
            # Write end marker
            echo "$line" >> "$TEMP_FILE"
            IN_SECTION=false
            ;;
        *)
            if [ "$IN_SECTION" == "false" ]; then
                # Write line if not in the section we're replacing
                echo "$line" >> "$TEMP_FILE"
            fi
            ;;
    esac
done < "$README_PATH"

# Check if content changed
if cmp -s "$README_PATH" "$TEMP_FILE"; then
    echo "→ No changes needed for $README_PATH"
    exit 0
fi

# Replace original with updated content
mv "$TEMP_FILE" "$README_PATH"
echo "→ Updated $README_PATH"
