# REVE ACADEMY OS — Owner Alpha demo seed (local only)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot/lib/reve-supabase-local.ps1"

$container = Get-ReveSupabaseDbContainer -RepoRoot $repoRoot
Assert-ReveLocalDatabaseTarget -Container $container

$seedPath = Join-Path $repoRoot 'scripts/seed-owner-alpha.sql'
if (-not (Test-Path $seedPath)) {
  throw "Seed file not found: $seedPath"
}

Write-Host "Applying Owner Alpha demo seed to local container: $container"
Write-Host 'WARNING: Demo credentials only. Never run against hosted/production databases.'

docker cp "$seedPath" "${container}:/tmp/seed-owner-alpha.sql"
if ($LASTEXITCODE -ne 0) { throw "docker cp failed with exit code $LASTEXITCODE" }

docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f /tmp/seed-owner-alpha.sql
if ($LASTEXITCODE -ne 0) { throw "seed SQL failed with exit code $LASTEXITCODE" }

Write-Host 'Owner Alpha demo seed applied.'
