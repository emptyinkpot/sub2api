# Bootstrap ContentMRS consumer on sub2api @ server-170; write local consumer secret.
param(
  [string]$SshHost = 'server-170',
  [string]$DashScopeEnvFile = '',
  [string]$AdminPassword = $(if ($env:SUB2API_ADMIN_PASSWORD) { $env:SUB2API_ADMIN_PASSWORD } else { 'ContentMRS-Novel-Admin-2026!' }),
  [string]$Sub2ApiModel = $(if ($env:CONTENTBASE_DEFAULT_MODEL) { $env:CONTENTBASE_DEFAULT_MODEL } else { 'qwen-plus' }),
  [switch]$Sync124,
  [switch]$Skip124
)
$ErrorActionPreference = 'Stop'
$opsRoot = $PSScriptRoot
$sub2apiRoot = Split-Path (Split-Path $opsRoot -Parent) -Parent
$mrsScripts = Join-Path (Split-Path $sub2apiRoot -Parent) 'ContentMRS\scripts'

function Read-DotEnvMap([string]$path) {
  $map = @{}
  if (-not (Test-Path -LiteralPath $path)) { return $map }
  Get-Content -LiteralPath $path | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
      $map[$Matches[1].Trim()] = $Matches[2].Trim()
    }
  }
  $map
}

function Resolve-DashScopeKey {
  if ($env:DASHSCOPE_API_KEY) { return $env:DASHSCOPE_API_KEY.Trim() }
  $candidates = @(
    $DashScopeEnvFile,
    (Join-Path $env:USERPROFILE '.codex-secrets\dashscope\api.env')
  ) | Where-Object { $_ } | Select-Object -Unique
  foreach ($file in $candidates) {
    if (-not (Test-Path -LiteralPath $file)) { continue }
    $map = Read-DotEnvMap $file
    $key = [string]($map.DASHSCOPE_API_KEY ?? '').Trim()
    if ($key) { return $key }
  }
  throw 'DASHSCOPE_API_KEY not found'
}

$dashKey = Resolve-DashScopeKey
$remoteEnv = Join-Path $env:TEMP 'sub2api-bootstrap-remote.env'
$remoteEnvBody = @(
  'ADMIN_EMAIL=admin@sub2api.local'
  "SUB2API_ADMIN_PASSWORD=$AdminPassword"
  "DASHSCOPE_API_KEY=$dashKey"
  "CONTENTBASE_DEFAULT_MODEL=$Sub2ApiModel"
) -join "`n"
[System.IO.File]::WriteAllText($remoteEnv, "$remoteEnvBody`n", [Text.UTF8Encoding]::new($false))
scp $remoteEnv "${SshHost}:/tmp/sub2api-bootstrap-remote.env" | Out-Host

$remoteCmd = (@'
set -e
cd /srv/sub2api
set -a && . /tmp/sub2api-bootstrap-remote.env && set +a
trap 'rm -f /tmp/sub2api-bootstrap-remote.env' EXIT
node deploy/ops/bootstrap-contentmrs.mjs
'@).Replace("`r`n", "`n")
$out = ssh $SshHost $remoteCmd
Write-Host $out
$result = $out | ConvertFrom-Json
if (-not $result.ok) { throw "sub2api bootstrap failed: $out" }

$remoteSecret = if ($result.envPath) { [string]$result.envPath } else { '~/.codex-secrets/sub2api/consumers/contentmrs-novel.env' }
$localCanonical = Join-Path $env:USERPROFILE '.codex-secrets\sub2api\consumers\contentmrs-novel.env'
New-Item -ItemType Directory -Path (Split-Path $localCanonical -Parent) -Force | Out-Null
scp "${SshHost}:$remoteSecret" $localCanonical | Out-Host
Write-Host "OK local $localCanonical"

if (-not $Skip124 -and (Test-Path (Join-Path $mrsScripts 'sync-production-secrets-124.ps1'))) {
  & (Join-Path $mrsScripts 'sync-production-secrets-124.ps1') -Sub2ApiModel $Sub2ApiModel
}

Write-Host "DONE model=$Sub2ApiModel group=$($result.groupId)"
