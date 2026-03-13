#!/bin/sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$IOS_DIR/.." && pwd)"

FLUTTER_VERSION=""
if [ -f "$REPO_DIR/.fvmrc" ]; then
  FLUTTER_VERSION="$(grep -oE '"flutter"[[:space:]]*:[[:space:]]*"[^"]+"' "$REPO_DIR/.fvmrc" | sed -E 's/.*"([^"]+)"/\1/' | head -n1 || true)"
fi
if [ -z "$FLUTTER_VERSION" ]; then
  FLUTTER_VERSION="$(sed -n 's/^[[:space:]]*flutter:[[:space:]]*\([0-9][0-9.]*\).*/\1/p' "$REPO_DIR/pubspec.yaml" | head -n1 || true)"
fi
if [ -z "$FLUTTER_VERSION" ]; then
  FLUTTER_VERSION="stable"
fi

FLUTTER_HOME="$HOME/flutter"
if [ ! -d "$FLUTTER_HOME/.git" ]; then
  echo "未检测到 Flutter SDK，开始安装：$FLUTTER_VERSION"
  if ! git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_HOME"; then
    echo "按版本安装失败，回退到 stable 分支"
    rm -rf "$FLUTTER_HOME"
    git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_HOME"
    (
      cd "$FLUTTER_HOME"
      git fetch --tags --depth 1 origin "refs/tags/$FLUTTER_VERSION:refs/tags/$FLUTTER_VERSION" || true
      git checkout "$FLUTTER_VERSION" || true
    )
  fi
fi

export PATH="$FLUTTER_HOME/bin:$PATH"

echo "Flutter 版本信息："
flutter --version
flutter config --no-analytics || true
flutter precache --ios

if ! command -v pod >/dev/null 2>&1; then
  echo "未检测到 CocoaPods，尝试自动安装"
  gem install --user-install cocoapods --no-document
  RUBY_VER="$(ruby -e 'print RbConfig::CONFIG["ruby_version"]')"
  export PATH="$HOME/.gem/ruby/$RUBY_VER/bin:$PATH"
fi

if ! command -v pod >/dev/null 2>&1; then
  echo "错误：CocoaPods 安装失败，请在 Xcode Cloud 日志中检查 Ruby/Gem 环境。"
  exit 1
fi

cd "$REPO_DIR"
flutter pub get

cd "$IOS_DIR"
pod install

echo "Xcode Cloud post-clone 阶段完成。"
