# REVE ACADEMY OS — deterministic Supabase db lint baseline verification

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $repoRoot
try {
  node "$PSScriptRoot/verify-db-lint-baseline.mjs"
  if ($LASTEXITCODE -ne 0) {
    throw "db lint baseline verification failed with exit code $LASTEXITCODE"
  }
}
finally {
  Pop-Location
}
