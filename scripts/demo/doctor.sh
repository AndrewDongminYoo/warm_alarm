#!/bin/bash
set -eu
cd "$(dirname "$0")"
for tool in osascript python3 clang ffmpeg ffprobe; do
  command -v "$tool" || true
done
scratch=$(mktemp -d "${TMPDIR:-/tmp}/warm-alarm-permissions.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
CLANG_MODULE_CACHE_PATH="$scratch/cache" clang permissions.m -framework Cocoa -framework ApplicationServices -framework CoreGraphics -framework Carbon -o "$scratch/permissions"
"$scratch/permissions"
