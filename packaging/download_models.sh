#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WHISPER_DIR="${WHISPER_DIR:-$ROOT_DIR/../whisper.cpp}"
WHISPER_MODELS="$WHISPER_DIR/models"
DOWNLOADER="$WHISPER_MODELS/download-ggml-model.sh"
DEST="$ROOT_DIR/models"

if [ "$#" -eq 0 ]; then
    set -- tiny base small
fi

if [ ! -f "$DOWNLOADER" ]; then
    echo "Ошибка: не найден $DOWNLOADER"
    exit 1
fi

mkdir -p "$DEST"
chmod +x "$DOWNLOADER"

for REQUESTED in "$@"; do
    MODEL="$REQUESTED"
    [ "$MODEL" = "max" ] && MODEL="large-v3"

    case "$MODEL" in
        tiny|base|small|medium|large-v1|large-v2|large-v3) ;;
        *)
            echo "Неизвестная модель: $REQUESTED"
            exit 1
            ;;
    esac

    TARGET="$DEST/ggml-$MODEL.bin"

    if [ -f "$TARGET" ]; then
        echo "Уже есть: $(basename "$TARGET")"
        continue
    fi

    echo "Скачиваю $REQUESTED..."
    (
        cd "$WHISPER_MODELS"
        ./download-ggml-model.sh "$MODEL"
    )

    SOURCE="$WHISPER_MODELS/ggml-$MODEL.bin"
    [ -f "$SOURCE" ] || { echo "Не найден $SOURCE"; exit 1; }

    cp -f "$SOURCE" "$TARGET"
    echo "Готово: $TARGET"
done

echo
echo "Модели:"
ls -lh "$DEST"/ggml-*.bin 2>/dev/null || true
