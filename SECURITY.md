# Security Policy

## Supported Surface

This fork documents and operates the `emptyinkpot/sub2api` deployment. Upstream product security issues may also need to be reported to `Wei-Shaw/sub2api` when the vulnerability is not fork-specific.

Current production surface:

- Public UI/API: `https://sub2api.tengokukk.com/`
- OpenAI-compatible client base URL: `https://sub2api.tengokukk.com/v1`
- Health check: `https://sub2api.tengokukk.com/health`
- Internal app target: `http://127.0.0.1:8080` behind nginx

## Secret Handling

Never commit:

- Sub2API client API keys
- GLM/OpenAI/Coze/Anthropic/Gemini provider keys
- OAuth access tokens, refresh tokens, id tokens, callback URLs containing tokens
- Cookies, private keys, database passwords, PostgreSQL dumps, Redis dumps
- Screenshots or logs containing live credentials

Allowed in Git:

- Placeholder examples such as `<sub2api-issued-key>`
- Public domains and non-secret ports
- Non-secret route, group, account and deployment procedures
- Machine-readable metadata in `project.json`

## Consumer Boundary

Mortis, Telegram, n8n, FuckVideo and similar consumers must receive Sub2API-issued keys only. They must not be configured with raw provider credentials unless there is a deliberate, documented exception.

## Reporting

For this fork, report privately to the repository owner/operator rather than opening a public issue with exploit details or secrets.

Include:

- Affected endpoint or component
- Impact
- Reproduction steps using placeholders
- Whether the issue is fork-local or likely inherited from upstream
- Any logs with credentials redacted

## Operational Response

For leaked Sub2API keys:

1. Disable or rotate the affected key in the Sub2API console.
2. Check usage logs for the affected key and group.
3. Rotate downstream consumer environment variables.
4. Confirm consumers call `https://sub2api.tengokukk.com/v1`.

For leaked provider keys:

1. Revoke or rotate at the provider.
2. Update the Sub2API upstream account credential.
3. Test the account.
4. Clear stale account error state if needed.
5. Review whether any downstream consumer was incorrectly holding provider credentials.
