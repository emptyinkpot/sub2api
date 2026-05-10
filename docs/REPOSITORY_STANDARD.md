# Repository Standard

This document defines what makes this fork a maintainable production repository.

## Current GitHub Facts

| Field | Value |
| --- | --- |
| GitHub repository | `emptyinkpot/sub2api` |
| Upstream repository | `Wei-Shaw/sub2api` |
| Fork status | Public GitHub fork |
| Default branch | `main` |
| License | LGPL-3.0 |
| Primary runtime | Go backend, Vue frontend, PostgreSQL, Redis |
| Production gateway | `https://sub2api.tengokukk.com/v1` |

## Documentation Map

| Document | Purpose |
| --- | --- |
| `README.md` | Human entry, positioning, runtime card, quick production connection facts |
| `project.json` | Machine-readable repo/runtime contract |
| `docs/runtime/production-runbook.md` | Production deployment, ports, keys, accounts, groups, Mortis alignment |
| `docs/runtime/coze-provider-consolidation.md` | Coze routing truth and retired adapter policy |
| `CONTRIBUTING.md` | Change rules and PR expectations |
| `SECURITY.md` | Secret policy, reporting, rotation response |
| `SUPPORT.md` | Troubleshooting intake and support boundaries |

## Quality Gates

Expected gates for material changes:

- `git diff --check`
- Backend tests relevant to touched packages
- Frontend typecheck/tests for UI changes
- `project.json` parses as valid JSON when modified
- No plaintext secrets in tracked files
- Runtime docs updated when endpoints, ports, groups, accounts, or consumers change

## Production Contract

Sub2API is the upstream AI gateway. It owns:

- provider credentials
- account pools
- group routing
- client API keys
- quota and usage records
- OpenAI-compatible endpoint exposure

Consumers own their application logic and should not carry raw provider secrets. Mortis, Telegram, n8n and FuckVideo should use:

```text
https://sub2api.tengokukk.com/v1
Authorization: Bearer <sub2api-issued-key>
```

## Repository Hygiene

A high-quality repository keeps these boundaries explicit:

- Source code and docs in Git.
- Secrets in secret stores or runtime env files.
- Runtime state in the server runtime root.
- Large artifacts and generated outputs outside Git.
- Fork-local production facts separate from upstream product claims.

## Recommended Next Improvements

- Add repository topics on GitHub such as `ai-gateway`, `openai-compatible`, `go`, `vue`, `postgresql`, `redis`.
- Add branch protection requiring CI and security scan before merging.
- Keep a short `CHANGELOG.md` for fork-local operational changes.
- Add release notes when deployment behavior changes.
- Keep issue and PR templates focused on sanitized reproduction evidence.
