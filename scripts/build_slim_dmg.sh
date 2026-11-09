#!/bin/bash
# ==============================================================================
# 天河網絡 (Tianhe Network) - macOS 輕巧瘦身編譯與 DMG 封裝腳本 (v3.3.1)
# 支援架構：Apple Silicon (arm64) & Intel (x86_64) 通用 Universal
# 核心規範：Apple TN2206 安全標準 + 符號連結 (Symlink) 零冗餘輕巧化
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist_mac"
BUILD_OUTPUT="$PROJECT_ROOT/build/macos/Build/Products/Release"
APP_NAME="Tianhe"
APP_BUNDLE="$BUILD_OUTPUT/$APP_NAME.app"

APP_VER=$(grep 'version:' "$PROJECT_ROOT/pubspec.yaml" | head -n 1 | awk '{print $2}' | cut -d'+' -f1)
APP_BUILD=$(grep 'version:' "$PROJECT_ROOT/pubspec.yaml" | head -n 1 | awk '{print $2}' | cut -d'+' -f2)
if [ -z "$APP_VER" ]; then APP_VER="3.3.1"; fi
if [ -z "$APP_BUILD" ]; then APP_BUILD="131"; fi

DMG_NAME="TianheNetwork_v${APP_VER}_macOS.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
MIHOMO_DIR="$PROJECT_ROOT/tools/mihomo"
MIHOMO_BIN="$MIHOMO_DIR/mihomo"

echo "=========================================="
echo "🏛️ 天河網絡 (Tianhe) - macOS Release Build SOP"
echo "Project Root:    $PROJECT_ROOT"
echo "Target Artifact: $DMG_PATH"
echo "Version:         v$APP_VER (Build $APP_BUILD)"
echo "=========================================="

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR"/*.dmg "$DIST_DIR"/*.app

# 1. 檢查並獲取 mihomo-darwin 內核 (Universal Apple Silicon + Intel)
mkdir -p "$MIHOMO_DIR"
if [ ! -f "$MIHOMO_BIN" ]; then
    echo "⬇️ 正在下載官方 Mihomo Darwin 雙架構內核 (v1.19.33)..."
    ARM64_URL="https://github.com/MetaCubeX/mihomo/releases/download/v1.19.33/mihomo-darwin-arm64-v1.19.33.gz"
    AMD64_URL="https://github.com/MetaCubeX/mihomo/releases/download/v1.19.33/mihomo-darwin-amd64-v1.19.33.gz"

    curl -L -s "$ARM64_URL" -o "$MIHOMO_DIR/mihomo-arm64.gz"
    curl -L -s "$AMD64_URL" -o "$MIHOMO_DIR/mihomo-amd64.gz"

    gzip -d -f "$MIHOMO_DIR/mihomo-arm64.gz"
    gzip -d -f "$MIHOMO_DIR/mihomo-amd64.gz"

    chmod +x "$MIHOMO_DIR/mihomo-arm64" "$MIHOMO_DIR/mihomo-amd64"

    echo "🔗 正在透過 lipo 合併為 Universal 通用二進位..."
    lipo -create "$MIHOMO_DIR/mihomo-arm64" "$MIHOMO_DIR/mihomo-amd64" -output "$MIHOMO_BIN"
    rm -f "$MIHOMO_DIR/mihomo-arm64" "$MIHOMO_DIR/mihomo-amd64"
    chmod +x "$MIHOMO_BIN"
    echo "✅ Mihomo Darwin Universal 內核合成完成"
else
    chmod +x "$MIHOMO_BIN"
    echo "✅ 已檢測到本機 Mihomo 內核: $MIHOMO_BIN"
fi

# 2. 檢查離線地理分流資料庫
if [ ! -f "$MIHOMO_DIR/Country.mmdb" ]; then
    echo "⬇️ 正在獲取離線 GeoIP 資料庫 (Country.mmdb)..."
    curl -L -s "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb" -o "$MIHOMO_DIR/Country.mmdb"
fi

# 3. 執行 Flutter Release 編譯與代碼混淆
cd "$PROJECT_ROOT"
echo "📦 正在拉取 Flutter 依賴..."
flutter pub get

