#!/usr/bin/env bash
# Build an install-ready zip: dist/GoonerJourneys-<version>.zip
# Unzip it into World of Warcraft/_forever_/Interface/AddOns/
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(git describe --tags --always 2>/dev/null || echo dev)}"
VERSION="${VERSION#v}"
OUT="dist"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$OUT" "$STAGE/GoonerJourneys"
cp GoonerJourneys/*.lua GoonerJourneys/*.toc "$STAGE/GoonerJourneys/"
# Images (Hall of Fame photos etc.)
if compgen -G "GoonerJourneys/media/*.tga" > /dev/null || compgen -G "GoonerJourneys/media/*.blp" > /dev/null; then
    mkdir -p "$STAGE/GoonerJourneys/media"
    cp GoonerJourneys/media/*.tga GoonerJourneys/media/*.blp "$STAGE/GoonerJourneys/media/" 2>/dev/null || true
fi
sed -i.bak "s/@project-version@/${VERSION}/" "$STAGE/GoonerJourneys/GoonerJourneys.toc"
rm -f "$STAGE/GoonerJourneys/"*.bak

ZIP="$OUT/GoonerJourneys-${VERSION}.zip"
rm -f "$ZIP"
(cd "$STAGE" && zip -qr - GoonerJourneys) > "$ZIP"
echo "Built $ZIP"
