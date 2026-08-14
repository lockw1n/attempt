#!/usr/bin/env bash
#
# TR-0.5.2: builds the three payloads the CDN serves, fresh, into an output directory.
#
#   scripts/generate-remote-content.sh              # writes ./Content
#   scripts/generate-remote-content.sh /tmp/out     # writes there instead
#
# `exercises.json` is copied rather than re-encoded: `Packages/SeedContent/SCHEMA.md` is explicit
# that the bundled and served copies are the same bytes, and this script is not a second place
# that document is authored. `formulas.json` and `flags.json` have no bundled counterpart —
# they come from `GenerateRemoteContent`, RemoteContent's own executable target. That tool also
# validates all three payloads, the copy this script just made included, and exits non-zero rather
# than leave an unpublishable tree behind.
#
# Nothing here is committed — Content/ is `.gitignore`d, and `.github/workflows/deploy-content.yml`
# runs this same script before publishing, so what CI serves is always what this script just wrote,
# never a checked-in copy either one could drift from. This script exists so a local run reproduces
# exactly what CI publishes.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

OUTPUT_DIR="${1:-Content}"

# The output directory is emptied before it is filled, so it has to be one this script could
# plausibly have written. Without this check `generate-remote-content.sh .` deletes the working
# tree, and the usage above invites a path argument.
#
# Resolved through `cd` so that `.` and `..` normalise to the directories they name — comparing
# the argument as written would let `.` past the repo-root check below.
if [[ -d "$OUTPUT_DIR" ]]; then
    OUTPUT_ABS="$(cd "$OUTPUT_DIR" && pwd)"
elif OUTPUT_PARENT="$(cd "$(dirname "$OUTPUT_DIR")" 2>/dev/null && pwd)"; then
    OUTPUT_ABS="$OUTPUT_PARENT/$(basename "$OUTPUT_DIR")"
else
    echo "generate-remote-content.sh: '$OUTPUT_DIR' has no existing parent directory" >&2
    exit 64
fi

if [[ "$OUTPUT_ABS" == "/" || "$OUTPUT_ABS" == "$REPO_ROOT" || "$REPO_ROOT" == "$OUTPUT_ABS"/* ]]; then
    echo "generate-remote-content.sh: refusing to empty '$OUTPUT_ABS' — it contains this repo" >&2
    exit 64
fi

if [[ -e "$OUTPUT_ABS" ]]; then
    if [[ ! -d "$OUTPUT_ABS" ]]; then
        echo "generate-remote-content.sh: '$OUTPUT_ABS' exists and is not a directory" >&2
        exit 64
    fi
    # An earlier run of this script leaves exactly `content/` and `config/` behind. Anything else
    # is someone's directory, not ours to delete.
    while IFS= read -r entry; do
        case "$(basename "$entry")" in
            content | config) ;;
            *)
                echo "generate-remote-content.sh: refusing to empty '$OUTPUT_ABS' — it holds" \
                    "'$(basename "$entry")', which no run of this script wrote" >&2
                exit 64
                ;;
        esac
    done < <(find "$OUTPUT_ABS" -mindepth 1 -maxdepth 1)
fi

rm -rf "$OUTPUT_ABS"
mkdir -p "$OUTPUT_ABS/content/v1"

cp \
    Packages/SeedContent/Sources/SeedContent/Resources/exercises.json \
    "$OUTPUT_ABS/content/v1/exercises.json"

# Writes formulas.json and flags.json, and validates all three.
swift run --package-path Packages/RemoteContent GenerateRemoteContent "$OUTPUT_ABS"

echo
echo "Content written to $OUTPUT_ABS:"
find "$OUTPUT_ABS" -type f | sort
