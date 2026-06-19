param(
  [string]$BaseUrl = $(if ($env:SUB2API_TEST_BASE_URL) { $env:SUB2API_TEST_BASE_URL } else { "https://sub2api.tengokukk.com" }),
  [string]$SshHost = $(if ($env:SUB2API_DEPLOY_SSH_HOST) { $env:SUB2API_DEPLOY_SSH_HOST } else { "server-170" }),
  [string]$RemoteRepoRoot = $(if ($env:SUB2API_REMOTE_ROOT) { $env:SUB2API_REMOTE_ROOT } else { "/srv/sub2api" }),
  [string]$RemoteGitRemote = $(if ($env:SUB2API_REMOTE_GIT_REMOTE) { $env:SUB2API_REMOTE_GIT_REMOTE } else { "git@github.com-sub2api-deploy:emptyinkpot/sub2api.git" }),
  [string]$ContainerName = $(if ($env:SUB2API_CONTAINER_NAME) { $env:SUB2API_CONTAINER_NAME } else { "sub2api" }),
  [string]$DockerNetwork = $(if ($env:SUB2API_DOCKER_NETWORK) { $env:SUB2API_DOCKER_NETWORK } else { "sub2api-network" }),
  [string]$RemoteDataDir = $(if ($env:SUB2API_REMOTE_DATA_DIR) { $env:SUB2API_REMOTE_DATA_DIR } else { "/srv/sub2api/deploy/data" }),
  [string]$ImageRepository = $(if ($env:SUB2API_IMAGE_REPOSITORY) { $env:SUB2API_IMAGE_REPOSITORY } else { "sub2api" }),
  [string]$BindHost = $(if ($env:SUB2API_BIND_HOST) { $env:SUB2API_BIND_HOST } else { "0.0.0.0" }),
  [int]$HostPort = $(if ($env:SUB2API_HOST_PORT) { [int]$env:SUB2API_HOST_PORT } else { 8080 }),
  [string]$CommitMessage = "chore(sub2api): manual deployment acceptance",
  [int]$TimeoutSec = 60,
  [int]$DeployTimeoutSec = 600,
  [int]$DeployPollIntervalSec = 5,
  [string]$CcswitchDataRoot = $(if ($env:CCSWITCH_DATA_ROOT) { $env:CCSWITCH_DATA_ROOT } else { Join-Path $HOME ".cc-switch" }),
  [switch]$AllowNoChanges,
  [switch]$SkipLocalChecks
)

# tests/run.ps1 is the single push -> manual SSH deploy -> release check entrypoint.
# It delegates business checks to scripts/check.sh instead of duplicating smoke/audit logic.

$ErrorActionPreference = "Stop"

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $Utf8NoBom
[Console]::InputEncoding = $Utf8NoBom
$OutputEncoding = $Utf8NoBom

$RequiredReleaseCheckMode = "full"
$RequiredReleaseChecks = @(
  [pscustomobject]@{
    Name = "smoke"
    Pattern = "run_module smoke.sh --full"
    Coverage = "health, auth, downstream model list, downstream chat, stream, admin stats"
  },
  [pscustomobject]@{
    Name = "downstream-keys"
    Pattern = "run_module audit-keys.sh"
    Coverage = "all usable downstream consumer keys through server-side real gateway tests"
  },
  [pscustomobject]@{
    Name = "downstream-models"
    Pattern = "run_module audit-models.sh"
    Coverage = "every exposed downstream model for usable consumer keys"
  },
  [pscustomobject]@{
    Name = "upstream-accounts"
    Pattern = "run_module audit-upstream.sh"
    Coverage = "real upstream account/provider tests"
  },
  [pscustomobject]@{
    Name = "routing"
    Pattern = "run_module audit-routing.sh"
    Coverage = "downstream key groups have schedulable upstream accounts"
  }
)

function Write-Step {
  param([string]$Message)
  Write-Host "[sub2api-tests] $Message"
}

function Get-RepoRoot {
  $root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
  return $root
}

function Invoke-External {
  param(
    [string]$FilePath,
    [string[]]$ArgumentList,
    [string]$WorkingDirectory = (Get-RepoRoot)
  )
  $oldLocation = Get-Location
  try {
    Set-Location -LiteralPath $WorkingDirectory
    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
      throw "$FilePath $($ArgumentList -join ' ') failed with exit code $LASTEXITCODE"
    }
  } finally {
    Set-Location $oldLocation
  }
}

