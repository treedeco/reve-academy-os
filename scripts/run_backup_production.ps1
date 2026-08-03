# Phase 2B-2C1 guarded production database backup runner (operator-only).
param(
  [switch]$ConfirmProduction,
  [Parameter(Mandatory = $true)][string]$ConfirmProjectRef,
  [string]$Label
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot
. (Join-Path $PSScriptRoot 'lib/ProductionOperator.ps1')

$expectedProjectRef = 'bfhptqhgxignyggyxxkx'

try {
  Assert-ProductionConfirmed -ConfirmProduction:$ConfirmProduction
  Assert-ProductionProjectRefConfirmed -ProvidedRef $ConfirmProjectRef -ExpectedRef $expectedProjectRef
  Write-ProductionOperatorStage 'confirm_production_complete'

  Read-SecureBackupEncryptionPassphrase
  if ([string]::IsNullOrWhiteSpace($env:REVE_BACKUP_ENCRYPTION_PASSPHRASE)) {
    throw 'REVE_BACKUP_ENCRYPTION_PASSPHRASE is not visible to this process.'
  }
  Write-Host 'REVE_BACKUP_ENCRYPTION_PASSPHRASE: configured (value not shown).'

  Read-SecureProductionDbPassword
  if ([string]::IsNullOrWhiteSpace($env:REVE_PRODUCTION_DB_PASSWORD)) {
    throw 'REVE_PRODUCTION_DB_PASSWORD is not visible to this process.'
  }
  Write-Host 'REVE_PRODUCTION_DB_PASSWORD: configured (value not shown).'

  Read-SecureProductionOwnerPassword
  if ([string]::IsNullOrWhiteSpace($env:PRODUCTION_OWNER_PASSWORD)) {
    throw 'PRODUCTION_OWNER_PASSWORD is not visible to this process.'
  }
  Write-Host 'PRODUCTION_OWNER_PASSWORD: configured (value not shown).'

  $env:REVE_PRODUCTION_PROJECT_REF_CONFIRM = $expectedProjectRef
  $env:REVE_SUPABASE_PROJECT_REF = $expectedProjectRef
  $env:PGPASSWORD = $env:REVE_PRODUCTION_DB_PASSWORD

  if (-not [string]::IsNullOrWhiteSpace($Label)) {
    $env:REVE_BACKUP_LABEL = $Label.Trim()
  }

  Set-ProductionSupabaseAnonKey -ProjectRef $expectedProjectRef

  $result = Invoke-ProductionNodeScript -ScriptPath 'scripts/backup_production_database.mjs' -TimeoutSeconds 360
  if ($result.Output.Trim().Length -gt 0) {
    Write-Host $result.Output.TrimEnd()
  }
  Write-ProductionOperatorStage 'backup_runner_complete'
  exit $result.ExitCode
}
finally {
  Remove-Item Env:REVE_PRODUCTION_PROJECT_REF_CONFIRM -ErrorAction SilentlyContinue
  Remove-Item Env:REVE_BACKUP_LABEL -ErrorAction SilentlyContinue
  Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
  Clear-ProductionOperatorEnv
  Restore-ProductionConfirmation
}
