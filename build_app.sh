#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$PROJECT_DIR/App"
BUILD_DIR="$APP_DIR/.build/release"
OUTPUT_APP="$PROJECT_DIR/TurboFieldfareBar.app"

echo "🔨 正在编译 TurboFieldfareBar 原生状态栏应用..."
cd "$APP_DIR"
swift build -c release

echo "📦 正在打包应用目录结构..."
rm -rf "$OUTPUT_APP"
mkdir -p "$OUTPUT_APP/Contents/MacOS"
mkdir -p "$OUTPUT_APP/Contents/Resources"

cp "$BUILD_DIR/TurboFieldfareBar" "$OUTPUT_APP/Contents/MacOS/"

cat << 'EOF' > "$OUTPUT_APP/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TurboFieldfareBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.justinxie.turbofieldfarebar</string>
    <key>CFBundleName</key>
    <string>TurboFieldfareBar</string>
    <key>CFBundleDisplayName</key>
    <string>TurboFieldfare Bar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <!-- LSUIElement 为 true 表示纯菜单栏辅助应用：不占用 Dock、无默认主窗口 -->
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

chmod +x "$OUTPUT_APP/Contents/MacOS/TurboFieldfareBar"

echo "✅ 打包完成！"
echo "📍 应用路径: $OUTPUT_APP"
echo "💡 你可以直接双击运行，或将其拖拽至 /Applications (应用程序) 目录中使用。"

