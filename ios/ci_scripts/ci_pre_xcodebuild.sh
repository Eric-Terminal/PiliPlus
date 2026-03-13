#!/bin/sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$IOS_DIR/.." && pwd)"

unset CPATH || true
unset LIBRARY_PATH || true
unset SDKROOT || true

if [ -d "$HOME/flutter/bin" ]; then
  export PATH="$HOME/flutter/bin:$PATH"
fi

VERSION_CODE="$(git -C "$REPO_DIR" rev-list --count HEAD)"
VERSION_NAME="$(sed -n 's/^[[:space:]]*version:[[:space:]]*\([0-9][0-9.]*\).*/\1/p' "$REPO_DIR/pubspec.yaml" | head -n1)"
if [ -z "$VERSION_NAME" ]; then
  VERSION_NAME="SNAPSHOT"
fi
COMMIT_HASH="$(git -C "$REPO_DIR" rev-parse HEAD)"
BUILD_TIME="$(date +%s)"

cat >"$REPO_DIR/pili_release.json" <<EOF
{"pili.name":"$VERSION_NAME","pili.code":$VERSION_CODE,"pili.hash":"$COMMIT_HASH","pili.time":$BUILD_TIME}
EOF

encode_define() {
  printf "%s" "$1" | base64 | tr -d '\n'
}

EXTRA_DEFINES="$(encode_define "pili.name=$VERSION_NAME"),$(encode_define "pili.code=$VERSION_CODE"),$(encode_define "pili.hash=$COMMIT_HASH"),$(encode_define "pili.time=$BUILD_TIME")"
GENERATED_XCCONFIG="$IOS_DIR/Flutter/Generated.xcconfig"

if [ -f "$GENERATED_XCCONFIG" ]; then
  CURRENT_DEFINES="$(sed -n 's/^DART_DEFINES=//p' "$GENERATED_XCCONFIG" | tail -n1 || true)"
  if [ -n "$CURRENT_DEFINES" ]; then
    NEW_DEFINES="$CURRENT_DEFINES,$EXTRA_DEFINES"
  else
    NEW_DEFINES="$EXTRA_DEFINES"
  fi

  awk -v value="$NEW_DEFINES" '
    BEGIN { replaced=0 }
    /^DART_DEFINES=/ {
      if (replaced == 0) {
        print "DART_DEFINES=" value
        replaced=1
      }
      next
    }
    { print }
    END {
      if (replaced == 0) {
        print "DART_DEFINES=" value
      }
    }
  ' "$GENERATED_XCCONFIG" > "$GENERATED_XCCONFIG.tmp"
  mv "$GENERATED_XCCONFIG.tmp" "$GENERATED_XCCONFIG"
fi

echo "Xcode Cloud pre-xcodebuild 阶段完成。"
SHORT_HASH="$(printf '%.9s' "$COMMIT_HASH")"
echo "版本信息：name=$VERSION_NAME code=$VERSION_CODE hash=$SHORT_HASH..."
