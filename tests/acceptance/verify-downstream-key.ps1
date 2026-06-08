param(
  [string]$BaseUrl = $env:SUB2API_BASE_URL,
  [string]$ApiKey = $env:SUB2API_CLIENT_KEY,
  [string]$Model = $env:SUB2API_MODEL,
  [switch]$SkipStream,
  [int]$TimeoutSec = 45,
  [string]$SecretEnvDir = $env:SUB2API_CONSUMER_SECRET_DIR,
  [switch]$NoSecretDiscovery
)

$ErrorActionPreference = "Stop"

if (-not $BaseUrl) {
  $BaseUrl = "https://sub2api.tengokukk.com/v1"
}
$ModelExplicit = $PSBoundParameters.ContainsKey("Model") -or -not [string]::IsNullOrWhiteSpace($env:SUB2API_MODEL)

function Read-EnvFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  $values = @{}
  foreach ($line in Get-Content -Path $Path -ErrorAction Stop) {
    if ($line -notmatch '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$') {
      continue
    }
    $name = $Matches[1]
    $value = $Matches[2].Trim()
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    $values[$name] = $value
  }
  return $values
}

function Mask-Key {
  param([string]$Key)
  if (-not $Key) { return "" }
  if ($Key.Length -le 12) { return "***" }
  return "$($Key.Substring(0, 6))...$($Key.Substring($Key.Length - 4))"
}

function New-Candidate {
  param(
    [Parameter(Mandatory = $true)][string]$Key,
    [string]$CandidateBaseUrl,
    [string]$CandidateModel,
    [string]$Source,
    [string]$KeyId,
    [string]$GroupId,
    [string]$GroupName
  )
  if (-not $Key -or $Key -match '^<.*>$') { return $null }
  $resolvedBaseUrl = $BaseUrl
  if ($CandidateBaseUrl) {
    $resolvedBaseUrl = $CandidateBaseUrl
  }
  $resolvedModel = $null
  if ($CandidateModel) {
    $resolvedModel = $CandidateModel
  }
  if ($ModelExplicit) {
    $resolvedModel = $Model
  }
  if (-not $resolvedModel) {
    $resolvedModel = "claude-sonnet-4-6"
  }
  [ordered]@{
    apiKey = $Key
    baseUrl = $resolvedBaseUrl
    model = $resolvedModel
    source = $Source
    keyId = $KeyId
    groupId = $GroupId
    groupName = $GroupName
  }
}

