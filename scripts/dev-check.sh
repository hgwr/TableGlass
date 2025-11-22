#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT_DIR"

for tool in swiftlint swift-format xcodebuild swift-doc; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "error: $tool is not installed or not on PATH."
        exit 1
    fi
done

echo "1) Linting with SwiftLint..."
swiftlint --quiet --config "$ROOT_DIR/.swiftlint.yml"

echo "2) Checking formatting with swift-format..."
swift-format lint -r TableGlass TableGlassKit TableGlassTests TableGlassUITests

echo "3) Running tests with xcodebuild..."
xcodebuild test -scheme TableGlass -destination 'platform=macOS' -quiet

echo "4) Generating documentation with swift-doc..."
"$ROOT_DIR/scripts/generate-docs.sh"

echo "All checks completed."