function Invoke-Git {
  param(
    [string[]]$GitArgs,
    [string]$RepoRoot = (Get-RepoRoot)
  )
  if (-not $GitArgs -or $GitArgs.Count -eq 0) {
    throw "Invoke-Git requires GitArgs"
  }
  $oldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = & git -C $RepoRoot @GitArgs 2>&1
  } finally {
    $ErrorActionPreference = $oldErrorActionPreference
  }
  if ($LASTEXITCODE -ne 0) {
    throw "git -C $RepoRoot $($GitArgs -join ' ') failed: $output"
  }
  return ($output | Out-String).Trim()
}

function Get-GitHead {
  param([string]$RepoRoot = (Get-RepoRoot))
  return (Invoke-Git -GitArgs @("rev-parse", "HEAD") -RepoRoot $RepoRoot).Trim()
}

function Get-GitBranch {
  param([string]$RepoRoot = (Get-RepoRoot))
  return (Invoke-Git -GitArgs @("branch", "--show-current") -RepoRoot $RepoRoot).Trim()
}

function Get-GitStatusShort {
  param([string]$RepoRoot = (Get-RepoRoot))
  return (Invoke-Git -GitArgs @("status", "--short") -RepoRoot $RepoRoot).Trim()
}

function ConvertTo-BashSingleQuoted {
  param([string]$Value)
  if ($Value -match "'") {
    throw "single quote is not allowed in bash parameter values: $Value"
  }
  return "'" + $Value + "'"
}

function Resolve-BaseUrl {
  if (-not $BaseUrl) {
    throw "BaseUrl is required. Pass -BaseUrl https://sub2api.example.com or set SUB2API_TEST_BASE_URL."
  }
  return $BaseUrl.Trim().TrimEnd("/")
}

function Resolve-Bash {
  if ($env:SUB2API_BASH) {
    if (-not (Test-Path -LiteralPath $env:SUB2API_BASH)) {
      throw "SUB2API_BASH points to a missing file: $env:SUB2API_BASH"
    }
    return $env:SUB2API_BASH
  }
  $cmd = Get-Command bash -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "bash is required to run scripts/check.sh. Install Git Bash or set SUB2API_BASH."
  }
  return $cmd.Source
}

function Resolve-Python {
  $cmd = Get-Command python -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "python is required to audit the local CC Switch SQLite store. Install Python or make python available on PATH."
  }
  return $cmd.Source
}

function Invoke-LocalChecks {
  param([string]$RepoRoot)
  if ($SkipLocalChecks) {
    Write-Step "skipping local checks by request"
    return
  }

  Write-Step "checking project.json"
  $projectPath = Join-Path $RepoRoot "project.json"
  [void]([IO.File]::ReadAllText($projectPath, $Utf8NoBom) | ConvertFrom-Json)

  Write-Step "checking whitespace"
  Invoke-Git -GitArgs @("diff", "--check") -RepoRoot $RepoRoot | Out-Null

  $backendRoot = Join-Path $RepoRoot "backend"
  if (Test-Path -LiteralPath (Join-Path $backendRoot "go.mod")) {
    Write-Step "running focused backend unit checks"
    Invoke-External -FilePath "go" -ArgumentList @("test", "-tags", "unit", "./internal/service", "./internal/handler/admin", "-run", "Test.*Account|Test.*ImportData|Test.*MixedChannel") -WorkingDirectory $backendRoot
  }
}

function Assert-ReleaseAcceptanceCoverage {
  param([string]$RepoRoot)
  if ($env:SUB2API_CHECK_MODE -and $env:SUB2API_CHECK_MODE -ne $RequiredReleaseCheckMode) {
    throw "tests/run.ps1 is the deploy acceptance entrypoint and always runs full upstream/downstream checks; remove SUB2API_CHECK_MODE=$($env:SUB2API_CHECK_MODE)."
  }

  $checkEntry = Join-Path $RepoRoot "scripts/check.sh"
  if (-not (Test-Path -LiteralPath $checkEntry)) {
    throw "release check owner is missing: $checkEntry"
  }

  $checkSource = [IO.File]::ReadAllText($checkEntry, $Utf8NoBom)
  foreach ($check in $RequiredReleaseChecks) {
    if (-not $checkSource.Contains($check.Pattern)) {
      throw "scripts/check.sh --full no longer invokes required release check '$($check.Name)' with pattern '$($check.Pattern)'."
    }
  }
}

