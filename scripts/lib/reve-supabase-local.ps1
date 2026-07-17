. "$PSScriptRoot/reve-owner-credentials.ps1"

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

function Wait-ReveSupabaseAuthService {
  param(
    [string]$ApiUrl = 'http://127.0.0.1:54321',
    [int]$MaxAttempts = 30,
    [int]$DelaySeconds = 2
  )

  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    try {
      $response = Invoke-WebRequest -Uri "$ApiUrl/auth/v1/health" -Method GET -UseBasicParsing -ErrorAction Stop
      if ($response.StatusCode -eq 200) {
        Write-Host "Supabase Auth service ready after $attempt attempt(s)."
        return
      }
    }
    catch {
      Write-Host "Supabase Auth service not ready (attempt $attempt/$MaxAttempts): $($_.Exception.Message)"
    }
    Start-Sleep -Seconds $DelaySeconds
  }

  throw "Supabase Auth service did not become ready after $MaxAttempts attempts."
}

function Wait-ReveSupabaseAuthReady {
  param(
    [string]$ApiUrl = 'http://127.0.0.1:54321',
    [string]$AnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0',
    [string]$OwnerEmail,
    [string]$OwnerPassword,
    [int]$MaxAttempts = 30,
    [int]$DelaySeconds = 2
  )

  if (-not $OwnerEmail) {
    $OwnerEmail = Get-ReveOwnerAuthEmail
  }
  if (-not $OwnerPassword) {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $OwnerPassword = Get-ReveOwnerSeedPassword -RepoRoot $repoRoot
  }

  $body = (@{ email = $OwnerEmail; password = $OwnerPassword } | ConvertTo-Json -Compress)
  $headers = @{
    apikey       = $AnonKey
    'Content-Type' = 'application/json'
  }

  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    try {
      $response = Invoke-RestMethod -Uri "$ApiUrl/auth/v1/token?grant_type=password" -Method POST -Headers $headers -Body $body -ErrorAction Stop
      if ($response.access_token) {
        Write-Host "Supabase Auth ready after $attempt attempt(s)."
        return
      }
    }
    catch {
      Write-Host "Supabase Auth not ready (attempt $attempt/$MaxAttempts): $($_.Exception.Message)"
    }
    Start-Sleep -Seconds $DelaySeconds
  }

  throw "Supabase Auth did not become ready after $MaxAttempts attempts."
}
