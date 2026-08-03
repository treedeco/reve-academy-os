# Verify a production backup manifest and dump checksum (operator-only read).
param(
  [switch]$ConfirmProduction,
  [Parameter(Mandatory = $true)][string]$ConfirmProjectRef,
  [string]$Label,
  [string]$ManifestPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot
. (Join-Path $PSScriptRoot 'lib/ProductionOperator.ps1')

$expectedProjectRef = 'bfhptqhgxignyggyxxkx'
$nodeArgs = @()

try {
  Assert-ProductionConfirmed -ConfirmProduction:$ConfirmProduction
  Assert-ProductionProjectRefConfirmed -ProvidedRef $ConfirmProjectRef -ExpectedRef $expectedProjectRef
  Write-ProductionOperatorStage 'confirm_production_complete'

  if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) {
    $nodeArgs += @('--manifest', $ManifestPath.Trim())
  }
  elseif (-not [string]::IsNullOrWhiteSpace($Label)) {
    $nodeArgs += @('--label', $Label.Trim())
  }
  else {
    throw 'Provide -Label or -ManifestPath.'
  }

  $result = Invoke-ProductionNodeScript -ScriptPath 'scripts/verify_production_backup.mjs' -NodeArgs $nodeArgs
  if ($result.Output.Trim().Length -gt 0) {
    Write-Host $result.Output.TrimEnd()
  }
  Write-ProductionOperatorStage 'verify_backup_runner_complete'
  exit $result.ExitCode
}
finally {
  Clear-ProductionOperatorEnv
  Restore-ProductionConfirmation
}
