#!/usr/bin/env bash
#
# TR-0.5.2: builds the three payloads the CDN serves, fresh, into an output directory.
#
#   scripts/generate-remote-content.sh              # writes ./Content
#   scripts/generate-remote-content.sh /tmp/out      # writes there instead
#
# `exercises.json` is copied rather than re-encoded: `Packages/SeedContent/SCHEMA.md` is explicit
# that the bundled and served copies are the same bytes, and this script is not a second place
# that document is authored. `formulas.json` and `flags.json` have no bundled counterpart —
# they come from `GenerateRemoteContent`, RemoteContent's own executable target, which encodes
# `RPETable.standard` and the flags literal with `.sortedKeys` so two runs agree byte for byte
# (see that target's header comment for why plain `Codable` key order is not enough on its own).
#
# Nothing here is committed — Content/ is `.gitignore`d, and `.github/workflows/deploy-content.yml`
# runs this same script before publishing, so what CI serves is always what this script just wrote,
# never a checked-in copy either one could drift from. This script exists so a local run reproduces
# exactly what CI publishes.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

OUTPUT_DIR="${1:-Content}"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/content/v1"

cp \
    Packages/SeedContent/Sources/SeedContent/Resources/exercises.json \
    "$OUTPUT_DIR/content/v1/exercises.json"

swift run --package-path Packages/RemoteContent GenerateRemoteContent "$OUTPUT_DIR"

echo
echo "Content written to $OUTPUT_DIR:"
find "$OUTPUT_DIR" -type f | sort
