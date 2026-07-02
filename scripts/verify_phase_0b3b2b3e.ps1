# Phase 0B-3B-2B-3E — full database verification (standard pgTAP + refund concurrency)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$container = 'supabase_db_reve-academy-os'

function Assert-NoHarnessObjects {
  $exists = docker exec -i $container psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -t -A -c @"
SELECT EXISTS (
  SELECT 1 FROM pg_namespace WHERE nspname IN ('reve_test', 'reve_concurrency_runtime')
);
"@
  if ($exists.Trim() -in @('t', 'true')) {
    throw 'Test harness objects remain after verification'
  }
}

Push-Location $repoRoot
try {
  Write-Host '=== Step 1: db reset ==='
  npx supabase db reset
  if ($LASTEXITCODE -ne 0) { throw "db reset failed with exit code $LASTEXITCODE" }

  Write-Host '=== Step 2: standard pgTAP suite ==='
  npx supabase test db
  if ($LASTEXITCODE -ne 0) { throw "standard pgTAP suite failed with exit code $LASTEXITCODE" }

  Write-Host '=== Step 3: refund concurrency verification ==='
  & "$PSScriptRoot/verify_refund_concurrency.ps1"
  if ($LASTEXITCODE -ne 0) { throw "refund concurrency verification failed with exit code $LASTEXITCODE" }

  Write-Host '=== Step 4: db lint ==='
  npx supabase db lint
  if ($LASTEXITCODE -ne 0) { throw "db lint failed with exit code $LASTEXITCODE" }

  Write-Host '=== Step 5: leftover harness check ==='
  Assert-NoHarnessObjects

  Write-Host 'Phase 0B-3B-2B-3E verification passed.'
}
finally {
  Pop-Location
}
