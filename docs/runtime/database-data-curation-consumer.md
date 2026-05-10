# DataBase Data Curation Consumer

DataBase consumes Sub2API as a replaceable OpenAI-compatible model gateway for
personal data cleaning and labeling.

## Relationship

```text
DataBase
  scripts/curate-knowledge-items.ps1
    -> OpenAI-compatible /v1/chat/completions
    -> Sub2API
    -> GLM or another configured provider/model
```

Sub2API does not own the user's personal database content. It only routes model
requests and manages upstream accounts, quotas, groups, model mappings, and
client API keys.

DataBase owns:

- raw imported notes and documents
- password/account/secret tables
- curation run records
- labels and human decisions

Sub2API owns:

- OpenAI-compatible gateway surface
- API key authentication
- model/provider routing
- upstream credentials and account pools
- usage and quota records

## Default Client Contract

DataBase uses:

```text
POST https://sub2api.tengokukk.com/v1/chat/completions
Authorization: Bearer <sub2api-issued-key>
```

Environment variables on the DataBase side:

```powershell
$env:DATA_CURATION_OPENAI_BASE_URL = "https://sub2api.tengokukk.com/v1"
$env:DATA_CURATION_OPENAI_API_KEY = "<sub2api-issued-key>"
$env:DATA_CURATION_MODEL = "glm-4-flash"
```

The model is replaceable. Any chat model exposed by Sub2API through the
OpenAI-compatible `/v1/chat/completions` endpoint can be used.

## Model Policy

Codex is not the bulk semantic cleaning model.

Codex role:

- maintain scripts
- maintain schemas
- run validations
- inspect failures
- update repository contracts

GLM or another cheap model role:

- classify imported knowledge items
- summarize content
- infer tags
- detect duplicate or low-value records
- flag secret-like content for secret-domain routing

## Data Safety Boundary

Do not write DataBase source records, passwords, cookies, or private imported
content into this repository.

Only document the consumer contract here. Secrets stay in Sub2API runtime
credential storage or the operator's local/remote secret store, not in Git.

## Related DataBase Files

```text
docs/operations/data-cleaning-and-labeling-runtime.md
docs/operations/sub2api-data-curation-consumer.md
scripts/curate-knowledge-items.ps1
scripts/curate_knowledge_items.py
schemas/data-curation/knowledge-label.schema.json
```
