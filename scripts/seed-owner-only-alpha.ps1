# REVE ACADEMY OS — Owner-only alpha seed (local Playwright fixture)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot/lib/reve-supabase-local.ps1"
. "$PSScriptRoot/lib/reve-owner-credentials.ps1"

$container = Get-ReveSupabaseDbContainer -RepoRoot $repoRoot
Assert-ReveLocalDatabaseTarget -Container $container

$seedPath = Join-Path $repoRoot 'scripts/seed-owner-only-alpha.sql'
if (-not (Test-Path $seedPath)) {
  throw "Seed file not found: $seedPath"
}

$ownerPassword = Get-ReveOwnerSeedPassword -RepoRoot $repoRoot
$escapedPassword = $ownerPassword.Replace("'", "''")

docker cp "$seedPath" "${container}:/tmp/seed-owner-only-alpha.sql"
if ($LASTEXITCODE -ne 0) { throw "docker cp failed with exit code $LASTEXITCODE" }

$seedSql = @"
BEGIN;
DO `$`$ BEGIN
  PERFORM set_config('reve.owner_seed_password', '$escapedPassword', true);
END `$`$;
\i /tmp/seed-owner-only-alpha.sql
SELECT set_config('reve.owner_seed_password', '', true);
COMMIT;
"@

$seedSql | docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1
if ($LASTEXITCODE -ne 0) { throw "seed SQL failed with exit code $LASTEXITCODE" }
