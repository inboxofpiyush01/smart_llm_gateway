# AnyCloud Studio - local secret scan (blocks commit if secrets found)
$ErrorActionPreference = 'Stop'
$root = (Get-Location).Path
if ($PSScriptRoot) { $candidate = Split-Path $PSScriptRoot -Parent; if (Test-Path (Join-Path $candidate 'Dockerfile')) { $root = $candidate } }
Set-Location $root
$patterns = @(
  '(?i)(API[_-]?KEY|_KEY|SECRET|PASSWORD)\s*[=:]\s*\S+',
  'sk-[A-Za-z0-9_-]{10,}',
  'gsk_[A-Za-z0-9_-]{10,}',
  'ghp_[A-Za-z0-9_-]{20,}',
  'AKIA[0-9A-Z]{16}'
)
$files = @()
if (Test-Path .git) {
  $files = @(git diff --cached --name-only --diff-filter=ACMR 2>$null)
  if (-not $files -or $files.Count -eq 0) { $files = @(git ls-files 2>$null) }
} 
if (-not $files -or $files.Count -eq 0) {
  $files = @(Get-ChildItem -Recurse -File -Include *.yaml,*.yml,*.env,*.json,*.toml,*.ps1 -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName.Substring($root.Length).TrimStart('\','/') })
}
$hits = @()
foreach ($f in $files) {
  if (-not $f) { continue }
  $rel = $f -replace '^[\\/]+',''
  if ($rel -notmatch '\.(ya?ml|env|json|toml|txt|md|ps1|sh|py|js)$' -and $rel -notmatch '(^|/)(Dockerfile|docker-compose)') { continue }
  if ($rel -match '(^|/)(scripts/scan-secrets|docs/SECRETS|\.githooks/)') { continue }
  $full = Join-Path $root $rel
  if (-not (Test-Path -LiteralPath $full)) { continue }
  $text = Get-Content -LiteralPath $full -Raw -ErrorAction SilentlyContinue
  if (-not $text) { continue }
  # Allow placeholder-only secret templates
  if ($text -match 'supplied-at-deploy-time|REMOVED-BY-ANYCLOUD-SECRET-GUARD') {
    $text = $text -replace '(?i)(supplied-at-deploy-time|REMOVED-BY-ANYCLOUD-SECRET-GUARD)','PLACEHOLDER'
  }
  foreach ($p in $patterns) {
    if ([regex]::IsMatch($text, $p)) { $hits += ($rel + ' matched secret pattern'); break }
  }
}
if ($hits.Count -gt 0) {
  Write-Host 'AnyCloud secret scan FAILED - commit blocked:' -ForegroundColor Red
  $hits | ForEach-Object { Write-Host ('  ' + $_) -ForegroundColor Yellow }
  Write-Host 'Move secrets to Runtime API keys & secrets (session-only). Do not commit them.' -ForegroundColor Yellow
  exit 1
}
Write-Host 'AnyCloud secret scan passed.' -ForegroundColor Green
exit 0
