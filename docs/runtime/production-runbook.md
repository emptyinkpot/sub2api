# Sub2API Production Runbook

This document is the operational source for the current self-hosted Sub2API deployment and its consumer-facing contract.

## Current Production Endpoint

| Item | Value |
| --- | --- |
| Public base URL | `https://sub2api.tengokukk.com/` |
| OpenAI-compatible client base URL | `https://sub2api.tengokukk.com/v1` |
| Health check | `GET https://sub2api.tengokukk.com/health` |
| Public DNS | `sub2api.tengokukk.com -> 170.106.179.226` |
| Server | `ubuntu@170.106.179.226` |
| Runtime root | `/srv/sub2api` |
| Deployment mode | `docker-compose` |
| Nginx site | `/etc/nginx/sites-enabled/sub2api.tengokukk.com` |
| TLS certificate | `/etc/letsencrypt/live/sub2api.tengokukk.com/` |
| Internal app target | `http://127.0.0.1:8080` |
| Public ports | `443/tcp` for HTTPS, `80/tcp` for HTTP redirect or ACME |
| Internal app port | `8080/tcp` |
| Internal database/cache | PostgreSQL `5432/tcp`, Redis `6379/tcp` inside the deployment network |

Do not point clients at `170.106.179.226:8080`. Public consumers should use the HTTPS domain. Port `8080` is the app container/backend port behind nginx.

## Consumer Contract

Sub2API is the upstream AI gateway. Consumers receive Sub2API-issued keys, not raw provider keys.

```text
Mortis / Telegram / n8n / FuckVideo / other clients
-> https://sub2api.tengokukk.com/v1
-> Authorization: Bearer <sub2api-issued-key>
-> Sub2API group routing
-> Sub2API upstream account pool
-> provider API
```

Current documented consumers:

| Consumer | Role | Base URL |
| --- | --- | --- |
| Mortis | Operator runtime and AI workflow consumer | `https://sub2api.tengokukk.com/v1` |
| Telegram / n8n | Bot and scheduled workflows | `https://sub2api.tengokukk.com/v1` |
| FuckVideo | Hosted embeddings and LLM access for video understanding | `https://sub2api.tengokukk.com/v1` |

This aligns with the DataBase topology where Mortis is an external runtime consumer and should talk to gateways instead of raw storage or raw provider credentials.

## How Clients Use A Key

Sub2API exposes OpenAI-compatible endpoints. A client uses the Sub2API key as the bearer token:

```bash
curl https://sub2api.tengokukk.com/v1/chat/completions \
  -H "Authorization: Bearer <sub2api-issued-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "coze-shell",
    "messages": [{"role": "user", "content": "ping"}]
  }'
```

Embeddings use the same pattern:

```bash
curl https://sub2api.tengokukk.com/v1/embeddings \
  -H "Authorization: Bearer <sub2api-issued-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "<embedding-model-exposed-by-sub2api>",
    "input": "上海夜景素材"
  }'
```

Never commit live keys. Store them in server environment files, secret stores, or consumer-local `.env` files.

## How To Create A Client API Key

Preferred path: use the web console at `https://sub2api.tengokukk.com/`.

User flow:

1. Sign in with a user that has access to the required group.
2. Open the user key page.
3. Create an API Key.
4. Bind the key to the target group when the consumer should be restricted to one route.
5. Copy the generated key once and store it in the consumer secret store.

API route used by the UI:

```text
POST /api/v1/keys
```

Payload shape:

```json
{
  "name": "mortis-coze-native",
  "group_id": 123,
  "quota": 0,
  "expires_in_days": 0
}
```

Important fields:

| Field | Meaning |
| --- | --- |
| `name` | Human-readable key name. Use consumer and purpose, for example `mortis-coze-native`. |
| `group_id` | Optional group binding. Use it when the key should only call one provider route. |
| `quota` | USD quota. `0` means unlimited in current UI semantics. |
| `expires_in_days` | Optional expiry. Omit or keep unset for no expiry. |
| `ip_whitelist` / `ip_blacklist` | Optional network restrictions. |
| `rate_limit_5h` / `rate_limit_1d` / `rate_limit_7d` | Optional key-level spending/rate windows. |

## How To Add A Group

Preferred path: Admin Console -> Groups.

API route used by the UI:

```text
POST /api/v1/admin/groups
```

Minimal payload:

```json
{
  "name": "Coze Native",
  "description": "Native Coze provider route for Mortis and bot workflows",
  "platform": "coze",
  "rate_multiplier": 1,
  "is_exclusive": true,
  "subscription_type": "standard"
}
```