function Format-ReleaseCoverage {
  return (($RequiredReleaseChecks | ForEach-Object { "$($_.Name): $($_.Coverage)" }) -join "; ")
}

function Publish-CurrentRepo {
  param([string]$RepoRoot)
  $branch = Get-GitBranch -RepoRoot $RepoRoot
  if (-not $branch) {
    throw "cannot deploy from detached HEAD; checkout a branch first"
  }

  $status = Get-GitStatusShort -RepoRoot $RepoRoot
  if ($status) {
    Write-Step "staging local changes"
    Invoke-Git -GitArgs @("add", "-A") -RepoRoot $RepoRoot | Out-Null

    $commitBody = @(
      "target: sub2api manual deployment acceptance",
      "owner: tests/run.ps1",
      "patch: auto-stage current repository changes",
      $(if ($SkipLocalChecks) { "test-not-run: -SkipLocalChecks" } else { "validate: project.json parse, git diff --check, release coverage assertion, focused backend unit checks" })
    )
    $args = @("commit", "-m", $CommitMessage)
    foreach ($line in $commitBody) {
      $args += @("-m", $line)
    }
    Write-Step "committing local changes"
    Invoke-Git -GitArgs $args -RepoRoot $RepoRoot | Out-Null
  } elseif (-not $AllowNoChanges) {
    Write-Step "no local changes; creating empty deployment marker commit"
    Invoke-Git -GitArgs @(
      "commit",
      "--allow-empty",
      "-m", "chore(sub2api): manual deployment marker",
      "-m", "target: sub2api manual deployment acceptance",
      "-m", "owner: tests/run.ps1",
      "-m", "patch: empty manual deployment marker",
      "-m", $(if ($SkipLocalChecks) { "test-not-run: -SkipLocalChecks" } else { "validate: project.json parse, git diff --check, release coverage assertion, focused backend unit checks" })
    ) -RepoRoot $RepoRoot | Out-Null
  } else {
    Write-Step "no local changes; deploying current HEAD without an empty commit"
  }

  $head = Get-GitHead -RepoRoot $RepoRoot
  Write-Step "pushing $branch at $head"
  Invoke-Git -GitArgs @("push", "origin", $branch) -RepoRoot $RepoRoot | Out-Null

  $remoteHead = (Invoke-Git -GitArgs @("ls-remote", "origin", "refs/heads/$branch") -RepoRoot $RepoRoot).Split("`t")[0].Trim()
  if ($remoteHead -ne $head) {
    throw "remote readback mismatch: local=$head remote=$remoteHead"
  }
  Write-Step "remote readback ok: $remoteHead"
  return $head
}

function Invoke-RemoteScript {
  param(
    [string]$Script,
    [string]$Label
  )
  Write-Step "running remote $Label on $SshHost"
  $oldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = $Script | & ssh $SshHost "bash -s" 2>&1
  } finally {
    $ErrorActionPreference = $oldErrorActionPreference
  }
  if ($LASTEXITCODE -ne 0) {
    throw "remote $Label failed on $SshHost`: $($output | Out-String)"
  }
  $text = ($output | Out-String).Trim()
  if ($text) { Write-Step $text }
}

