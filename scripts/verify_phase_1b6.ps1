# Phase 1B-6 — Owner student operational history vertical slice aggregate verification

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

Push-Location $repoRoot
try {
  $container = Get-ReveSupabaseDbContainer -RepoRoot $repoRoot

  Invoke-Step 'Step 1: npm ci' { npm ci }
  Invoke-Step 'Step 2: typecheck' { npm run typecheck }
  Invoke-Step 'Step 3: eslint' { npm run lint }
  Invoke-Step 'Step 4: vitest' { npm run test }
  Invoke-Step 'Step 5: production build' { npm run build }

  Invoke-Step 'Step 6: supabase db reset' { npx supabase db reset }

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

  Invoke-Step 'Step 12: playwright (full e2e suite)' { npx playwright test }

  Invoke-Step 'Step 13: Phase 1A regression (Playwright)' { npx playwright test e2e/owner-alpha.spec.ts }
  Invoke-Step 'Step 14: Phase 1B-1 regression (Playwright)' { npx playwright test e2e/owner-weekly-schedule.spec.ts }
  Invoke-Step 'Step 15: Phase 1B-2 regression (Playwright)' { npx playwright test e2e/owner-sms.spec.ts }
  Invoke-Step 'Step 16: Phase 1B-3 regression (Playwright)' { npx playwright test e2e/owner-refunds.spec.ts }
  Invoke-Step 'Step 17: Phase 1B-4 regression (Playwright)' { npx playwright test e2e/owner-schedule-requests.spec.ts }
  Invoke-Step 'Step 18: Phase 1B-5 regression (Playwright)' { npx playwright test e2e/owner-schedule-requests.spec.ts }

  Write-Host '=== Step 19: leftover harness check ==='
  Assert-ReveNoHarnessObjects -Container $container

  Write-Host '=== Step 20: working tree status ==='
  $status = git status --porcelain
  if ($status) {
    Write-Host $status
    throw 'Working tree is not clean'
  }
  Write-Host 'working tree clean'

  Write-Host 'Phase 1B-6 aggregate verification passed.'
  Write-Host "Report: vitest via npm run test; standard pgTAP=$standardPgtap; SMS concurrency pgTAP=1; refund concurrency pgTAP=2"
}
finally {
  Pop-Location
}
