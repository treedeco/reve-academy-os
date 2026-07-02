function Get-ReveProjectId {
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot
  )

  $configPath = Join-Path $RepoRoot 'supabase\config.toml'
  if (-not (Test-Path $configPath)) {
    throw "Supabase config not found at $configPath"
  }

  foreach ($line in Get-Content $configPath) {
    if ($line -match '^\s*project_id\s*=\s*"([^"]+)"\s*$') {
      return $Matches[1]
    }
  }

  throw 'Could not resolve project_id from supabase/config.toml'
}

function Get-ReveSupabaseDbContainer {
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot
  )

  if ($env:SUPABASE_DB_CONTAINER) {
    $candidate = $env:SUPABASE_DB_CONTAINER.Trim()
    $exists = docker ps --format '{{.Names}}' | Where-Object { $_ -eq $candidate }
    if (-not $exists) {
      throw "SUPABASE_DB_CONTAINER is set to '$candidate' but the container is not running."
    }
    return $candidate
  }

  $projectId = Get-ReveProjectId -RepoRoot $RepoRoot
  $expected = "supabase_db_$projectId"
  $running = @(docker ps --format '{{.Names}}' | Where-Object { $_ -like 'supabase_db_*' })

  if ($running.Count -eq 0) {
    throw 'No running supabase_db_* container found. Start local Supabase with: npx supabase start'
  }

  if ($running -contains $expected) {
    return $expected
  }

  if ($running.Count -eq 1) {
    Write-Warning "Expected container '$expected' not found; using '$($running[0])'."
    return $running[0]
  }

  throw "Multiple supabase_db_* containers are running ($($running -join ', ')). Set SUPABASE_DB_CONTAINER explicitly."
}

function Assert-ReveLocalDatabaseTarget {
  param(
    [Parameter(Mandatory = $true)][string]$Container
  )

  $dbHost = docker exec -i $container psql -U postgres -d postgres -t -A -c "SELECT COALESCE(inet_server_addr()::text, 'local');"
  $dbHost = $dbHost.Trim()
  if ($dbHost -notin @('', '127.0.0.1', '::1', 'local')) {
    throw "Refusing to continue: database host '$dbHost' does not look local."
  }

  $apiUrl = $env:SUPABASE_URL
  if (-not $apiUrl) {
    $apiUrl = $env:NEXT_PUBLIC_SUPABASE_URL
  }

  if ($apiUrl) {
    $lower = $apiUrl.ToLowerInvariant()
    if ($lower -match 'supabase\.co|supabase\.in|\.amazonaws\.com|\.azure\.|\.gcp\.') {
      throw "Refusing to continue: SUPABASE URL '$apiUrl' appears to be hosted/production."
    }
    if ($lower -notmatch '127\.0\.0\.1|localhost') {
      throw "Refusing to continue: SUPABASE URL '$apiUrl' is not a local development URL."
    }
  }
}

function Assert-ReveNoHarnessObjects {
  param(
    [Parameter(Mandatory = $true)][string]$Container
  )

  $exists = docker exec -i $container psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -t -A -c @"
SELECT EXISTS (
  SELECT 1 FROM pg_namespace WHERE nspname IN ('reve_test', 'reve_concurrency_runtime')
);
"@
  if ($exists.Trim() -in @('t', 'true')) {
    throw 'Test harness objects remain after verification'
  }
}
