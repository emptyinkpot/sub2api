# Repository Agent Rules

## Repository Hygiene

- This fork should keep `main` as the only maintained personal-development branch unless the operator explicitly requests a temporary branch.
- `upstream/*` references are for synchronizing the original project only. They are not personal development branches and should not be merged wholesale into `main`.
- Do not merge historical snapshot, backup, upstream experiment, or unrelated feature branches into `main` just to reduce branch count.
- Before deleting or merging any branch, tag, config, directory, worktree, or old checkout, verify:
  - default branch
  - local and remote branches
  - whether the branch is already merged
  - unique commits that may contain working functionality
  - CI, deployment, script, README, and `project.json` references
  - tag or commit coverage for rollback
- If safety cannot be proven, stop and report the risk instead of cleaning.

## Coupling And Configuration

- Prefer one canonical source of truth for each runtime fact.
- Do not create duplicate config roots, duplicate runtime owners, fallback paths, or compatibility layers.
- New capability should be visible and callable through a small entrypoint, with model/provider/storage selection exposed through `project.json` or documented environment variables.
- Keep gateway routing, account storage, provider mapping, downstream consumer contracts, deployment, and documentation as separate boundaries.

## Downstream Consumers

- sub2api owns the model gateway, API keys, provider accounts, quotas, routing, and usage records.
- Downstream repositories such as DataBase own their data and domain-specific runtime state.
- Do not store downstream personal data in this repository; document only the consumer contract.