function Deploy-Sub2ApiRemote {
  param([string]$TargetCommit)
  if (-not $TargetCommit) { throw "Deploy-Sub2ApiRemote requires TargetCommit" }

  $script = @"
set -euo pipefail
TARGET_COMMIT=$(ConvertTo-BashSingleQuoted $TargetCommit)
REMOTE_REPO_ROOT=$(ConvertTo-BashSingleQuoted $RemoteRepoRoot)
REMOTE_GIT_REMOTE=$(ConvertTo-BashSingleQuoted $RemoteGitRemote)
CONTAINER_NAME=$(ConvertTo-BashSingleQuoted $ContainerName)
DOCKER_NETWORK=$(ConvertTo-BashSingleQuoted $DockerNetwork)
REMOTE_DATA_DIR=$(ConvertTo-BashSingleQuoted $RemoteDataDir)
IMAGE_REPOSITORY=$(ConvertTo-BashSingleQuoted $ImageRepository)
BIND_HOST=$(ConvertTo-BashSingleQuoted $BindHost)
HOST_PORT=$(ConvertTo-BashSingleQuoted ([string]$HostPort))
DEPLOY_TIMEOUT_SEC=$(ConvertTo-BashSingleQuoted ([string]$DeployTimeoutSec))
DEPLOY_POLL_INTERVAL_SEC=$(ConvertTo-BashSingleQuoted ([string]$DeployPollIntervalSec))
"@ + @'

command -v git >/dev/null
command -v curl >/dev/null
sudo -n docker version >/dev/null

if [ -d "$REMOTE_REPO_ROOT/.git" ]; then
  cd "$REMOTE_REPO_ROOT"
  git remote set-url origin "$REMOTE_GIT_REMOTE"
else
  if [ -e "$REMOTE_REPO_ROOT" ]; then
    backup="${REMOTE_REPO_ROOT}.backup.$(date +%Y%m%d%H%M%S)"
    mv "$REMOTE_REPO_ROOT" "$backup"
    echo "moved-existing-root=$backup"
  fi
  mkdir -p "$(dirname "$REMOTE_REPO_ROOT")"
  git clone "$REMOTE_GIT_REMOTE" "$REMOTE_REPO_ROOT"
  cd "$REMOTE_REPO_ROOT"
fi

git fetch origin --prune
git cat-file -e "${TARGET_COMMIT}^{commit}"
git reset --hard "$TARGET_COMMIT"
git clean -fdx \
  -e .env \
  -e backups \
  -e backups/ \
  -e deploy/.env \
  -e deploy/data \
  -e deploy/postgres_data \
  -e deploy/redis_data \
  -e mcp/.env \
  -e mcp/patrol_state.json

if ! sudo -n docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  echo "existing container $CONTAINER_NAME is required so deployment can preserve production env" >&2
  exit 31
fi

sudo -n docker network inspect "$DOCKER_NETWORK" >/dev/null
mkdir -p "$REMOTE_DATA_DIR"

image_tag="${IMAGE_REPOSITORY}:${TARGET_COMMIT}"
echo "building-image=$image_tag"
sudo -n docker build \
  --target final \
  --build-arg "SOURCE_COMMIT=${TARGET_COMMIT}" \
  --build-arg "COMMIT=${TARGET_COMMIT}" \
  -t "$image_tag" \
  -t "${IMAGE_REPOSITORY}:manual" \
  .

tmp_env="$(mktemp)"
cleanup() {
  rm -f "$tmp_env"
}
trap cleanup EXIT

sudo -n docker inspect "$CONTAINER_NAME" --format '{{range .Config.Env}}{{println .}}{{end}}' \
  | sed '/^PATH=/d;/^HOSTNAME=/d;/^HOME=/d;/^SOURCE_COMMIT=/d' > "$tmp_env"

sudo -n docker rm -f "$CONTAINER_NAME" >/dev/null
sudo -n docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  --ulimit nofile=100000:100000 \
  --network "$DOCKER_NETWORK" \
  -p "${BIND_HOST}:${HOST_PORT}:8080" \
  -v "${REMOTE_DATA_DIR}:/app/data" \
  --env-file "$tmp_env" \
  -e "SOURCE_COMMIT=${TARGET_COMMIT}" \
  "$image_tag" >/dev/null

elapsed=0
while [ "$elapsed" -le "$DEPLOY_TIMEOUT_SEC" ]; do
  if curl -fsS --max-time 10 "http://127.0.0.1:${HOST_PORT}/health" | grep -q '"status"[[:space:]]*:[[:space:]]*"ok"'; then
    echo "remote-health-ok commit=$TARGET_COMMIT image=$image_tag"
    sudo -n docker inspect "$CONTAINER_NAME" --format 'container={{.Name}} image={{.Config.Image}} status={{.State.Status}}'
    exit 0
  fi
  sleep "$DEPLOY_POLL_INTERVAL_SEC"
  elapsed=$((elapsed + DEPLOY_POLL_INTERVAL_SEC))
done

sudo -n docker logs --tail 120 "$CONTAINER_NAME" >&2 || true
echo "remote health did not become ok within ${DEPLOY_TIMEOUT_SEC}s" >&2
exit 32
'@

  Invoke-RemoteScript -Script $script -Label "Sub2API manual deploy"
}

