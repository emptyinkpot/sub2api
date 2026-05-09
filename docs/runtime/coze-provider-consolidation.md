# Coze Provider Consolidation

## Current Production Truth

Coze traffic is centralized through sub2api on the 170 server.

```text
Client / Mortis / Telegram
-> https://sub2api.tengokukk.com/v1
-> sub2api API key and group routing
-> account: coze-openai-proxy or coze-glm-proxy
-> http://coze-openai-proxy:8787/v1
-> Coze v3 chat API
```

Production runtime roots:

- sub2api: `/srv/sub2api` on `ubuntu@170.106.179.226`
- Coze OpenAI-compatible adapter: `/srv/coze-openai-proxy` on `ubuntu@170.106.179.226`
- Docker network: `sub2api-network`
- Internal upstream URL from sub2api: `http://coze-openai-proxy:8787/v1`
- Public client base URL: `https://sub2api.tengokukk.com/v1`
- Public client model: `coze-shell`

## Active Accounts

The current production database has Coze routed as sub2api accounts:

- `coze-openai-proxy`
  - platform: `openai`
  - base_url: `http://coze-openai-proxy:8787/v1`
  - model mapping: `coze-shell -> coze-shell`
- `coze-glm-proxy`
  - platform: `glm`
  - base_url: `http://coze-openai-proxy:8787/v1`
  - model mapping: `coze-shell -> coze-shell`

The bot-facing exported key is managed outside git and must not be committed.

## Retired Runtime

The 124 server had a separate `coze2openai` container at `127.0.0.1:8788`.
That service is retired and must not be used for new clients.

Retired reference root:

- `/srv/coze2openai` on `ubuntu@124.220.233.126`

Why it is retired:

- It is an older Coze v2 `/open_api/v2/chat` adapter.
- It expects clients to send the Coze token directly as the OpenAI `Authorization` bearer.
- It bypasses sub2api account scheduling, groups, key management, usage tracking, and policy controls.
- It creates a second truth for the same Coze capability.

It is kept only as a reference implementation for old Coze API behavior.

## Adapter Kept For Now

`/srv/coze-openai-proxy` is still a separate container, but it is no longer an independent product surface.
It is an internal upstream adapter owned by the sub2api runtime.

The current adapter supports:

- `GET /health`
- `GET /v1/models`
- `POST /v1/chat/completions`
- `POST /v1/responses`
- streaming and non-streaming text output
- Coze v3 `/v3/chat`

The adapter uses its own upstream Coze credentials:

- `COZE_API_TOKEN`
- `COZE_BOT_ID`
- `COZE_MODEL_NAME=coze-shell`

Clients must never receive those upstream Coze credentials.
Clients receive only sub2api keys.

## Integration Direction

### Phase 1: sub2api-managed adapter

Keep `coze-openai-proxy` as an internal container on the `sub2api-network`, but document and manage it as part of the sub2api deployment.

Acceptance criteria:

- `coze2openai` on 124 remains stopped or retired.
- sub2api database owns the public keys, groups, routing, quotas, and usage records.
- all clients use `https://sub2api.tengokukk.com/v1` and `model=coze-shell`.
- no bot or workflow points at `127.0.0.1:8788` or 124-side Coze services.

### Phase 2: native sub2api Coze provider

Move the adapter logic into sub2api as a native provider instead of a Node sidecar.

Required native provider behavior:

- account platform: `coze`
- credentials: `coze_api_base`, `coze_api_token`, `coze_bot_id`, `coze_user_id`, `model_mapping`
- inbound compatibility:
  - `/v1/chat/completions`
  - `/v1/responses`
- upstream Coze v3 call:
  - `POST {coze_api_base}/v3/chat`
  - `stream=true`
  - `additional_messages` mapped from OpenAI messages/input
- stream mapping:
  - Coze `conversation.message.delta` answer text -> OpenAI chat chunks or Responses deltas
- non-stream mapping:
  - accumulated answer text -> OpenAI-compatible response
- test connection support using `coze-shell`
- usage/error passthrough compatible with existing sub2api accounting

## Do Not Reintroduce

Do not add another standalone Coze proxy unless it is explicitly registered as a sub2api-managed internal upstream.
Do not configure Telegram, Mortis, n8n, Codex, or any client directly against `coze2openai`.
Do not expose raw Coze tokens as client-facing API keys.

See also: [Coze Native Provider Migration Plan](./coze-native-provider-migration-plan.md).

## Native Cutover Status

As of 2026-05-09, the active Coze route is native inside sub2api. The previous `coze-openai-proxy` sidecar has been stopped and renamed as retired. Do not restart it unless rolling back from the native Coze provider.

Active production route:

```text
https://sub2api.tengokukk.com/v1
-> coze-native-shell key
-> Coze Native group
-> coze-native account
-> Coze v3 /v3/chat
```
