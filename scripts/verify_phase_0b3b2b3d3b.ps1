# Phase 0B-3B-2B-3D-3B — full database verification (standard pgTAP + concurrency harness)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot/lib/reve-supabase-local.ps1"
. "$PSScriptRoot/lib/reve-verify-helpers.ps1"
$container = Get-ReveSupabaseDbContainer -RepoRoot $repoRoot

Push-Location $repoRoot
try {
  Write-Host '=== Step 1: db reset ==='
  npx supabase db reset
  if ($LASTEXITCODE -ne 0) { throw "db reset failed with exit code $LASTEXITCODE" }

  Invoke-PgtapSuite -Label 'Step 2: standard pgTAP suite'

  Write-Host '=== Step 3: Owner SMS concurrency verification ==='
  & "$PSScriptRoot/verify_sms_concurrency.ps1"
  if ($LASTEXITCODE -ne 0) { throw "concurrency verification failed with exit code $LASTEXITCODE" }

  Write-Host '=== Step 4: db lint baseline verification ==='
  Invoke-DbLintBaseline

  Write-Host '=== Step 5: leftover harness check ==='
  Assert-ReveNoHarnessObjects -Container $container

  Write-Host 'Phase 0B-3B-2B-3D-3B verification passed.'
}
finally {
  Pop-Location
}
