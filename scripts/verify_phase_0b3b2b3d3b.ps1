# Phase 0B-3B-2B-3D-3B — full database verification (standard pgTAP + concurrency harness)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$container = 'supabase_db_reve-academy-os'

function Assert-NoHarnessObjects {
  $exists = docker exec -i $container psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -t -A -c @"
SELECT EXISTS (
  SELECT 1 FROM information_schema.tables
  WHERE table_schema = 'reve_test' AND table_name = 'concurrency_assertions'
) OR EXISTS (
  SELECT 1 FROM pg_namespace WHERE nspname = 'reve_test'
) OR EXISTS (
  SELECT 1 FROM pg_namespace WHERE nspname = 'reve_concurrency_runtime'
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

  Write-Host '=== Step 3: Owner SMS concurrency verification ==='
  & "$PSScriptRoot/verify_sms_concurrency.ps1"
  if ($LASTEXITCODE -ne 0) { throw "concurrency verification failed with exit code $LASTEXITCODE" }

  Write-Host '=== Step 4: db lint ==='
  npx supabase db lint
  if ($LASTEXITCODE -ne 0) { throw "db lint failed with exit code $LASTEXITCODE" }

  Write-Host '=== Step 5: leftover harness check ==='
  Assert-NoHarnessObjects

  Write-Host 'Phase 0B-3B-2B-3D-3B verification passed.'
}
finally {
  Pop-Location
}
