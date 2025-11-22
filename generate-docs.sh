#!/bin/sh
set -e

# Check if swift-doc is installed
if ! command -v swift-doc &> /dev/null
then
    echo "warning: swift-doc not found. Please install it to generate documentation."
    echo "See: https://github.com/apple/swift-doc"
    exit 0
fi

echo "Generating documentation for TableGlass and TableGlassKit..."

# Note: This requires swift-doc to be installed.
# You can install it via Homebrew: `brew install swift-doc`
swift doc generate \
    --module-name "TableGlass" \
    --output "docs" \
    --format html \
    ./TableGlass/ \
    ./TableGlassKit/

echo "Documentation successfully generated in the 'docs' directory."
