# Cursor 遥测拦截补丁

[English](README.md)

阻止 Cursor IDE 向后端服务器发送遥测和分析数据。

## 功能说明

在 Cursor 内置的 `cursor-always-local` 扩展的 ConnectRPC 传输层拦截出站 RPC 调用。遥测相关调用在到达网络之前被捕获，并静默返回空响应。

### 拦截的 RPC

| 服务 | 方法 | 说明 |
|---|---|---|
| `AnalyticsService` | `Batch` | 批量事件上报（仓库活动、功能使用等） |
| `AnalyticsService` | `TrackEvents` | 事件追踪上报 |
| `AiService` | `ReportCommitAiAnalytics` | Commit AI 评分分析上报 |
| `AiService` | `ReportAiCodeChangeMetrics` | 代码变更指标上报 |

### 不受影响

- AI 聊天、代码补全、Agent、Cmd+K（所有功能正常使用）
- `AnalyticsService.BootstrapStatsig`（实验框架，拦截会导致功能异常）
- 所有其他非遥测 RPC 调用

## 工作原理

```
                    transport.unary(service, method, ...)
                                    │
                    ┌───────────────┴───────────────┐
                    │          注入的拦截器            │
                    │                                │
                    │  if (AnalyticsService &&       │
                    │      method ≠ BootstrapStatsig)│
                    │    → 返回空响应                 │
                    │                                │
                    │  if (ReportCommitAiAnalytics   │
                    │   || ReportAiCodeChangeMetrics)│
                    │    → 返回空响应                 │
                    └───────────────┬───────────────┘
                                    │
                          (非遥测调用正常通过)
                                    │
                                    ▼
                           Cursor 后端
```

补丁修改 `Cursor.app` 内的两个文件：

1. **`extensions/cursor-always-local/dist/main.js`** — 在 `transport.unary()` 入口注入 `if` 判断，拦截遥测调用并返回空响应。

2. **`out/vs/workbench/api/node/extensionHostProcess.js`** — 更新 `main.js` 的 SHA-256 哈希值。Cursor 内置扩展有完整性校验表（`hct`），不更新哈希会导致 "Hash mismatch" 错误，扩展宿主进程无法启动。

## 使用方法

### 一键安装（curl）

```bash
# 应用补丁
curl -fsSL https://raw.githubusercontent.com/lyonle/patch-cursor-telemetry/main/patch-telemetry.sh | sudo bash

# 恢复原文件
curl -fsSL https://raw.githubusercontent.com/lyonle/patch-cursor-telemetry/main/unpatch-telemetry.sh | sudo bash
```

执行后重启 Cursor。

### 本地安装

```bash
# 应用补丁
sudo ./patch-telemetry.sh

# 恢复原文件
sudo ./unpatch-telemetry.sh
```

执行后重启 Cursor。

### Cursor 更新后

Cursor 更新会覆盖已补丁的文件，每次更新后需要重新执行补丁命令。

如果 macOS 提示 `Operation not permitted` 阻止文件访问，先清除隔离属性：

```bash
sudo xattr -cr /Applications/Cursor.app
```

## 环境要求

- macOS，Cursor 安装在 `/Applications/Cursor.app`
- Node.js（用于字符串替换和 SHA-256 计算）
- `sudo` 权限

## 文件说明

| 文件 | 说明 |
|---|---|
| `patch-telemetry.sh` | 应用遥测拦截补丁 |
| `unpatch-telemetry.sh` | 从备份恢复原始文件 |