function Resolve-KeyCandidates {
  $items = New-Object System.Collections.Generic.List[object]
  if ($ApiKey) {
    $items.Add((New-Candidate -Key $ApiKey -CandidateBaseUrl $BaseUrl -CandidateModel $Model -Source "parameter/env:SUB2API_CLIENT_KEY"))
    return $items
  }

  if ($NoSecretDiscovery) {
    return $items
  }

  $dirs = New-Object System.Collections.Generic.List[string]
  if ($SecretEnvDir) { $dirs.Add($SecretEnvDir) }
  if ($env:USERPROFILE) {
    $dirs.Add((Join-Path $env:USERPROFILE ".codex-secrets\sub2api\consumers"))
  }

  $seenFiles = New-Object System.Collections.Generic.HashSet[string]
  foreach ($dir in $dirs) {
    if (-not $dir -or -not (Test-Path $dir)) { continue }
    foreach ($file in Get-ChildItem -Path $dir -Filter "*.env" -File -ErrorAction SilentlyContinue) {
      if (-not $seenFiles.Add($file.FullName)) { continue }
      $vars = Read-EnvFile -Path $file.FullName
      foreach ($name in $vars.Keys) {
        if ($name -notmatch '^SUB2API_(.+)_API_KEY$' -and $name -notmatch '^SUB2API_CLIENT_KEY$') {
          continue
        }
        $prefix = if ($name -eq "SUB2API_CLIENT_KEY") { "SUB2API" } else { "SUB2API_$($Matches[1])" }
        $candidate = New-Candidate `
          -Key $vars[$name] `
          -CandidateBaseUrl $vars["${prefix}_BASE_URL"] `
          -CandidateModel $vars["${prefix}_MODEL"] `
          -Source "$($file.FullName):$name" `
          -KeyId $vars["${prefix}_KEY_ID"] `
          -GroupId $vars["${prefix}_GROUP_ID"] `
          -GroupName $vars["${prefix}_GROUP_NAME"]
        if ($candidate) { $items.Add($candidate) }
      }
    }
  }
  return $items
}

function Invoke-HttpPost {
  param(
    [Parameter(Mandatory = $true)][string]$Uri,
    [Parameter(Mandatory = $true)][string]$ApiKey,
    [Parameter(Mandatory = $true)][string]$Body,
    [Parameter(Mandatory = $true)][bool]$Stream
  )

  Add-Type -AssemblyName System.Net.Http
  $client = [System.Net.Http.HttpClient]::new()
  $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
  $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, $Uri)
  $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $ApiKey)
  if ($Stream) {
    $request.Headers.Accept.Add([System.Net.Http.Headers.MediaTypeWithQualityHeaderValue]::new("text/event-stream"))
  }
  $request.Content = [System.Net.Http.StringContent]::new($Body, [System.Text.Encoding]::UTF8, "application/json")

  try {
    $response = $client.SendAsync($request).GetAwaiter().GetResult()
    $text = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    return [ordered]@{
      statusCode = [int]$response.StatusCode
      text = $text
    }
  } finally {
    if ($request) { $request.Dispose() }
    if ($client) { $client.Dispose() }
  }
}

function Read-StreamAssistantContent {
  param([Parameter(Mandatory = $true)][string]$Text)

  $frames = [regex]::Matches($Text, "(?m)^data:\s*(.+?)\s*$")
  $parts = New-Object System.Collections.Generic.List[string]
  foreach ($frame in $frames) {
    $payload = $frame.Groups[1].Value.Trim()
    if (-not $payload -or $payload -eq "[DONE]") {
      continue
    }
    try {
      $json = $payload | ConvertFrom-Json -ErrorAction Stop
      $piece = ""
      if ($json.choices -and $json.choices.Count -gt 0) {
        $choice = $json.choices[0]
        if ($choice.delta -and $choice.delta.content) {
          $piece = [string]$choice.delta.content
        } elseif ($choice.message -and $choice.message.content) {
          $piece = [string]$choice.message.content
        }
      }
      if (-not $piece -and $json.content) {
        $piece = [string]$json.content
      }
      if ($piece) {
        $parts.Add($piece)
      }
    } catch {
      continue
    }
  }

  [ordered]@{
    frameCount = $frames.Count
    content = (($parts.ToArray()) -join "")
  }
}

function Invoke-ChatCompletion {
  param(
    [Parameter(Mandatory = $true)][object]$Candidate,
    [Parameter(Mandatory = $true)][bool]$Stream
  )
  $base = [string]$Candidate.baseUrl
  $base = $base.TrimEnd("/")
  $candidateModel = [string]$Candidate.model

  $body = @{
    model = $candidateModel
    messages = @(
      @{
        role = "user"
        content = "Reply with exactly: sub2api downstream key ok"
      }
    )
    temperature = 0
    max_tokens = 32
    stream = $Stream
  } | ConvertTo-Json -Depth 8

  try {
    if ($Stream) {
      $raw = Invoke-HttpPost -Uri "$base/chat/completions" -ApiKey $Candidate.apiKey -Body $body -Stream $true
      $text = [string]$raw.text
      if ($raw.statusCode -lt 200 -or $raw.statusCode -ge 300) {
        throw "stream request failed with HTTP $($raw.statusCode): $($text.Substring(0, [Math]::Min(240, $text.Length)))"
      }
      if (-not ($text -match "data:\s*")) {
        throw "stream response did not contain SSE data frames"
      }
      $streamParsed = Read-StreamAssistantContent -Text $text
      $streamContent = [string]$streamParsed.content
      if (-not $streamContent.Trim()) {
        throw "stream response contained $($streamParsed.frameCount) SSE frames but no assistant content"
      }
      if (-not ($text -match "sub2api downstream key ok")) {
        Write-Warning "stream response did not exactly echo the requested phrase; accepting non-empty assistant content for smoke"
      }
      return [ordered]@{
        stream = $true
        content = $streamContent.Trim()
        frameCount = $streamParsed.frameCount
      }
    }

    $raw = Invoke-HttpPost -Uri "$base/chat/completions" -ApiKey $Candidate.apiKey -Body $body -Stream $false
    if ($raw.statusCode -lt 200 -or $raw.statusCode -ge 300) {
      $text = [string]$raw.text
      throw "non-stream request failed with HTTP $($raw.statusCode): $($text.Substring(0, [Math]::Min(240, $text.Length)))"
    }
    $response = ([string]$raw.text) | ConvertFrom-Json
    $content = [string]($response.choices[0].message.content)
    if (-not $content.Trim()) {
      throw "sub2api returned no assistant content for downstream key"
    }
    return [ordered]@{
      stream = $false
      content = $content.Trim()
      usage = $response.usage
    }
  } catch {
    $message = ($_ | Out-String).Trim()
    if ($message -match "No available accounts|no available accounts") {
      throw "Downstream key reached sub2api but no account was schedulable for model $candidateModel"
    }
    throw
  }
}

$candidates = Resolve-KeyCandidates
if (-not $candidates -or $candidates.Count -lt 1) {
  throw "No sub2api downstream key candidate found. Set SUB2API_CLIENT_KEY/-ApiKey or create a consumer env file under .codex-secrets\sub2api\consumers with SUB2API_<NAME>_API_KEY."
}

$attempts = New-Object System.Collections.Generic.List[object]
foreach ($candidate in $candidates) {
  try {
    $nonStreamResult = Invoke-ChatCompletion -Candidate $candidate -Stream:$false
    $streamResult = $null
    if (-not $SkipStream) {
      $streamResult = Invoke-ChatCompletion -Candidate $candidate -Stream:$true
    }
    [ordered]@{
      ok = $true
      baseUrl = ([string]$candidate.baseUrl).TrimEnd("/")
      model = $candidate.model
      source = $candidate.source
      key = Mask-Key -Key $candidate.apiKey
      keyId = $candidate.keyId
      groupId = $candidate.groupId
      groupName = $candidate.groupName
      attemptedCandidates = $attempts.Count + 1
      nonStream = $nonStreamResult
      stream = $streamResult
      keyContract = "sub2api-issued downstream key only"
    } | ConvertTo-Json -Depth 8
    exit 0
  } catch {
    $attempts.Add([ordered]@{
      source = $candidate.source
      key = Mask-Key -Key $candidate.apiKey
      keyId = $candidate.keyId
      groupId = $candidate.groupId
      groupName = $candidate.groupName
      model = $candidate.model
      error = (($_ | Out-String).Trim() -replace [regex]::Escape($candidate.apiKey), (Mask-Key -Key $candidate.apiKey))
    })
  }
}

[ordered]@{
  ok = $false
  candidateCount = $candidates.Count
  attempts = $attempts
  keyContract = "sub2api-issued downstream key only"
} | ConvertTo-Json -Depth 8
throw "No discovered sub2api downstream key passed non-stream/stream acceptance"
