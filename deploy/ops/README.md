# Sub2API Ops Contracts

`deploy/ops` is not a deployment lane. It only keeps declarative consumer
contracts and bootstrap helpers that may be run against an already deployed
Sub2API HTTP endpoint.

## Canonical Deployment

`E:\My Project\sub2api` is the local source of truth and
`https://github.com/emptyinkpot/sub2api` is the delivery surface. Production
must be built by Coolify from the root `Dockerfile`; servers run the finished
Docker image, not a checked-out source tree.

Do not deploy Sub2API by SSH-editing `/srv/sub2api`, rebuilding a host-local
checkout, or restarting a hand-built `sub2api:integration` container. Those
paths are legacy evidence only unless explicitly re-authorized.

## Files

| Path | Purpose |
|------|---------|
| `consumers/*.yaml` | Downstream lane declarations: group, platform, key name, default model |
| `bootstrap-contentmrs.mjs` | Idempotent ContentMRS novel lane bootstrap against an HTTP endpoint |
| `../docs/runtime/provider-catalog.md` | Human-readable provider catalog aligned with backend code |

## Release Acceptance

Use the repository root check entrypoint:

```bash
scripts/check.sh --release --remote-host <host> --coolify-resource-uuid <uuid> --full
```

This validates a finished Coolify image with the remote Coolify application
`.env` and real HTTP checks. `--endpoint-only` is allowed only for temporary
legacy diagnostics and is not release-authoritative.

## ContentMRS Bootstrap

Run this only after the Sub2API app is already deployed and reachable:

```bash
export SUB2API_ADMIN_BASE_URL='https://sub2api.tengokukk.com'
export SUB2API_ADMIN_EMAIL='admin@example.com'
export SUB2API_ADMIN_PASSWORD='...'
node deploy/ops/bootstrap-contentmrs.mjs
```

For production, prefer reading credentials from Coolify secrets or an explicit
`SUB2API_DEPLOY_ENV_FILE`. The script must not assume `/srv/sub2api` is a
source or deployment root.
