#!/bin/bash
#
# fetch-dependencies.sh
# Downloads the real yt-dlp and ffmpeg binaries for local development /
# release builds. Never committed to git - see .gitignore. Run this once
# after cloning, and again whenever you want to refresh the bundled
# fallback copies before an Archive.

set -e

RESOURCES_DIR="Resources"
mkdir -p "$RESOURCES_DIR"

echo "Fetching latest yt-dlp..."
curl -L -o "$RESOURCES_DIR/yt-dlp" \
  "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
chmod +x "$RESOURCES_DIR/yt-dlp"

echo "Fetching latest ffmpeg (macOS static build)..."
curl -L -o "$RESOURCES_DIR/ffmpeg.zip" \
  "https://evermeet.cx/ffmpeg/getrelease/zip"
unzip -o "$RESOURCES_DIR/ffmpeg.zip" -d "$RESOURCES_DIR"
rm "$RESOURCES_DIR/ffmpeg.zip"
chmod +x "$RESOURCES_DIR/ffmpeg"

echo "Done. Real binaries are in $RESOURCES_DIR/ (git-ignored)."
echo "Placeholders in the same folder stay tracked so the Xcode project reference and CI build stay intact."
