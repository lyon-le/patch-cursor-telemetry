#!/bin/bash
#
# Cursor 遥测拦截 — Transport 层拦截
#
# 在 cursor-always-local 扩展的 ConnectRPC transport.unary() 路由入口
# 注入拦截逻辑，对遥测相关 RPC 调用返回空响应，不再转发到服务器。
#
# 拦截的 RPC:
#   - AnalyticsService.Batch           (事件批量上报)
#   - AnalyticsService.TrackEvents     (事件上报)
#   - AiService.ReportCommitAiAnalytics    (commit AI 评分上报)
#   - AiService.ReportAiCodeChangeMetrics  (代码变更指标上报)
#
# 放行的 RPC:
#   - AnalyticsService.BootstrapStatsig  (实验框架，拦截会影响功能)
#   - 所有 AI 聊天、补全、Agent 等功能性调用
#
# 用法:
#   sudo ./patch-telemetry.sh
#
# 恢复:
#   sudo ./unpatch-telemetry.sh
#
# Cursor 更新后需要重新执行

set -e

APP_DIR="/Applications/Cursor.app/Contents/Resources/app"
TARGET="$APP_DIR/extensions/cursor-always-local/dist/main.js"
EXT_HOST="$APP_DIR/out/vs/workbench/api/node/extensionHostProcess.js"
BACKUP="${TARGET}.bak"
EXT_HOST_BACKUP="${EXT_HOST}.bak"

check_files() {
    if [ ! -f "$TARGET" ]; then
        echo "错误: 找不到 $TARGET"
        echo "请确认 Cursor 已安装在 /Applications/"
        exit 1
    fi
    if [ ! -f "$EXT_HOST" ]; then
        echo "错误: 找不到 $EXT_HOST"
        exit 1
    fi
}

check_already_patched() {
    if grep -q '"aiserver.v1.AnalyticsService"===t.typeName' "$TARGET" 2>/dev/null; then
        echo "[ok] 已经 patch 过了，无需重复操作"
        exit 0
    fi
}

backup() {
    echo "[1/4] 备份原始文件..."
    cp "$TARGET" "$BACKUP"
    cp "$EXT_HOST" "$EXT_HOST_BACKUP"
    echo "  -> main.js.bak"
    echo "  -> extensionHostProcess.js.bak"
}

inject_interceptor() {
    echo "[2/4] 注入遥测拦截器..."

    node -e '
const fs = require("fs");
const target = process.argv[1];
let code = fs.readFileSync(target, "utf8");

const OLD = [
  "unary(t,n,r,s,o,i,a){",
  "const u=e._getTransportForService(t.typeName,n.name);",
  "if(void 0===u)throw new Error(\"INVARIANT VIOLATION: Transport is undefined for service: \"+t.typeName);",
  "return u.transport.unary(t,n,r,s,o,i,a)}"
].join("");

const INTERCEPT = [
  "try{if((\"aiserver.v1.AnalyticsService\"===t.typeName",
  "&&\"BootstrapStatsig\"!==n.name)",
  "||\"ReportCommitAiAnalytics\"===n.name",
  "||\"ReportAiCodeChangeMetrics\"===n.name)",
  "{const _O=typeof n.O===\"function\"?new n.O:{};",
  "return Promise.resolve({stream:!1,service:t,method:n,",
  "header:new Headers,message:_O,trailer:new Headers})}}catch(_){}"
].join("");

const NEW = "unary(t,n,r,s,o,i,a){" + INTERCEPT + OLD.slice("unary(t,n,r,s,o,i,a){".length);

if (!code.includes(OLD)) {
  console.error("  [fail] 未找到目标代码模式，Cursor 版本可能不匹配");
  process.exit(1);
}

code = code.replace(OLD, NEW);
fs.writeFileSync(target, code, "utf8");
console.log("  [ok] 拦截器已注入");
' "$TARGET"
}

update_hash() {
    echo "[3/4] 更新扩展文件哈希校验..."

    node -e '
const fs = require("fs");
const crypto = require("crypto");
const target = process.argv[1];
const extHost = process.argv[2];

const newHash = crypto.createHash("sha256").update(fs.readFileSync(target)).digest("hex");

let code = fs.readFileSync(extHost, "utf8");
const re = /("anysphere\.cursor-always-local":\{dist:\{"gitWorker\.js":"[a-f0-9]+","main\.js":")([a-f0-9]+)(")/;
const match = code.match(re);

if (!match) {
  console.error("  [fail] 未找到哈希条目");
  process.exit(1);
}

code = code.replace(re, "$1" + newHash + "$3");
fs.writeFileSync(extHost, code, "utf8");
console.log("  [ok] 哈希已更新:", match[2].slice(0, 12) + "... ->", newHash.slice(0, 12) + "...");
' "$TARGET" "$EXT_HOST"
}

verify() {
    echo "[4/4] 验证..."

    if ! grep -q '"aiserver.v1.AnalyticsService"===t.typeName' "$TARGET" 2>/dev/null; then
        echo "  [fail] 拦截器未写入，恢复备份..."
        cp "$BACKUP" "$TARGET"
        cp "$EXT_HOST_BACKUP" "$EXT_HOST"
        exit 1
    fi

    if ! node -e "require('fs').readFileSync('$TARGET','utf8')" 2>/dev/null; then
        echo "  [fail] 文件异常，恢复备份..."
        cp "$BACKUP" "$TARGET"
        cp "$EXT_HOST_BACKUP" "$EXT_HOST"
        exit 1
    fi

    echo "  [ok] 验证通过"
}

main() {
    echo "=== Cursor Telemetry Patch ==="
    echo ""
    check_files
    check_already_patched
    backup
    inject_interceptor
    update_hash
    verify
    echo ""
    echo "=== Patch 成功，请重启 Cursor ==="
    echo ""
    echo "拦截: AnalyticsService.Batch/TrackEvents, AiService.Report*"
    echo "放行: BootstrapStatsig, AI 聊天/补全/Agent"
    echo "恢复: sudo ./unpatch-telemetry.sh"
}

main