function Invoke-ReleaseAcceptance {
  param(
    [string]$RepoRoot,
    [string]$TargetCommit
  )
  $bash = Resolve-Bash
  $resolvedBaseUrl = Resolve-BaseUrl
  $modeArg = "--$RequiredReleaseCheckMode"
  Write-Step "running full release acceptance commit=$TargetCommit baseUrl=$resolvedBaseUrl"
  Write-Step "release coverage: $(Format-ReleaseCoverage)"
  Invoke-External -FilePath $bash -ArgumentList @(
    "scripts/check.sh",
    "--release",
    "--endpoint-only",
    "--base-url", $resolvedBaseUrl,
    "--expect-commit", $TargetCommit,
    $modeArg,
    "--timeout", ([string]$TimeoutSec)
  ) -WorkingDirectory $RepoRoot
}

function Invoke-CcswitchBridgeAudit {
  param([string]$RepoRoot)
  $python = Resolve-Python
  $resolvedBaseUrl = Resolve-BaseUrl
  $script = @'
import json
import re
import sqlite3
import sys
import urllib.request
from pathlib import Path

base_url = sys.argv[1].rstrip("/")
ccswitch_root = Path(sys.argv[2])
timeout_sec = float(sys.argv[3])

settings_path = ccswitch_root / "settings.json"
db_path = ccswitch_root / "cc-switch.db"

if not settings_path.is_file():
    raise SystemExit(f"missing CC Switch settings file: {settings_path}")
if not db_path.is_file():
    raise SystemExit(f"missing CC Switch database: {db_path}")

settings = json.loads(settings_path.read_text(encoding="utf-8"))
conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
conn.row_factory = sqlite3.Row

def request_json(method, path, token=None, body=None):
    data = None
    headers = {"Accept": "application/json"}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(base_url + path, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=timeout_sec) as resp:
        return json.loads(resp.read().decode("utf-8"))

def mask_key(key):
    if not key:
        return ""
    if len(key) <= 12:
        return "***"
    return f"{key[:6]}...{key[-4:]}"

def normalized_url(value):
    return (value or "").rstrip("/")

def load_json(text):
    return json.loads(text or "{}")

def provider_secret(cfg, app_type):
    if app_type == "claude":
        return ((cfg.get("env") or {}).get("ANTHROPIC_AUTH_TOKEN") or "")
    if app_type == "codex":
        return ((cfg.get("auth") or {}).get("OPENAI_API_KEY") or "")
    return ""

def provider_points_to_base(row, cfg, app_type):
    website_url = normalized_url(row["website_url"])
    if website_url == base_url:
        return True
    if app_type == "claude":
        return normalized_url((cfg.get("env") or {}).get("ANTHROPIC_BASE_URL")) == base_url
    if app_type == "codex":
        config_text = cfg.get("config") or ""
        return f'base_url = "{base_url}"' in config_text or f"base_url='{base_url}'" in config_text
    return False

def matching_providers(app_type, platform, masked_keys):
    rows = conn.execute(
        "select id, app_type, name, settings_config, website_url, is_current from providers where app_type=? order by is_current desc, sort_index, created_at",
        (app_type,),
    ).fetchall()
    matches = []
    for row in rows:
        cfg = load_json(row["settings_config"])
        if not provider_points_to_base(row, cfg, app_type):
            continue
        secret = provider_secret(cfg, app_type)
        masked = mask_key(secret)
        matches.append({
            "id": row["id"],
            "name": row["name"],
            "app_type": app_type,
            "platform": platform,
            "is_current": bool(row["is_current"]),
            "masked_key": masked,
            "key_matches_sub2api": masked in masked_keys,
        })
    return matches

bootstrap = request_json("POST", "/api/v1/auth/bootstrap")
token = ((bootstrap.get("data") or {}).get("access_token") or "")
if not token:
    raise SystemExit("sub2api auth/bootstrap did not return an access token")

consumer_keys = request_json("GET", "/api/v1/admin/consumer-keys?limit=200", token=token)
items = ((consumer_keys.get("data") or {}).get("items") or [])
usable = [item for item in items if item.get("usable") is True]

required = [
    {"platform": "anthropic", "app_type": "claude", "label": "Claude"},
    {"platform": "openai", "app_type": "codex", "label": "Codex"},
]

gaps = []
bridge_report = []

for requirement in required:
    platform = requirement["platform"]
    app_type = requirement["app_type"]
    masked_keys = {item.get("masked_key") for item in usable if item.get("platform") == platform}
    masked_keys.discard(None)
    if not masked_keys:
        gaps.append(f"sub2api has no usable downstream key for {requirement['label']} platform={platform}")
        continue
    matches = matching_providers(app_type, platform, masked_keys)
    if not matches:
        gaps.append(f"CC Switch has no {app_type} provider pointing to {base_url}")
    elif not any(match["key_matches_sub2api"] for match in matches):
        gaps.append(f"CC Switch {app_type} provider points to {base_url}, but its key does not match usable sub2api {platform} keys")
    bridge_report.append({
        "label": requirement["label"],
        "platform": platform,
        "app_type": app_type,
        "sub2api_key_count": len(masked_keys),
        "ccswitch_provider_count": len(matches),
        "ccswitch_matching_providers": matches,
    })

current_checks = []
for app_type, setting_key in (("claude", "currentProviderClaude"), ("codex", "currentProviderCodex")):
    current_id = settings.get(setting_key)
    if not current_id:
        gaps.append(f"CC Switch settings missing {setting_key}")
        continue
    row = conn.execute(
        "select id, name, is_current from providers where app_type=? and id=?",
        (app_type, current_id),
    ).fetchone()
    if not row:
        gaps.append(f"CC Switch current provider not found app={app_type} id={current_id}")
        continue
    current_checks.append({
        "app_type": app_type,
        "current_id": current_id,
        "name": row["name"],
        "is_current": bool(row["is_current"]),
    })
    if not row["is_current"]:
        gaps.append(f"CC Switch settings {setting_key}={current_id} exists, but providers.is_current is not set")

report = {
    "status": "failed" if gaps else "passed",
    "ccswitch_root": str(ccswitch_root),
    "base_url": base_url,
    "usable_sub2api_keys": [
        {
            "id": item.get("id"),
            "name": item.get("name"),
            "platform": item.get("platform"),
            "group": item.get("group_name"),
            "masked_key": item.get("masked_key"),
        }
        for item in usable
    ],
    "bridge_report": bridge_report,
    "current_provider_checks": current_checks,
    "gaps": gaps,
}

print(json.dumps(report, ensure_ascii=True, indent=2))
if gaps:
    raise SystemExit(1)
'@

  Write-Step "running local CC Switch bridge audit root=$CcswitchDataRoot baseUrl=$resolvedBaseUrl"
  $oldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = $script | & $python - $resolvedBaseUrl $CcswitchDataRoot ([string]$TimeoutSec) 2>&1
  } finally {
    $ErrorActionPreference = $oldErrorActionPreference
  }
  $text = ($output | Out-String).Trim()
  if ($text) { Write-Step $text }
  if ($LASTEXITCODE -ne 0) {
    throw "local CC Switch bridge audit failed"
  }
}

