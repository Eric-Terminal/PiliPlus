#!/bin/sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PUB_CACHE_DIR="${PUB_CACHE:-$HOME/.pub-cache}"

if [ -z "${FLUTTER_ROOT:-}" ]; then
  FLUTTER_BIN="$(command -v flutter || true)"
  if [ -z "$FLUTTER_BIN" ]; then
    echo "错误：未找到 flutter，请先把 Flutter SDK 加入 PATH。"
    exit 1
  fi
  FLUTTER_ROOT="$(cd "$(dirname "$FLUTTER_BIN")/.." && pwd)"
fi

apply_patch_file() {
  patch_file="$1"
  patch_path="$REPO_DIR/$patch_file"

  if git apply --check "$patch_path" >/dev/null 2>&1; then
    git apply "$patch_path"
    echo "$patch_file applied"
    return
  fi

  if git apply --reverse --check "$patch_path" >/dev/null 2>&1; then
    echo "$patch_file already applied"
    return
  fi

  echo "错误：无法应用补丁 $patch_file"
  git apply --check "$patch_path"
}

latest_package_dir() {
  package_name="$1"
  find "$PUB_CACHE_DIR/hosted/pub.dev" -maxdepth 1 -type d -name "$package_name-*" | sort | tail -n 1
}

cd "$REPO_DIR"
apply_patch_file "lib/scripts/bottom_sheet_ios_piliplus.patch"
apply_patch_file "lib/scripts/geetest_ios.patch"

cd "$FLUTTER_ROOT"
for patch_file in \
  "lib/scripts/modal_barrier.patch" \
  "lib/scripts/text_selection.patch" \
  "lib/scripts/mouse_cursor.patch" \
  "lib/scripts/image_anim.patch" \
  "lib/scripts/layout_builder.patch" \
  "lib/scripts/navigation_drawer.patch" \
  "lib/scripts/popup_menu.patch" \
  "lib/scripts/fab.patch" \
  "lib/scripts/null_safety_for_selectable_region.patch" \
  "lib/scripts/selectable_region.patch" \
  "lib/scripts/editable_text.patch" \
  "lib/scripts/text_field.patch" \
  "lib/scripts/scroll_position.patch" \
  "lib/scripts/scrollable.patch" \
  "lib/scripts/scrollable_gesture.patch" \
  "lib/scripts/draggable_scrollable_sheet.patch" \
  "lib/scripts/scaffold.patch" \
  "lib/scripts/text.patch" \
  "lib/scripts/text_painter.patch" \
  "lib/scripts/sliver.patch" \
  "lib/scripts/refresh_indicator.patch" \
  "lib/scripts/scroll_view.patch" \
  "lib/scripts/bottom_sheet_ios_flutter.patch" \
  "lib/scripts/navigator.patch"
do
  apply_patch_file "$patch_file"
done

cd "$REPO_DIR"
flutter pub get

MATERIAL_UI_DIR="$(latest_package_dir "material_ui")"
if [ -z "$MATERIAL_UI_DIR" ]; then
  echo "错误：未在 Pub 缓存中找到 material_ui。"
  exit 1
fi

echo "material_ui dir: $MATERIAL_UI_DIR"
cd "$MATERIAL_UI_DIR"
for patch_file in \
  "lib/scripts/material/modal_barrier_material.patch" \
  "lib/scripts/material/navigation_drawer.patch" \
  "lib/scripts/material/popup_menu.patch" \
  "lib/scripts/material/fab.patch" \
  "lib/scripts/material/text_field.patch" \
  "lib/scripts/material/scaffold.patch" \
  "lib/scripts/material/refresh_indicator.patch" \
  "lib/scripts/material/tabs.patch" \
  "lib/scripts/material/bottom_sheet_ios_flutter_material.patch"
do
  apply_patch_file "$patch_file"
done

CUPERTINO_UI_DIR="$(latest_package_dir "cupertino_ui")"
if [ -z "$CUPERTINO_UI_DIR" ]; then
  echo "错误：未在 Pub 缓存中找到 cupertino_ui。"
  exit 1
fi

echo "cupertino_ui dir: $CUPERTINO_UI_DIR"
cd "$CUPERTINO_UI_DIR"
apply_patch_file "lib/scripts/cupertino/bottom_sheet_ios_flutter.patch"

# 使用 Flutter 实际解析的插件目录，避免补丁落到其他版本的 Pub 缓存。
MEDIA_KIT_IOS_DIR="$(ruby -rjson -e '
  plugins = JSON.parse(File.read(ARGV.fetch(0))).fetch("plugins").fetch("ios")
  plugin = plugins.find { |entry| entry.fetch("name") == "media_kit_libs_ios_video" }
  abort "错误：未找到 iOS media-kit 插件。" unless plugin
  puts plugin.fetch("path")
' "$REPO_DIR/.flutter-plugins-dependencies")"
cd "$(git -C "$MEDIA_KIT_IOS_DIR" rev-parse --show-toplevel)"
apply_patch_file "lib/scripts/media_kit_ios.patch"

cd "$REPO_DIR"
echo "iOS 编译补丁已应用。"