echo "🔨 正在編譯 macOS 獨立應用程式 (Release + Obfuscate)..."
mkdir -p "$PROJECT_ROOT/build/macos_symbols"
flutter build macos --release \
    --obfuscate \
    --split-debug-info="$PROJECT_ROOT/build/macos_symbols" \
    --dart-define=APP_VERSION="$APP_VER" \
    --dart-define=APP_BUILD_NUMBER="$APP_BUILD"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ 找不到編譯產物: $APP_BUNDLE"
    exit 1
fi

# 4. 嵌入 tianhe_engine 內核至 Contents/MacOS (Apple TN2206 標準) 與離線資料庫至 Resources
echo "📂 正在將內核封裝進 $APP_NAME.app (Apple TN2206 架構)..."
cp -f "$MIHOMO_BIN" "$APP_BUNDLE/Contents/MacOS/tianhe_engine"
chmod +x "$APP_BUNDLE/Contents/MacOS/tianhe_engine"

APP_RES_DIR="$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_RES_DIR"
for db_file in Country.mmdb GeoIP.dat GeoSite.dat ASN.mmdb geoip.metadb; do
    if [ -f "$MIHOMO_DIR/$db_file" ]; then
        cp -f "$MIHOMO_DIR/$db_file" "$APP_RES_DIR/"
    fi
done

# 兼容舊路徑（使用 0 KB 軟連結 Symlink，實現 100% 雙向相容且零冗餘）
echo "🔗 建立向後相容軟連結 (Symlink 零冗餘瘦身)..."
APP_TOOLS_DIR="$APP_BUNDLE/Contents/Resources/tools/mihomo"
mkdir -p "$APP_TOOLS_DIR"
ln -sf "../../../MacOS/tianhe_engine" "$APP_TOOLS_DIR/mihomo"
for db_file in Country.mmdb GeoIP.dat GeoSite.dat ASN.mmdb geoip.metadb; do
    if [ -f "$MIHOMO_DIR/$db_file" ]; then
        ln -sf "../../$db_file" "$APP_TOOLS_DIR/$db_file"
    fi
done

# 5. 檔案體積極限瘦身 (剔除除錯暫存檔)
echo "✂️ 正在進行二進位與資源極限瘦身..."
find "$APP_BUNDLE" -name "*.dSYM" -exec rm -rf {} + 2>/dev/null || true
find "$APP_BUNDLE" -name "*.pdb" -delete 2>/dev/null || true
rm -f "$APP_BUNDLE/Contents/Frameworks/App.framework/Resources/kernel_blob.bin" 2>/dev/null || true

# 6. Ad-hoc 本地簽名 (確保 Gatekeeper 與 macOS 13/14/15 順暢執行)
echo "🔏 正在執行 Ad-hoc 本機程式碼簽名..."
codesign --force --sign - "$APP_BUNDLE/Contents/MacOS/tianhe_engine" 2>/dev/null || true
codesign --force --deep --sign - "$APP_BUNDLE"

# 7. 打包封裝為標準拖拽式 DMG
echo "💿 正在生成 $DMG_NAME 安裝映像檔..."
DMG_TEMP_DIR="$PROJECT_ROOT/build/dmg_temp"
rm -rf "$DMG_TEMP_DIR"
mkdir -p "$DMG_TEMP_DIR"

cp -R "$APP_BUNDLE" "$DMG_TEMP_DIR/"
cp -R "$APP_BUNDLE" "$DIST_DIR/"
ln -s /Applications "$DMG_TEMP_DIR/Applications"

# 透過 hdiutil 建立壓縮型 DMG
hdiutil create -volname "Tianhe Network" \
    -srcfolder "$DMG_TEMP_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_TEMP_DIR"

# 8. 輸出產物成果
FILE_SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo "=========================================="
echo "🎉 SUCCESS: macOS 輕巧版發布打包完成！"
echo "DMG 產物: $DMG_PATH ($FILE_SIZE)"
echo "App 產物: $APP_BUNDLE"
echo "=========================================="
