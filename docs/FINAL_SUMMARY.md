# Langfuse Ruby SDK — 当前状态

Gem 名称：`langfuse-ruby`。当前版本见 `lib/langfuse/version.rb`。

## 对使用者最重要的一点

**Langfuse v4 请使用 `ingestion_mode: :otel`。** 默认仍是 `:legacy`（兼容 0.2.0），但 Cloud 将在 2026-11-16 起拒绝非 score 的 `/api/public/ingestion` 流量。说明见 [V4.md](V4.md) 和仓库根目录 README。

## 能力

- Tracing：trace / span / generation / event，以及 `agent` `tool` `chain` `retriever` `embedding` `evaluator` `guardrail`
- v4 OTEL：OTLP/HTTP、`x-langfuse-ingestion-version: 4`、create/update 合并、W3C hex ID、`usage_details` / `cost_details`
- Prompt：缓存、过期后 stale 读取、URL 编码、`retries` 走 HTTP 层
- Score：始终走 ingestion API；OTEL 模式下 ID 规范化为 hex
- 运行时：有界队列、fork 安全 flush、部分更新、Retry-After + jitter

## 发布

推送 `v*` tag 会触发 `.github/workflows/release.yml`（测 → 构建 → RubyGems → GitHub Release）。步骤见 [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md)。
