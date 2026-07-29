# Phase 2B-2B5 — Owner permanent deletion and schedule removal aggregate verification

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot/lib/reve-supabase-local.ps1"
. "$PSScriptRoot/lib/reve-verify-helpers.ps1"

function Invoke-Step {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][scriptblock]$Action
  )

  Write-Host "=== $Name ==="
  & $Action
  if ($LASTEXITCODE -ne 0) {
    throw "$Name failed with exit code $LASTEXITCODE"
  }
}

function Invoke-PlaywrightCommand {
  param(
    [Parameter(Mandatory = $true)][string]$Label,
    [Parameter(Mandatory = $true)][string[]]$CommandArgs
  )

  Write-Host "=== $Label ==="
  $previousErrorAction = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $output = & npx @CommandArgs 2>&1 | Tee-Object -Variable captured
    $output | Write-Host
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousErrorAction
  }

  if ($exitCode -ne 0) {
    throw "$Label failed with exit code $exitCode"
  }

  $joined = ($captured | Out-String)
  if ($joined -match '\bflaky\b') {
    throw "$Label reported flaky tests"
  }

  $matches = [regex]::Matches($joined, '(\d+)\s+passed')
  if ($matches.Count -eq 0) {
    throw "$Label could not parse Playwright pass count"
  }

  return [int]$matches[$matches.Count - 1].Groups[1].Value
}

Push-Location $repoRoot
try {
  Write-Host '=== Step 0: rollback tag checkpoint ==='
  $rollbackTag = git rev-parse 'phase-2b2b5-owner-deletion-rollback' 2>$null
  if (-not $rollbackTag) {
    throw 'Missing local tag phase-2b2b5-owner-deletion-rollback'
  }
  if ($rollbackTag -ne '98d8c2121d3dd9b2da25f80ca7d86d9f9f96b12c') {
    throw "Rollback tag must point to 98d8c21, found $rollbackTag"
  }
  Write-Host "Rollback tag OK at $rollbackTag"

  Invoke-Step 'Step 1: npm ci' { npm ci }
  Invoke-Step 'Step 2: typecheck' { npm run typecheck }
  Invoke-Step 'Step 3: eslint' { npm run lint }

  Write-Host '=== Step 4: vitest ==='
  $vitestOutput = npm run test 2>&1 | Tee-Object -Variable vitestCaptured
  $vitestOutput | Write-Host
  if ($LASTEXITCODE -ne 0) { throw "Vitest failed with exit code $LASTEXITCODE" }
  $vitestMatch = [regex]::Match(($vitestCaptured -join "`n"), 'Tests\s+(\d+)\s+passed')
  if (-not $vitestMatch.Success) { throw 'Could not parse Vitest pass count' }
  $vitestPassed = [int]$vitestMatch.Groups[1].Value

  Invoke-Step 'Step 5: production build' { npm run build }

  Invoke-Step 'Step 6: supabase db reset' { npx supabase db reset --yes }
  Wait-ReveSupabaseAuthService

  $standardPgtap = Invoke-PgtapSuite -Label 'Step 7: pgTAP full suite'

  Write-Host '=== Step 8: Owner Alpha demo seed (local) ==='
  & "$PSScriptRoot/seed-owner-alpha.ps1"
  if ($LASTEXITCODE -ne 0) { throw "Owner Alpha demo seed failed with exit code $LASTEXITCODE" }
  Wait-ReveSupabaseAuthReady

  Write-Host '=== Pre-Playwright: ensure fresh dev server after db reset ==='
  $env:CI = '1'
  . "$PSScriptRoot/lib/reve-playwright-server.ps1"
  Stop-RevePlaywrightDevServerIfStale -RepoRoot $repoRoot -Port 3000

  $playwrightFocused = Invoke-PlaywrightCommand -Label 'Step 9: Phase 2B-2B5 focused Playwright' -CommandArgs @(
    'playwright', 'test', '--retries=0', 'e2e/owner-deletion.spec.ts'
  )

  & "$PSScriptRoot/seed-owner-alpha.ps1"
  if ($LASTEXITCODE -ne 0) { throw "Owner Alpha re-seed before regression Playwright failed" }
  Wait-ReveSupabaseAuthReady
  Stop-RevePlaywrightDevServerIfStale -RepoRoot $repoRoot -Port 3000

  Invoke-PlaywrightCommand -Label 'Step 10: student detail regression' -CommandArgs @(
    'playwright', 'test', '--retries=0', 'e2e/owner-student-detail.spec.ts'
  ) | Out-Null
  Invoke-PlaywrightCommand -Label 'Step 11: teachers regression' -CommandArgs @(
    'playwright', 'test', '--retries=0', 'e2e/owner-teachers.spec.ts'
  ) | Out-Null
  Invoke-PlaywrightCommand -Label 'Step 12: enrollment regression' -CommandArgs @(
    'playwright', 'test', '--retries=0', 'e2e/owner-student-enrollment.spec.ts'
  ) | Out-Null

  Write-Host 'Phase 2B-2B5 aggregate verification passed.'
  Write-Host "Report: vitest=$vitestPassed passed; pgTAP=$standardPgtap; playwright_2b2b5=$playwrightFocused passed"
}
finally {
  Pop-Location
}
