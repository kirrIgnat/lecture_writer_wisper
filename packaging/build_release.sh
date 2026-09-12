#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build-release"
DIST_DIR="$ROOT_DIR/dist"
MODELS_DIR="$ROOT_DIR/models"
WHISPER_DIR="${WHISPER_DIR:-$ROOT_DIR/../whisper.cpp}"
FFMPEG_PATH="${FFMPEG_PATH:-$ROOT_DIR/tools/ffmpeg}"

APP_NAME="LectureWhisper"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/LectureWhisper-0.7-macOS-Intel.dmg"
STAGE_DIR="$DIST_DIR/dmg_root"

fail() { echo "ОШИБКА: $1"; exit 1; }

command -v cmake >/dev/null 2>&1 || fail "cmake не найден"
command -v hdiutil >/dev/null 2>&1 || fail "hdiutil не найден"
[ -d "$WHISPER_DIR" ] || fail "Не найден whisper.cpp: $WHISPER_DIR"
[ -f "$FFMPEG_PATH" ] || fail "Не найден ffmpeg: $FFMPEG_PATH"

mkdir -p "$MODELS_DIR" "$DIST_DIR"

MODEL_COUNT="$(find "$MODELS_DIR" -maxdepth 1 -type f -name 'ggml-*.bin' | wc -l | tr -d ' ')"
[ "$MODEL_COUNT" -gt 0 ] || fail "Сначала скачай модели через ./packaging/download_models.sh"

echo "[1/5] Чистая сборка"
rm -rf "$BUILD_DIR"

cmake -S "$ROOT_DIR" -B "$BUILD_DIR"   -DCMAKE_BUILD_TYPE=Release   -DCMAKE_OSX_DEPLOYMENT_TARGET=10.15   -DGGML_METAL=OFF   -DBUILD_SHARED_LIBS=OFF   -DWHISPER_BUILD_TESTS=OFF   -DWHISPER_BUILD_EXAMPLES=OFF

echo "[2/5] Компиляция"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
cmake --build "$BUILD_DIR" -j "$JOBS"

[ -d "$APP_PATH" ] || fail "Не найден $APP_PATH"

echo "[3/5] Встраиваю ffmpeg и модели"
RES="$APP_PATH/Contents/Resources"
mkdir -p "$RES/models"
cp -f "$FFMPEG_PATH" "$RES/ffmpeg"
chmod +x "$RES/ffmpeg"
rm -f "$RES/models"/ggml-*.bin 2>/dev/null || true
cp -f "$MODELS_DIR"/ggml-*.bin "$RES/models/"

echo "[4/5] Подпись"
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

echo "[5/5] DMG"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH"
rm -rf "$STAGE_DIR"
hdiutil verify "$DMG_PATH"

echo
echo "ГОТОВО: $DMG_PATH"
