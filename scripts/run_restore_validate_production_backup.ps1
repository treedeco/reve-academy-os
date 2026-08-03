# Restore a production backup into an isolated local validation database (never production).
param(
  [switch]$ConfirmRestoreValidation,
  [string]$Label,
  [string]$ManifestPath,
  [string]$Container
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot
. (Join-Path $PSScriptRoot 'lib/ProductionOperator.ps1')
. (Join-Path $PSScriptRoot 'lib/reve-supabase-local.ps1')

$nodeArgs = @()

try {
  if (-not $ConfirmRestoreValidation) {
    throw 'Explicit restore validation confirmation is required. Re-run with -ConfirmRestoreValidation.'
  }

  $env:REVE_CONFIRM_RESTORE_VALIDATION = '1'

  Read-SecureBackupEncryptionPassphrase
  if ([string]::IsNullOrWhiteSpace($env:REVE_BACKUP_ENCRYPTION_PASSPHRASE)) {
    throw 'REVE_BACKUP_ENCRYPTION_PASSPHRASE is not visible to this process.'
  }

  if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) {
    $nodeArgs += @('--manifest', $ManifestPath.Trim())
  }
  elseif (-not [string]::IsNullOrWhiteSpace($Label)) {
    $nodeArgs += @('--label', $Label.Trim())
  }
  else {
    throw 'Provide -Label or -ManifestPath.'
  }

  if (-not [string]::IsNullOrWhiteSpace($Container)) {
    $env:SUPABASE_DB_CONTAINER = $Container.Trim()
  }
  else {
    $env:SUPABASE_DB_CONTAINER = Get-ReveSupabaseDbContainer -RepoRoot $repoRoot
  }

  Assert-ReveLocalDatabaseTarget -Container $env:SUPABASE_DB_CONTAINER
  Write-ProductionOperatorStage 'restore_validation_target_confirmed'

  $result = Invoke-ProductionNodeScript -ScriptPath 'scripts/restore_validate_production_backup.mjs' -NodeArgs $nodeArgs -TimeoutSeconds 420
  if ($result.Output.Trim().Length -gt 0) {
    Write-Host $result.Output.TrimEnd()
  }
  Write-ProductionOperatorStage 'restore_validation_runner_complete'
  exit $result.ExitCode
}
finally {
  Remove-Item Env:REVE_CONFIRM_RESTORE_VALIDATION -ErrorAction SilentlyContinue
  Clear-ProductionOperatorEnv
}
