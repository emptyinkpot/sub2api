# API Contract

This document is a compact contract map for consumers and automation. It is not a full OpenAPI specification yet.

## Base URLs

| Surface | Base URL |
| --- | --- |
| Public UI/API | `https://sub2api.tengokukk.com/` |
| OpenAI-compatible gateway | `https://sub2api.tengokukk.com/v1` |
| Admin/User API prefix | `https://sub2api.tengokukk.com/api/v1` |
| Internal app target | `http://127.0.0.1:8080` |

## Health

```http
GET /health
```

Expected successful body:

```json
{"status":"ok"}
```

Use `GET`, not `HEAD`, for health checks.

## Client Gateway

Clients authenticate with Sub2API-issued keys:

```http
Authorization: Bearer <sub2api-issued-key>
Content-Type: application/json
```

OpenAI-compatible endpoints currently documented for consumers:

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/v1/chat/completions` | Chat completions compatibility |
| `POST` | `/v1/responses` | Responses API compatibility |
| `POST` | `/v1/embeddings` | Hosted embeddings for vector retrieval |
| `POST` | `/v1/images/generations` | Image generation compatibility |
| `POST` | `/v1/images/edits` | Image edit compatibility |

## User API Key Management

The web UI uses these routes after normal user authentication:

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/v1/keys` | List current user's API keys |
| `POST` | `/api/v1/keys` | Create client API key |
| `GET` | `/api/v1/keys/:id` | Get key detail |
| `PUT` | `/api/v1/keys/:id` | Update key |
| `DELETE` | `/api/v1/keys/:id` | Delete key |
| `GET` | `/api/v1/groups/available` | List groups the current user may bind |
| `GET` | `/api/v1/groups/rates` | Get user-specific group rates |

Create key payload shape:

```json
{
  "name": "mortis-coze-native",
  "group_id": 123,
  "quota": 0,
  "expires_in_days": 0,
  "ip_whitelist": [],
  "ip_blacklist": []
}
```

## Admin Provider Catalog

Canonical upstream vendor presets for API-key accounts (no secrets):

```http
GET /api/v1/admin/provider-catalog
```

See `docs/runtime/provider-catalog.md` and `backend/internal/domain/provider_catalog.go`.

## Admin Group Management

Admin routes require admin authentication.

Group `platform` values: `anthropic`, `openai`, `glm`, `coze`, `gemini`, `antigravity`.

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/v1/admin/groups` | Paginated group list |
| `GET` | `/api/v1/admin/groups/all` | Active groups without pagination |
| `POST` | `/api/v1/admin/groups` | Create group |
| `PUT` | `/api/v1/admin/groups/:id` | Update group |
| `DELETE` | `/api/v1/admin/groups/:id` | Delete group |
| `GET` | `/api/v1/admin/groups/:id/api-keys` | List keys bound to group |
| `GET` | `/api/v1/admin/groups/capacity-summary` | Capacity summary |

## Admin Account Management

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/v1/admin/accounts` | Paginated upstream account list |
| `POST` | `/api/v1/admin/accounts` | Create upstream account |
| `PUT` | `/api/v1/admin/accounts/:id` | Update upstream account |
| `DELETE` | `/api/v1/admin/accounts/:id` | Delete upstream account |
| `POST` | `/api/v1/admin/accounts/:id/test` | Test account connectivity |
| `POST` | `/api/v1/admin/accounts/:id/clear-error` | Clear stale account error |
| `POST` | `/api/v1/admin/accounts/data` | Import account/proxy bundle |
| `GET` | `/api/v1/admin/accounts/data` | Export account/proxy bundle |

## Admin Proxy Management

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/v1/admin/proxies` | Paginated proxy list |
| `GET` | `/api/v1/admin/proxies/all` | Active proxies |
| `GET` | `/api/v1/admin/proxies/risk-summary` | Exit-IP quality/risk summary |
| `POST` | `/api/v1/admin/proxies` | Create proxy |
| `PUT` | `/api/v1/admin/proxies/:id` | Update proxy |
| `DELETE` | `/api/v1/admin/proxies/:id` | Delete proxy |
| `POST` | `/api/v1/admin/proxies/:id/test` | Test proxy connectivity |
| `POST` | `/api/v1/admin/proxies/:id/quality-check` | Check proxy quality against AI targets |
| `GET` | `/api/v1/admin/proxies/:id/accounts` | Accounts using proxy |

## Consumer Defaults

Mortis / Telegram / n8n:

```env
OPENAI_BASE_URL=https://sub2api.tengokukk.com/v1
OPENAI_API_KEY=<sub2api-issued-key>
OPENAI_MODEL=coze-shell
```

FuckVideo hosted embeddings:

```env
MATERIAL_EMBEDDING_BACKEND=openai-compatible
MATERIAL_EMBEDDING_API_BASE_URL=https://sub2api.tengokukk.com/v1
MATERIAL_EMBEDDING_API_MODEL=<embedding-model-exposed-by-sub2api>
MATERIAL_EMBEDDING_API_KEY_ENV=SUB2API_API_KEY
SUB2API_API_KEY=<sub2api-issued-key>
```

## Next Step

The next quality step is to generate a formal OpenAPI document from backend route definitions or maintain one manually under `docs/openapi/`.
