# Contract tests for Phase 2B-2C1 backup runners.
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $repoRoot
. (Join-Path $repoRoot 'scripts/lib/ProductionOperator.ps1')

$failures = @()

function Assert-ContractTest {
  param(
    [string]$Name,
    [scriptblock]$Test
  )

  try {
    & $Test
    Write-Host "PASS $Name"
  }
  catch {
    Write-Host "FAIL $Name"
    Write-Host "  $($_.Exception.Message)"
    $script:failures += $Name
  }
}

function Assert-ThrowsLike {
  param(
    [scriptblock]$Action,
    [string]$Pattern
  )

  $threw = $false
  try {
    & $Action
  }
  catch {
    $threw = $true
    if ($_.Exception.Message -notmatch $Pattern) {
      throw "Expected error matching '$Pattern' but got '$($_.Exception.Message)'"
    }
  }

  if (-not $threw) {
    throw 'Expected an exception but none was thrown.'
  }
}

Assert-ContractTest 'project ref confirmation rejects mismatch' {
  Assert-ThrowsLike {
    Assert-ProductionProjectRefConfirmed -ProvidedRef 'wrong-ref'
  } 'project ref mismatch'
}

Assert-ContractTest 'project ref confirmation accepts production ref' {
  $confirmed = Assert-ProductionProjectRefConfirmed -ProvidedRef 'bfhptqhgxignyggyxxkx'
  if ($confirmed -ne 'bfhptqhgxignyggyxxkx') {
    throw 'Expected production project ref to be accepted.'
  }
}

Assert-ContractTest 'backup runner requires ConfirmProduction' {
  Remove-Item Env:REVE_CONFIRM_PRODUCTION -ErrorAction SilentlyContinue
  Assert-ThrowsLike {
    Assert-ProductionConfirmed -ConfirmProduction:$false
  } 'Explicit production confirmation is required'
}

Assert-ContractTest 'Clear-ProductionOperatorEnv removes backup and encryption env vars' {
  $env:REVE_PRODUCTION_DB_PASSWORD = 'temp'
  $env:PGPASSWORD = 'temp'
  $env:REVE_BACKUP_LABEL = 'phase-2b2c1-test'
  $env:REVE_BACKUP_ENCRYPTION_PASSPHRASE = 'temp'
  $env:REVE_BACKUP_DESTINATION = 'C:\Dev\temp'
  Clear-ProductionOperatorEnv
  if ($env:REVE_PRODUCTION_DB_PASSWORD -or $env:PGPASSWORD -or $env:REVE_BACKUP_LABEL -or $env:REVE_BACKUP_ENCRYPTION_PASSPHRASE -or $env:REVE_BACKUP_DESTINATION) {
    throw 'Backup-related environment variables were not cleared.'
  }
}

if ($failures.Count -gt 0) {
  Write-Host "Contract failures: $($failures.Count)"
  exit 1
}

Write-Host 'All BackupRunner contract tests passed.'
exit 0
