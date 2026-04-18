#!/bin/bash
set -e

echo "Setting up TimeTracker..."

if ! command -v brew &> /dev/null; then
    echo "Error: Homebrew is required. Install it from https://brew.sh"
    exit 1
fi

if ! command -v xcodegen &> /dev/null; then
    echo "Installing xcodegen..."
    brew install xcodegen
fi

echo "Generating Xcode project..."
xcodegen generate

echo ""
echo "Done. Next steps:"
echo "  1. Open TimeTracker.xcodeproj in Xcode"
echo "  2. Press Cmd+R to build and run"
echo "  3. When prompted, allow TimeTracker to control Safari / Brave"
echo ""
echo "Tracked data is saved to: ~/Library/Application Support/TimeTracker/"
