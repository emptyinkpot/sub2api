# Coze Native Provider Migration Plan

## Goal

Move Coze support from an internal Node sidecar into sub2api as a native provider while keeping the current production route usable during the migration.

Target end state:

```text
Client / Mortis / Telegram
-> https://sub2api.tengokukk.com/v1
-> sub2api key, group, quota, usage, policy
-> native coze account
-> Coze v3 /v3/chat
```

The Node adapter `/srv/coze-openai-proxy` should become removable after parity is proven.

## Current Baseline

Production currently works through a managed sidecar:

```text
sub2api account/group routing
-> http://coze-openai-proxy:8787/v1
-> /srv/coze-openai-proxy
-> Coze v3 /v3/chat
```

Known-good public client contract:

- base URL: `https://sub2api.tengokukk.com/v1`
- model: `coze-shell`
- endpoint: `/chat/completions`
- endpoint: `/responses`

The old 124-side `coze2openai` runtime is retired and is not part of this migration except as historical reference.

## Non-Goals

- Do not expose raw Coze tokens to clients.
- Do not revive `coze2openai` as a production service.
- Do not change the public bot/client base URL.
- Do not remove `coze-openai-proxy` until native parity is tested under real traffic.
- Do not rewrite unrelated OpenAI/Codex/Gemini routing logic.

## Phase 0: Freeze Current Truth

Purpose: make the current sidecar route explicit and testable before native code starts.

Tasks:

1. Keep `docs/runtime/coze-provider-consolidation.md` as the source of truth for current production topology.
2. Add a smoke script that validates:
   - `GET https://sub2api.tengokukk.com/health`
   - `POST /v1/chat/completions` with `model=coze-shell`
   - `POST /v1/responses` with `model=coze-shell`
3. Store secret-bearing scripts outside git or make them read keys from server-side secret files.
4. Record expected output shape for chat and responses.

Acceptance:

- current sidecar route returns HTTP 200 for chat completions.
- current sidecar route returns HTTP 200 for responses.
- no secret is printed in logs or committed files.

Rollback:

- none required; this phase is read-only except docs/scripts.

## Phase 1: Add Native Coze Domain Package

Purpose: port the useful part of `/srv/coze-openai-proxy/src/server.js` into a Go package without touching routing first.

Suggested package:

```text
backend/internal/pkg/coze/
├── client.go
├── types.go
├── convert.go
├── sse.go
└── *_test.go
```

Responsibilities:

- Build Coze v3 request:
  - `POST {coze_api_base}/v3/chat`
  - `bot_id`
  - `user_id`
  - `stream=true`
  - `additional_messages`
- Convert OpenAI chat messages to Coze `additional_messages`.
- Convert Responses input/instructions to Coze messages.
- Parse Coze SSE events.
- Extract only answer text deltas from `conversation.message.delta` / answer messages.
- Accumulate non-stream output.
- Return structured upstream errors.

Tests:

- chat messages string content -> Coze messages
- chat messages array text content -> Coze messages
- responses `input` string -> Coze messages
- responses item content array -> Coze messages
- SSE answer delta extraction
- SSE ignores ping/non-answer events
- Coze error payload maps to a typed upstream error

Acceptance:

- package tests pass without network.
- no gateway routing changes yet.

Rollback:

- remove `backend/internal/pkg/coze` package.

## Phase 2: Add Coze Account Platform Surface

Purpose: make Coze visible as a first-class account type while keeping the sidecar accounts untouched.

Tasks:

1. Add platform constant:

```go
PlatformCoze = "coze"
```

2. Add Coze defaults:

```text
Default model: coze-shell
Default base URL: https://api.coze.cn
```

3. Add account credential fields:

```text
coze_api_base
coze_api_token
coze_bot_id
coze_user_id
model_mapping
```

4. Add admin create/edit/test UI hints.
5. Add channel monitor/provider display support.
6. Add model whitelist/default model entry for `coze-shell`.

Acceptance:

- admin can create a Coze account without using the OpenAI platform workaround.
- connection test can call Coze through native provider test logic.
- existing OpenAI/GLM sidecar accounts remain unchanged.

Rollback:

- disable Coze platform in UI and keep old sidecar accounts.

## Phase 3: Native Chat Completions Route

Purpose: route OpenAI-compatible chat completions to native Coze when selected account platform is `coze`.

Tasks:

1. Extend account scheduling so `PlatformCoze` can be selected by a Coze group.
2. In the gateway chat completions path, branch on `account.Platform == PlatformCoze`.
3. Use the Coze package to call upstream Coze v3.
4. Return OpenAI-compatible response shape:

```json
{
  "object": "chat.completion",
  "model": "coze-shell",
  "choices": [
    { "message": { "role": "assistant", "content": "..." }, "finish_reason": "stop" }
  ]
}
```

5. Support streaming chat chunks:

```text
data: {"object":"chat.completion.chunk", "choices":[{"delta":{"content":"..."}}]}
```

Tests:

- non-stream chat completion maps Coze text to OpenAI response.
- stream chat completion emits chunks and `[DONE]`.
- upstream Coze error maps to OpenAI-compatible error.
- usage log still records account, model, endpoint, status.

Acceptance:

- native `coze` group passes `/v1/chat/completions` smoke with `coze-shell`.
- sidecar `openai`/`glm` groups still pass existing smoke.

Rollback:

- move API key back to sidecar-backed group.
- disable native Coze group.

## Phase 4: Native Responses Route

Purpose: support OpenAI Responses-compatible clients through native Coze.

Tasks:

1. Branch `/v1/responses` for `account.Platform == PlatformCoze`.
2. Convert Responses request to Coze messages.
3. Return non-stream Responses shape:

