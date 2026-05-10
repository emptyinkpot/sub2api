# Contributing

This repository is a public fork of `Wei-Shaw/sub2api` with local production operations for `emptyinkpot/sub2api`.

## Repository Role

Sub2API is an AI API gateway with account pools, API keys, quota, billing, routing and operational visibility.

It is not the source repository for downstream consumers such as Mortis, Telegram workflows, n8n, or FuckVideo. Those systems should consume Sub2API through `https://sub2api.tengokukk.com/v1` and Sub2API-issued keys.

## Change Rules

- Keep changes small and scoped by intent.
- Preserve upstream compatibility unless the change is explicitly fork-local.
- Do not commit production secrets, provider keys, OAuth tokens, cookies, database dumps, logs, screenshots containing tokens, or generated deploy output.
- Runtime facts must be reflected in both `README.md` and `project.json` when they are machine-readable contract fields.
- Production deployment, port, key, account and group procedures belong in `docs/runtime/production-runbook.md`.
- Consumer/topology claims must align with the DataBase repository's Mortis and external-consumer model.

## Local Checks

Backend focused checks:

```bash
cd backend
go test ./internal/service ./internal/handler ./internal/server/routes
```

Frontend focused checks:

```bash
cd frontend
pnpm install --frozen-lockfile
pnpm run typecheck
pnpm run test:unit
```

Repository checks:

```bash
git diff --check
```

If a broader package fails because of an unrelated existing issue, document the exact failure in the PR or closeout.

## Commit Style

Use intent-based prefixes:

- `feat:` product behavior
- `fix:` bug fix
- `docs:` documentation, runbooks, repository metadata
- `ops:` deployment or operational automation
- `test:` tests only
- `refactor:` internal restructuring without intended behavior change
- `chore:` maintenance

## Pull Request Expectations

A useful PR states:

- What changed
- Why it changed
- Which user/operator path it affects
- How it was tested
- Whether docs or `project.json` needed updates
- Whether secrets or production values were intentionally excluded

## Fork And Upstream

Current GitHub fork:

- Fork: `https://github.com/emptyinkpot/sub2api`
- Upstream: `https://github.com/Wei-Shaw/sub2api`
- Default branch: `main`
- License: LGPL-3.0

When pulling from upstream, avoid overwriting fork-local production docs unless the runtime facts are being intentionally changed.
