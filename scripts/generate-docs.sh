#!/usr/bin/env bash
set -euo pipefail

if ! command -v swift-doc >/dev/null 2>&1; then
    echo "error: swift-doc not found. Install it with: brew install swift-doc"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOCS_DIR="${SCRIPT_DIR}/docs"

rm -rf "${DOCS_DIR}/TableGlass" "${DOCS_DIR}/TableGlassKit"
mkdir -p "${DOCS_DIR}"

echo "Generating documentation for TableGlassKit..."
swift-doc generate \
    --module-name "TableGlassKit" \
    --output "${DOCS_DIR}/TableGlassKit" \
    --format html \
    "${SCRIPT_DIR}/TableGlassKit"

echo "Generating documentation for TableGlass..."
swift-doc generate \
    --module-name "TableGlass" \
    --output "${DOCS_DIR}/TableGlass" \
    --format html \
    "${SCRIPT_DIR}/TableGlass"

echo "Documentation successfully generated in '${DOCS_DIR}'."
