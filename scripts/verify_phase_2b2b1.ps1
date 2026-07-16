# Phase 2B-2B1 — Owner student master and initial enrollment aggregate verification

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
  Write-Host '=== Step 0: starting checkpoint validation ==='
  $branch = git branch --show-current
  if ($branch -ne 'main') {
    throw "Expected branch main, found $branch"
  }

  $phase2b1Tag = git rev-parse 'phase-2b1-owner-teachers-master-data-runtime-verified'
  if ($phase2b1Tag -ne '0ee3cad6b8f57586e922ee95c66e9f5616f56747') {
    throw "Phase 2B-1 runtime tag must resolve to 0ee3cad6b8f57586e922ee95c66e9f5616f56747"
  }
  Write-Host "Phase 2B-1 runtime tag OK at $phase2b1Tag"

  $phase2b2b1Tag = git rev-parse 'phase-2b2b1-owner-student-initial-enrollment-implemented'
  if ($phase2b2b1Tag -ne '87b6665b57d92423c26b780218c703e61590138e') {
    throw "Phase 2B-2B1 implementation tag must resolve to 87b6665b57d92423c26b780218c703e61590138e"
  }
  Write-Host "Phase 2B-2B1 implementation tag OK at $phase2b2b1Tag"

  $implementationTag = git tag -l 'phase-2b2b1-owner-student-initial-enrollment-implemented'
  if (-not $implementationTag) {
    throw 'Phase 2B-2B1 implementation tag is missing'
  }

  $initialStatus = git status --porcelain
  if ($initialStatus) {
    Write-Host $initialStatus
    throw 'Working tree is not clean before verification'
  }
  Write-Host 'initial working tree clean'

  $container = Get-ReveSupabaseDbContainer -RepoRoot $repoRoot

  Write-Host '=== Pre-install: stop stale dev server on port 3000 ==='
  . "$PSScriptRoot/lib/reve-playwright-server.ps1"
  Stop-RevePlaywrightDevServerIfStale -RepoRoot $repoRoot -Port 3000

  Invoke-Step 'Step 1: npm ci' { npm ci }
  Invoke-Step 'Step 2: typecheck' { npm run typecheck }
  Invoke-Step 'Step 3: eslint' { npm run lint }

  Write-Host '=== Step 4: vitest ==='
  $vitestOutput = npm run test 2>&1 | Tee-Object -Variable vitestCaptured
  $vitestOutput | Write-Host
  if ($LASTEXITCODE -ne 0) { throw "Vitest failed with exit code $LASTEXITCODE" }
  $vitestMatch = [regex]::Match(($vitestCaptured -join "`n"), 'Tests\s+(\d+)\s+passed')
  if (-not $vitestMatch.Success) {
    throw 'Could not parse Vitest pass count'
  }
  $vitestPassed = [int]$vitestMatch.Groups[1].Value

  Invoke-Step 'Step 5: production build' { npm run build }

  Invoke-Step 'Step 6: supabase db reset' { npx supabase db reset }
  Wait-ReveSupabaseAuthService

  $standardPgtap = Invoke-PgtapSuite -Label 'Step 7: standard pgTAP suite'

  Write-Host '=== Step 8: SMS concurrency verification ==='
  & "$PSScriptRoot/verify_sms_concurrency.ps1"
  if ($LASTEXITCODE -ne 0) { throw "SMS concurrency verification failed with exit code $LASTEXITCODE" }

  Write-Host '=== Step 9: refund concurrency verification ==='
  & "$PSScriptRoot/verify_refund_concurrency.ps1"
  if ($LASTEXITCODE -ne 0) { throw "refund concurrency verification failed with exit code $LASTEXITCODE" }

  Invoke-Step 'Step 10: db lint baseline verification' {
    Invoke-DbLintBaseline
  }

  Write-Host '=== Step 11: Owner Alpha demo seed (local) ==='
  & "$PSScriptRoot/seed-owner-alpha.ps1"
  if ($LASTEXITCODE -ne 0) { throw "Owner Alpha demo seed failed with exit code $LASTEXITCODE" }
  Wait-ReveSupabaseAuthReady

  Write-Host '=== Pre-Playwright: ensure fresh dev server after db reset ==='
  $env:CI = '1'
  Stop-RevePlaywrightDevServerIfStale -RepoRoot $repoRoot -Port 3000

  $playwrightAllPassed = Invoke-PlaywrightCommand -Label 'Step 12: playwright (full e2e suite)' -CommandArgs @('playwright', 'test', '--retries=0')

  & "$PSScriptRoot/seed-owner-alpha.ps1"
  if ($LASTEXITCODE -ne 0) { throw "Owner Alpha re-seed before focused Playwright failed with exit code $LASTEXITCODE" }
  Wait-ReveSupabaseAuthReady
  Stop-RevePlaywrightDevServerIfStale -RepoRoot $repoRoot -Port 3000
  $playwrightFocusedPassed = Invoke-PlaywrightCommand -Label 'Step 13: Phase 2B-2B1 focused Playwright' -CommandArgs @('playwright', 'test', '--retries=0', 'e2e/owner-student-enrollment.spec.ts')

  & "$PSScriptRoot/seed-owner-alpha.ps1"
  if ($LASTEXITCODE -ne 0) { throw "Owner Alpha re-seed before regression Playwright failed with exit code $LASTEXITCODE" }
  Wait-ReveSupabaseAuthReady
  Stop-RevePlaywrightDevServerIfStale -RepoRoot $repoRoot -Port 3000

  Invoke-PlaywrightCommand -Label 'Step 14: Phase 1A regression (Playwright)' -CommandArgs @('playwright', 'test', '--retries=0', 'e2e/owner-alpha.spec.ts') | Out-Null
  Invoke-PlaywrightCommand -Label 'Step 15: Phase 1B-1 regression (Playwright)' -CommandArgs @('playwright', 'test', '--retries=0', 'e2e/owner-weekly-schedule.spec.ts') | Out-Null
  Invoke-PlaywrightCommand -Label 'Step 16: Phase 1B-2 regression (Playwright)' -CommandArgs @('playwright', 'test', '--retries=0', 'e2e/owner-sms.spec.ts') | Out-Null
  Invoke-PlaywrightCommand -Label 'Step 17: Phase 1B-3 regression (Playwright)' -CommandArgs @('playwright', 'test', '--retries=0', 'e2e/owner-refunds.spec.ts') | Out-Null
  Invoke-PlaywrightCommand -Label 'Step 18: Phase 1B-4 regression (Playwright)' -CommandArgs @('playwright', 'test', '--retries=0', 'e2e/owner-schedule-requests.spec.ts') | Out-Null
  Invoke-PlaywrightCommand -Label 'Step 19: Phase 1B-5 regression (Playwright)' -CommandArgs @('playwright', 'test', '--retries=0', 'e2e/owner-schedule-requests.spec.ts') | Out-Null
  Invoke-PlaywrightCommand -Label 'Step 20: Phase 1B-6 regression (Playwright)' -CommandArgs @('playwright', 'test', '--retries=0', 'e2e/owner-student-detail.spec.ts') | Out-Null
  Invoke-PlaywrightCommand -Label 'Step 21: Phase 2B-1 regression (Playwright)' -CommandArgs @('playwright', 'test', '--retries=0', 'e2e/owner-teachers.spec.ts') | Out-Null

  Write-Host '=== Step 22: leftover harness check ==='
  Assert-ReveNoHarnessObjects -Container $container

  Write-Host '=== Step 23: working tree status ==='
  $status = git status --porcelain
  if ($status) {
    Write-Host $status
    throw 'Working tree is not clean'
  }
  Write-Host 'working tree clean'

  Write-Host 'Phase 2B-2B1 aggregate verification passed.'
  Write-Host "Report: vitest=$vitestPassed passed; standard pgTAP=$standardPgtap; SMS concurrency pgTAP=1; refund concurrency pgTAP=2; playwright_all=$playwrightAllPassed passed; playwright_focused_2b2b1=$playwrightFocusedPassed passed"
}
finally {
  Pop-Location
}
