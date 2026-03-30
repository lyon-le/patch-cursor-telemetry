# Cursor Telemetry Patch

Block Cursor IDE from sending telemetry and analytics data to its backend servers.

## What It Does

Intercepts outgoing RPC calls at the ConnectRPC transport layer inside Cursor's built-in `cursor-always-local` extension. Telemetry calls are caught before they reach the network and silently return empty responses.

### Blocked RPCs

| Service | Method | Description |
|---|---|---|
| `AnalyticsService` | `Batch` | Batched event reporting (repo activity, feature usage) |
| `AnalyticsService` | `TrackEvents` | Event tracking |
| `AiService` | `ReportCommitAiAnalytics` | Commit AI scoring analytics |
| `AiService` | `ReportAiCodeChangeMetrics` | Code change metrics reporting |

### Not Affected

- AI chat, completions, Agent, Cmd+K (all functional features work normally)
- `AnalyticsService.BootstrapStatsig` (experiment framework, blocking breaks features)
- All other non-telemetry RPC calls

## How It Works

```
                    transport.unary(service, method, ...)
                                    │
                    ┌───────────────┴───────────────┐
                    │      Injected Interceptor      │
                    │                                │
                    │  if (AnalyticsService &&       │
                    │      method ≠ BootstrapStatsig)│
                    │    → return empty response     │
                    │                                │
                    │  if (ReportCommitAiAnalytics   │
                    │   || ReportAiCodeChangeMetrics)│
                    │    → return empty response     │
                    └───────────────┬───────────────┘
                                    │
                          (non-telemetry calls)
                                    │
                                    ▼
                           Cursor Backend
```

The patch modifies two files inside `Cursor.app`:

1. **`extensions/cursor-always-local/dist/main.js`** — Injects an `if` check at the top of `transport.unary()` to intercept telemetry calls and return empty responses.

2. **`out/vs/workbench/api/node/extensionHostProcess.js`** — Updates the SHA-256 hash of `main.js` in Cursor's built-in extension integrity verification table (`hct`). Without this, Cursor rejects the modified extension with "Hash mismatch" and the extension host fails to start.

## Usage

### Apply Patch

```bash
sudo ./patch-telemetry.sh
```

Then restart Cursor.

### Remove Patch

```bash
sudo ./unpatch-telemetry.sh
```

Then restart Cursor.

### After Cursor Updates

Cursor updates overwrite both patched files. Re-run `patch-telemetry.sh` after each update.

If macOS blocks file access with `Operation not permitted`, clear the quarantine attribute first:

```bash
sudo xattr -cr /Applications/Cursor.app
```

## Requirements

- macOS with Cursor installed at `/Applications/Cursor.app`
- Node.js (used for string replacement and SHA-256 computation)
- `sudo` access

## Files

| File | Description |
|---|---|
| `patch-telemetry.sh` | Apply the telemetry patch |
| `unpatch-telemetry.sh` | Restore original files from backup |
