#!/bin/bash
#
# 恢复 Cursor 遥测拦截补丁
#
# 从备份文件恢复 main.js 和 extensionHostProcess.js 到原始状态。
#
# 用法:
#   sudo ./unpatch-telemetry.sh

set -e

APP_DIR="/Applications/Cursor.app/Contents/Resources/app"
TARGET="$APP_DIR/extensions/cursor-always-local/dist/main.js"
EXT_HOST="$APP_DIR/out/vs/workbench/api/node/extensionHostProcess.js"
BACKUP="${TARGET}.bak"
EXT_HOST_BACKUP="${EXT_HOST}.bak"

echo "=== Cursor Telemetry Unpatch ==="
echo ""

if [ ! -f "$BACKUP" ] || [ ! -f "$EXT_HOST_BACKUP" ]; then
    echo "错误: 找不到备份文件"
    [ ! -f "$BACKUP" ] && echo "  缺少: $BACKUP"
    [ ! -f "$EXT_HOST_BACKUP" ] && echo "  缺少: $EXT_HOST_BACKUP"
    echo ""
    echo "可能从未 patch 过，或备份已被删除。"
    exit 1
fi

if ! grep -q '"aiserver.v1.AnalyticsService"===t.typeName' "$TARGET" 2>/dev/null; then
    echo "[ok] 当前未处于 patch 状态，无需恢复"
    exit 0
fi

echo "[1/2] 恢复原始文件..."
cp "$BACKUP" "$TARGET"
echo "  -> main.js 已恢复"
cp "$EXT_HOST_BACKUP" "$EXT_HOST"
echo "  -> extensionHostProcess.js 已恢复"

echo "[2/2] 验证..."
if grep -q '"aiserver.v1.AnalyticsService"===t.typeName' "$TARGET" 2>/dev/null; then
    echo "  [fail] 恢复失败，拦截代码仍存在"
    exit 1
fi
echo "  [ok] 已恢复到原始状态"

echo ""
echo "=== Unpatch 成功，请重启 Cursor ==="
