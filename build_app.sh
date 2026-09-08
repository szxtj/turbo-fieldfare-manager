#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$PROJECT_DIR/App"
BUILD_DIR="$APP_DIR/.build/release"
OUTPUT_APP="$PROJECT_DIR/TurboFieldfareBar.app"
DMG_OUTPUT="$PROJECT_DIR/TurboFieldfareBar.dmg"
ICON_PATH="$PROJECT_DIR/App/Resources/AppIcon.icns"

echo "=========================================================="
echo "🚀 开始构建 TurboFieldfareBar 状态栏应用与 DMG 安装镜像"
echo "=========================================================="

# 1. 编译 Swift 可执行文件
echo "🔨 正在编译 TurboFieldfareBar Release 版本..."
(cd "$APP_DIR" && swift build -c release)

# 2. 打包 .app 目录结构
echo "📦 正在生成应用包 TurboFieldfareBar.app..."
rm -rf "$OUTPUT_APP"
mkdir -p "$OUTPUT_APP/Contents/MacOS"
mkdir -p "$OUTPUT_APP/Contents/Resources"

cp "$BUILD_DIR/TurboFieldfareBar" "$OUTPUT_APP/Contents/MacOS/"

# 拷贝应用图标
if [ -f "$ICON_PATH" ]; then
    cp "$ICON_PATH" "$OUTPUT_APP/Contents/Resources/AppIcon.icns"
fi

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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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

# 3. 签名检测与执行 (严格过滤公司/团队签名，优先个人签名，无则使用无签名)
echo "🔐 检测代码签名证书..."

PERSONAL_IDENTITY=""
# 提取所有代码签名身份
IDENTITIES=$(security find-identity -v -p codesigning 2>/dev/null || true)

if [ -n "$IDENTITIES" ]; then
    # 严格排除含有公司、团队、组织关键字的证书
    FILTERED_IDENTITIES=$(echo "$IDENTITIES" | grep -v -i -E "Co\.|Ltd|Inc|Corp|Company|Team|Enterprise|Group|Distribution")
    
    # 优先匹配当前用户的个人证书 (如包含 Justin 或 Apple Development)
    PERSONAL_IDENTITY=$(echo "$FILTERED_IDENTITIES" | grep -i "Justin" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
    
    if [ -z "$PERSONAL_IDENTITY" ]; then
        PERSONAL_IDENTITY=$(echo "$FILTERED_IDENTITIES" | grep "Apple Development:" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
    fi
fi

if [ -n "$PERSONAL_IDENTITY" ]; then
    echo "   ✅ 发现本地个人开发者签名: $PERSONAL_IDENTITY"
    echo "   ✍️  正在应用个人签名..."
    codesign --force --deep --sign "$PERSONAL_IDENTITY" "$OUTPUT_APP"
else
    echo "   ℹ️  未检测到个人签名证书（或已安全过滤企业/团队证书），采用本地无签名/Ad-hoc 模式 (-)..."
    codesign --force --deep --sign - "$OUTPUT_APP"
fi

# 4. 生成发布 DMG 安装镜像
echo "💿 正在打包发布 DMG 镜像..."
DMG_STAGING="/tmp/turbofieldfare_dmg_staging_$$"
rm -rf "$DMG_STAGING" "$DMG_OUTPUT"
mkdir -p "$DMG_STAGING"

# 拷贝 App 与应用程序软链接
cp -R "$OUTPUT_APP" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

# 使用 macOS 原生 hdiutil 生成压缩 DMG
hdiutil create \
    -volname "TurboFieldfareBar" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_OUTPUT" > /dev/null

rm -rf "$DMG_STAGING"

# 若有个人签名，顺便为 DMG 容器签名
if [ -n "$PERSONAL_IDENTITY" ]; then
    codesign --force --sign "$PERSONAL_IDENTITY" "$DMG_OUTPUT" 2>/dev/null || true
else
    codesign --force --sign - "$DMG_OUTPUT" 2>/dev/null || true
fi

echo "=========================================================="
echo "🎉 打包完成！成品信息如下："
echo "   ├─ 📱 原生应用: $OUTPUT_APP"
echo "   ├─ 💿 安装镜像: $DMG_OUTPUT"
echo "   └─ 📏 镜像大小: $(du -sh "$DMG_OUTPUT" | awk '{print $1}')"
echo "=========================================================="
echo "💡 用户只需打开 TurboFieldfareBar.dmg，将 TurboFieldfareBar 拖入 Applications 即可使用！"