function Invoke-Sub2ApiAcceptance {
  $repoRoot = Get-RepoRoot
  Write-Step "repo root: $repoRoot"
  Invoke-LocalChecks -RepoRoot $repoRoot
  Assert-ReleaseAcceptanceCoverage -RepoRoot $repoRoot
  $targetCommit = Publish-CurrentRepo -RepoRoot $repoRoot
  Deploy-Sub2ApiRemote -TargetCommit $targetCommit
  Invoke-ReleaseAcceptance -RepoRoot $repoRoot -TargetCommit $targetCommit
  Invoke-CcswitchBridgeAudit -RepoRoot $repoRoot
  Write-Host "SUB2API MANUAL DEPLOYMENT ACCEPTANCE PASS"
  [pscustomobject]@{
    BaseUrl = Resolve-BaseUrl
    Commit = $targetCommit
    SshHost = $SshHost
    RemoteRepoRoot = $RemoteRepoRoot
    ContainerName = $ContainerName
    DockerNetwork = $DockerNetwork
    CheckMode = $RequiredReleaseCheckMode
    ReleaseCoverage = ($RequiredReleaseChecks | ForEach-Object { $_.Name }) -join ","
    CcswitchDataRoot = $CcswitchDataRoot
  } | Format-List
}

Invoke-Sub2ApiAcceptance
