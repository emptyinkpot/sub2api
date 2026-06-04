param(
  [string]$BaseUrl = $env:SUB2API_BASE_URL,
  [string]$ApiKey = $env:SUB2API_CLIENT_KEY,
  [string]$Model = $env:SUB2API_MODEL,
  [switch]$SkipStream,
  [int]$TimeoutSec = 45
)

$ErrorActionPreference = "Stop"

if (-not $BaseUrl) {
  $BaseUrl = "https://sub2api.tengokukk.com/v1"
}
if (-not $Model) {
  $Model = "claude-sonnet-4-6"
}
if (-not $ApiKey) {
  throw "SUB2API_CLIENT_KEY or -ApiKey is required. Use a sub2api-issued downstream key, not an upstream provider key."
}

$base = $BaseUrl.TrimEnd("/")

function Invoke-ChatCompletion {
  param(
    [Parameter(Mandatory = $true)][bool]$Stream
  )

  $body = @{
    model = $Model
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
      $raw = Invoke-WebRequest `
        -Method Post `
        -Uri "$base/chat/completions" `
        -Headers @{ Authorization = "Bearer $ApiKey"; "Content-Type" = "application/json"; Accept = "text/event-stream" } `
        -Body $body `
        -TimeoutSec $TimeoutSec
      $text = [string]$raw.Content
      if ($raw.StatusCode -lt 200 -or $raw.StatusCode -ge 300) {
        throw "stream request failed with HTTP $($raw.StatusCode): $($text.Substring(0, [Math]::Min(240, $text.Length)))"
      }
      if (-not ($text -match "data:\s*")) {
        throw "stream response did not contain SSE data frames"
      }
      if (-not ($text -match "sub2api downstream key ok")) {
        throw "stream response did not contain expected assistant text"
      }
      return [ordered]@{
        stream = $true
        content = "sub2api downstream key ok"
        frameCount = ([regex]::Matches($text, "data:\s*")).Count
      }
    }

    $response = Invoke-RestMethod `
      -Method Post `
      -Uri "$base/chat/completions" `
      -Headers @{ Authorization = "Bearer $ApiKey"; "Content-Type" = "application/json" } `
      -Body $body `
      -TimeoutSec $TimeoutSec
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
      throw "Downstream key reached sub2api but no account was schedulable for model $Model"
    }
    throw
  }
}

$nonStreamResult = Invoke-ChatCompletion -Stream:$false
$streamResult = $null
if (-not $SkipStream) {
  $streamResult = Invoke-ChatCompletion -Stream:$true
}

[ordered]@{
  ok = $true
  baseUrl = $base
  model = $Model
  nonStream = $nonStreamResult
  stream = $streamResult
  keyContract = "sub2api-issued downstream key only"
} | ConvertTo-Json -Depth 8
