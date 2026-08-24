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
export FLUTTER_SWIFT_PACKAGE_MANAGER=false

echo "Flutter 版本信息："
flutter --version
flutter config --no-analytics || true
flutter config --no-enable-swift-package-manager || true
flutter precache --ios

RUBY_VER="$(ruby -e 'print RbConfig::CONFIG["ruby_version"]')"
export PATH="$HOME/.gem/ruby/$RUBY_VER/bin:$PATH"

if ! command -v pod >/dev/null 2>&1; then
  echo "未检测到 CocoaPods，尝试自动安装"
  echo "预安装 Ruby 2.6 兼容的 CocoaPods 依赖，避免 RubyGems 解析到仅支持 Ruby 3 的版本"
  gem install --user-install ffi -v 1.17.4 --platform=ruby --no-document
  gem install --user-install zeitwerk -v 2.6.18 --no-document
  gem install --user-install i18n -v 1.14.8 --no-document
  gem install --user-install activesupport -v 6.1.7.10 --conservative --no-document
  gem install --user-install cocoapods -v 1.16.2 --conservative --no-document
fi

# CocoaPods 通过 ActiveSupport 启动时依赖 Logger 常量，系统 Ruby 2.6 环境需要显式预加载。
export RUBYOPT="${RUBYOPT:+$RUBYOPT }-rlogger"

if ! command -v pod >/dev/null 2>&1; then
  echo "错误：CocoaPods 安装失败，请在 Xcode Cloud 日志中检查 Ruby/Gem 环境。"
  exit 1
fi

cd "$REPO_DIR"
rm -rf .dart_tool/flutter_build ios/.symlinks ios/Pods ios/Podfile.lock ios/Flutter/ephemeral
rm -f .flutter-plugins .flutter-plugins-dependencies
FLUTTER_ROOT="$FLUTTER_HOME" sh "$REPO_DIR/lib/scripts/patch_ios.sh"

cd "$IOS_DIR"
pod install
echo "已安装的 CocoaPods："
sed -n '/^PODS:/,/^DEPENDENCIES:/p' Podfile.lock

echo "Xcode Cloud post-clone 阶段完成。"
