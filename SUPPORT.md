# Support

## What This Repository Supports

This fork supports the local `emptyinkpot/sub2api` production deployment and its documentation:

- `https://sub2api.tengokukk.com/`
- `https://sub2api.tengokukk.com/v1`
- `/srv/sub2api` on `ubuntu@170.106.179.226`
- Mortis / Telegram / n8n / FuckVideo consumer routing through Sub2API-issued keys

## Where To Look First

| Need | Document |
| --- | --- |
| Production endpoint, ports, key usage, account/group setup | `docs/runtime/production-runbook.md` |
| Coze routing and retired adapter policy | `docs/runtime/coze-provider-consolidation.md` |
| Provider runtime dashboard direction | `docs/PROVIDER_RUNTIME_DASHBOARD_CN.md` |
| Payment setup | `docs/PAYMENT_CN.md` |
| Machine-readable repo/runtime facts | `project.json` |

## Before Asking For Help

Collect non-secret evidence:

- Public health result: `curl -i https://sub2api.tengokukk.com/health`
- Consumer base URL
- Model name
- Group name or group ID
- Account name or account ID
- HTTP status and sanitized error body
- Whether the failure is chat, responses, embeddings, account test, billing, or UI

Do not paste live API keys, provider keys, OAuth tokens, cookies, passwords, or screenshots containing secrets.

## Operational Boundaries

- Client-facing API base URL is `https://sub2api.tengokukk.com/v1`.
- Do not expose or rely on `:8080` as a public client endpoint.
- Do not point new consumers at retired Coze adapters or raw provider APIs.
- Consumers should use gateway-issued keys and group routing.
