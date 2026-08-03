# Dry-run (default) or apply cleanup for PHASE2B2B5 disposable production records.
param(
  [switch]$ConfirmProduction,
  [switch]$Apply,
  [string]$RunId
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot
. (Join-Path $PSScriptRoot 'lib/ProductionOperator.ps1')

$nodeArgs = @()

try {
  Assert-ProductionConfirmed -ConfirmProduction:$ConfirmProduction

  if ($Apply) {
    if ([string]::IsNullOrWhiteSpace($RunId)) {
      throw 'Apply requires -RunId from the prior dry-run output.'
    }
    $env:REVE_CLEANUP_APPLY_RUN_ID = $RunId
    $nodeArgs += '--apply'
  }

  if ($Apply -or [string]::IsNullOrWhiteSpace($env:PRODUCTION_OWNER_PASSWORD)) {
    Read-SecureProductionOwnerPassword
  }

  if ([string]::IsNullOrWhiteSpace($env:PRODUCTION_OWNER_PASSWORD)) {
    throw 'PRODUCTION_OWNER_PASSWORD is not visible to this process.'
  }

  Set-ProductionSupabaseAnonKey

  $result = Invoke-ProductionNodeScript -ScriptPath 'scripts/cleanup_phase_2b2b5_production_disposables.mjs' -NodeArgs $nodeArgs
  Write-Host $result.Output.TrimEnd()
  exit $result.ExitCode
}
finally {
  Clear-ProductionOperatorEnv
  Restore-ProductionConfirmation
}