Group fields that matter operationally:

| Field | Meaning |
| --- | --- |
| `platform` | Scheduler family: `openai`, `glm`, `coze`, `anthropic`, `gemini`, or `antigravity`. |
| `is_exclusive` | If true, only explicitly allowed users/keys should use the group. Use this for Mortis/bot/private routes. |
| `rate_multiplier` | Billing multiplier. Keep `1` unless there is a deliberate pricing reason. |
| `rpm_limit` | Optional group RPM cap. |
| `daily_limit_usd` / `weekly_limit_usd` / `monthly_limit_usd` | Optional group spend limits. |
| `fallback_group_id` | Optional fallback route for recoverable upstream failures. |
| `fallback_group_id_on_invalid_request` | Optional fallback route for invalid-request handling. |
| `require_oauth_only` / `require_privacy_set` | Provider-specific gating; leave false unless the route needs it. |

After creating an exclusive group, grant the target user access in Admin Console -> Users -> Allowed Groups, then create/bind the API key to that group.

## How To Add An Upstream Account

Preferred path: Admin Console -> Accounts -> Create Account.

API route used by the UI:

```text
POST /api/v1/admin/accounts
```

For hosted OpenAI-compatible API-key providers such as OpenAI or GLM:

```json
{
  "name": "glm-embedding",
  "platform": "glm",
  "type": "apikey",
  "credentials": {
    "api_key": "<provider-key>",
    "base_url": "https://open.bigmodel.cn/api/paas/v4",
    "model_mapping": {
      "embedding-client": "embedding-3"
    }
  },
  "group_ids": [123],
  "concurrency": 5,
  "priority": 100
}
```

For native Coze:

```json
{
  "name": "coze-native",
  "platform": "coze",
  "type": "apikey",
  "credentials": {
    "coze_api_base": "https://api.coze.cn",
    "coze_api_token": "<coze-token>",
    "coze_bot_id": "<bot-id>",
    "coze_user_id": "<stable-user-id>",
    "model_mapping": {
      "coze-shell": "coze-shell"
    }
  },
  "group_ids": [123],
  "concurrency": 5,
  "priority": 100
}
```

Operational rules:

- Put raw provider keys only in Sub2API account credentials or deployment secret stores.
- Give consumers only Sub2API keys.
- Bind accounts to the groups that should schedule them.
- Test the account after creation with `POST /api/v1/admin/accounts/:id/test` or the UI Test button.
- If a stale error remains after a successful fix, clear it with `POST /api/v1/admin/accounts/:id/clear-error` or the UI Clear Error action.

## Mortis Alignment

Mortis should be configured as a consumer, not as a provider-key holder.

Mortis-side stable settings:

```env
OPENAI_BASE_URL=https://sub2api.tengokukk.com/v1
OPENAI_API_KEY=<sub2api-issued-key>
```

For Coze-native work:

```env
OPENAI_MODEL=coze-shell
```

For embeddings or video/material retrieval consumers:

```env
MATERIAL_EMBEDDING_BACKEND=openai-compatible
MATERIAL_EMBEDDING_API_BASE_URL=https://sub2api.tengokukk.com/v1
MATERIAL_EMBEDDING_API_MODEL=<embedding-model-exposed-by-sub2api>
MATERIAL_EMBEDDING_API_KEY_ENV=SUB2API_API_KEY
SUB2API_API_KEY=<sub2api-issued-key>
```

Do not configure Mortis, Telegram, n8n, or FuckVideo directly against retired Coze adapters, raw Coze tokens, raw GLM keys, or `127.0.0.1` services on another host.

## Deployment Checks

On the 170 server:

```bash
cd /srv/sub2api
docker compose ps
docker compose logs -f sub2api
curl -i http://127.0.0.1:8080/health
```

From any client network:

```bash
curl -i https://sub2api.tengokukk.com/health
```

Expected public ingress:

```text
client HTTPS :443
-> nginx site /etc/nginx/sites-enabled/sub2api.tengokukk.com
-> http://127.0.0.1:8080
-> sub2api container
```

## Do Not Reintroduce

- Do not expose raw provider credentials to Mortis, Telegram, n8n, FuckVideo, or other clients.
- Do not publish `:8080` as the client-facing API.
- Do not point new clients at the retired 124-side `coze2openai` service.
- Do not create another parallel Coze gateway unless it is explicitly registered as a Sub2API-managed internal upstream.
- Do not commit screenshots, logs, `.env` files, or curl examples containing live keys.