```json
{
  "object": "response",
  "status": "completed",
  "output": [
    {
      "type": "message",
      "role": "assistant",
      "content": [{ "type": "output_text", "text": "..." }]
    }
  ]
}
```

4. Support streaming events:

```text
event: response.created
event: response.output_text.delta
event: response.completed
```

Tests:

- non-stream responses maps answer text.
- streaming responses emits created/delta/completed.
- unsupported input parts are ignored or rejected predictably.
- existing Codex/OpenAI transforms do not run on Coze accounts unless explicitly intended.

Acceptance:

- native Coze group passes `/v1/responses` smoke.
- Mortis Telegram GLM route can use the native group without changing client base URL/model.

Rollback:

- route the bot key back to sidecar group.

## Phase 5: Production Shadow Cutover

Purpose: prove native Coze under real traffic before removing sidecar.

Tasks:

1. Create a new native Coze account in production:

```text
name: coze-native
platform: coze
model: coze-shell
```

2. Create a native Coze group and a separate test API key.
3. Run side-by-side smoke:

```text
sidecar key -> /v1/chat/completions
native key  -> /v1/chat/completions
sidecar key -> /v1/responses
native key  -> /v1/responses
```

4. Move one low-risk client/workflow to native key.
5. Watch logs, latency, error rate, and usage records.
6. Move Telegram/Mortis bot key only after native chat has passed real traffic.

Acceptance:

- native route handles real Telegram/Mortis messages.
- no raw Coze token leaves sub2api.
- usage logs and quotas work like other provider routes.
- sidecar can be retained as fallback for at least one day.

Rollback:

- restore Telegram/Mortis export to sidecar-backed `coze-glm-shell` key.
- disable native Coze group/account.

## Phase 6: Sidecar Retirement

Purpose: remove the last isolated adapter once native Coze is stable.

Tasks:

1. Confirm no production key/group references `http://coze-openai-proxy:8787/v1`.
2. Confirm no workflow/env references `coze-openai-proxy` or `127.0.0.1:8788`.
3. Stop `coze-openai-proxy` container.
4. Keep `/srv/coze-openai-proxy` source for archived reference until one stable week passes.
5. Remove sidecar compose/network wiring after retention window.
6. Update `docs/runtime/coze-provider-consolidation.md` to mark sidecar retired.

Acceptance:

- all Coze traffic uses native `platform=coze` accounts.
- sidecar stopped with no client impact.
- one-week stability window passes without rollback.

Rollback:

- restart sidecar container.
- restore sidecar-backed accounts/groups/API keys.

## Migration Gates

Every implementation PR/commit must pass:

```bash
cd backend
go test ./internal/pkg/coze ./internal/service ./internal/handler/admin ./internal/model ./internal/pkg/...

cd frontend
npm run typecheck
```

Production cutover must pass:

```text
/health HTTP 200
/v1/models HTTP 200
/v1/chat/completions HTTP 200 for coze-shell
/v1/responses HTTP 200 for coze-shell
Telegram/Mortis living reply returns runtime=glm/coze-shell
```

## Data And Secret Rules

- Coze upstream token is stored only in sub2api account credentials or server-side secret files.
- Client-facing keys are sub2api keys only.
- Do not commit `.env`, exported keys, DB dumps, or token-bearing curl commands.
- Mask keys in logs and docs.

## Recommended Next Commit

Start with Phase 1 only:

```text
feat(coze): add native coze v3 client package
```

This gives testable code without changing production routing.

## Phase 1 Progress Log

2026-05-09:

- Added native Coze package skeleton under `backend/internal/pkg/coze`.
- Implemented Coze v3 request types and client request builder.
- Implemented OpenAI Chat Completions message conversion to Coze `additional_messages`.
- Implemented OpenAI Responses input conversion to Coze `additional_messages`.
- Implemented Coze SSE parser and answer-delta extraction.
- Added unit tests for conversion, SSE parsing, and client request construction.
- Corrected native Coze default API root to `https://api.coze.cn`; the retired 124-side `127.0.0.1:8788` adapter must not be used as the default.

Verification performed:

```text
local backend: go test ./internal/pkg/coze
```

Remote verification note:

The 170 server verification now runs through Docker with explicit Go binary paths:

```bash
sudo -n docker run --rm \
  -v /srv/sub2api/backend:/work \
  -w /work \
  golang:1.26.2-alpine \
  sh -lc "/usr/local/go/bin/gofmt -w internal/pkg/coze/*.go && /usr/local/go/bin/go test ./internal/pkg/coze"
```

Result: `ok github.com/Wei-Shaw/sub2api/internal/pkg/coze`.

## Phase 2 Progress Log

2026-05-09:

- Added `PlatformCoze = "coze"` to domain/service constants.
- Added Coze to error passthrough platform lists.
- Added `Account.IsCoze()` without making Coze pretend to be OpenAI.
- Routed account connection testing to native Coze before OpenAI/Gemini branches.
- Implemented native Coze account test using Coze v3 `/v3/chat` with these credentials:
  - `coze_api_base` or account `base_url`, defaulting to `https://api.coze.cn`
  - `coze_api_token` or `api_key`
  - `coze_bot_id`
  - `coze_user_id`, defaulting to `sub2api-test`
- Added unit tests for Coze platform detection and native test request construction.

Verification performed:

```text
Docker: gofmt + go test ./internal/pkg/coze -> PASS
Docker: go test -tags unit ./internal/service -run Coze -> BLOCKED by existing unrelated Proxy.IPAddress compile errors in admin_service.go
```

The service-package blocker is outside the Coze migration files. Do not cut over production routing until the service package compiles cleanly.
