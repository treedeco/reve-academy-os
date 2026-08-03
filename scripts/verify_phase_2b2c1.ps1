# Phase 2B-2C1 — Production backup / restore safety gate aggregate verification

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

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

function Invoke-SecretScan {
  param(
    [Parameter(Mandatory = $true)][string]$Label,
    [Parameter(Mandatory = $true)][string[]]$Paths
  )

  Write-Host "=== $Label ==="
  $patterns = @(
    'sb_secret_[A-Za-z0-9_-]{20,}',
    'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}',
    'service_role\s*=\s*''[^'']{20,}'''
  )

  $hits = @()
  foreach ($target in $Paths) {
    if (-not (Test-Path $target)) {
      continue
    }

    $files = if (Test-Path $target -PathType Container) {
      Get-ChildItem -Path $target -Recurse -File -ErrorAction SilentlyContinue
    }
    else {
      @(Get-Item $target)
    }

    foreach ($file in $files) {
      $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
      if (-not $content) {
        continue
      }
      foreach ($pattern in $patterns) {
        if ($content -match $pattern) {
          $hits += "$($file.FullName) matched $pattern"
        }
      }
    }
  }

  if ($hits.Count -gt 0) {
    throw ($hits -join [Environment]::NewLine)
  }

  Write-Host 'Secret scan passed.'
}

Push-Location $repoRoot
try {
  Write-Host '=== Step 0: rollback tag checkpoint ==='
  $rollbackTag = git rev-parse 'phase-2b2c1-pre-backup-restore-safety-gate' 2>$null
  if (-not $rollbackTag) {
    throw 'Missing local tag phase-2b2c1-pre-backup-restore-safety-gate'
  }
  Write-Host "Rollback tag OK at $rollbackTag"

  Invoke-Step 'Step 1: typecheck' { npm run typecheck }
  Invoke-Step 'Step 2: eslint' { npm run lint }

  Write-Host '=== Step 3: vitest (2B-2C1 unit scope) ==='
  $previousErrorAction = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $vitestOutput = npx vitest run `
      tests/unit/reve-production-backup-contract.test.mjs `
      tests/unit/reve-production-backup-dump-contract.test.mjs `
      tests/unit/reve-production-backup-io.test.mjs `
      tests/unit/reve-production-backup-encryption.test.mjs `
      tests/unit/reve-production-backup-storage-guard.test.mjs `
      tests/unit/reve-production-backup-secrets-scan.test.mjs `
      tests/unit/reve-production-restore-plan.test.mjs `
      tests/unit/reve-production-restore-isolation-guard.test.mjs `
      tests/unit/reve-production-restore-validation.test.mjs `
      tests/unit/backup-production.test.mjs `
      tests/unit/verify-production-backup.test.mjs 2>&1 | Tee-Object -Variable vitestCaptured
    $vitestOutput | Write-Host
    if ($LASTEXITCODE -ne 0) { throw "Vitest failed with exit code $LASTEXITCODE" }
  }
  finally {
    $ErrorActionPreference = $previousErrorAction
  }

  Invoke-Step 'Step 4: BackupRunner contract tests' {
    powershell -ExecutionPolicy Bypass -File tests/unit/BackupRunner.contract.test.ps1
  }

  Invoke-SecretScan -Label 'Step 5: secret scan (scripts/docs)' -Paths @(
    'scripts/backup_production_database.mjs',
    'scripts/verify_production_backup.mjs',
    'scripts/restore_validate_production_backup.mjs',
    'scripts/lib/reve-production-backup-contract.mjs',
    'scripts/lib/reve-production-backup-dump-contract.mjs',
    'scripts/lib/reve-production-backup-io.mjs',
    'scripts/lib/reve-production-backup-encryption.mjs',
    'scripts/lib/reve-production-backup-storage-guard.mjs',
    'scripts/lib/reve-production-backup-secrets-scan.mjs',
    'scripts/lib/reve-production-backup-baseline.mjs',
    'scripts/lib/reve-production-restore-plan.mjs',
    'scripts/lib/reve-production-restore-isolation-guard.mjs',
    'scripts/lib/reve-production-restore-validation.mjs',
    'scripts/run_backup_production.ps1',
    'scripts/run_verify_production_backup.ps1',
    'scripts/run_restore_validate_production_backup.ps1',
    'docs/backup-restore-runbook.md'
  )

  Write-Host '=== Step 6: git diff secret scan ==='
  $diff = git diff --unified=0
  if ($diff -match 'sb_secret_[A-Za-z0-9_-]{20,}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}') {
    throw 'git diff contains credential-like material.'
  }
  Write-Host 'git diff secret scan passed.'

  Write-Host '=== Step 7: git diff --check ==='
  git diff --check
  if ($LASTEXITCODE -ne 0) {
    throw 'git diff --check reported whitespace errors.'
  }

  Write-Host 'Phase 2B-2C1 verification complete.'
}
finally {
  Pop-Location
}
