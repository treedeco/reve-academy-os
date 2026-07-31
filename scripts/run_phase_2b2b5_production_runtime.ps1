# Phase 2B-2B5 production runtime verification runner (operator-only).
param(
  [switch]$ConfirmProduction,
  [switch]$AllowSecurePrompt,
  [switch]$TestLoginOnly
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot
. (Join-Path $PSScriptRoot 'lib/ProductionOperator.ps1')

try {
  Assert-ProductionConfirmed -ConfirmProduction:$ConfirmProduction

  if ($AllowSecurePrompt -or [string]::IsNullOrWhiteSpace($env:PRODUCTION_OWNER_PASSWORD)) {
    Read-SecureProductionOwnerPassword
  }

  if ([string]::IsNullOrWhiteSpace($env:PRODUCTION_OWNER_PASSWORD)) {
    throw 'PRODUCTION_OWNER_PASSWORD is not visible to this process.'
  }

  Write-Host 'PRODUCTION_OWNER_PASSWORD: configured (value not shown).'
  if ($AllowSecurePrompt) {
    Write-Host 'Password source: secure prompt (this run).'
  }

  Set-ProductionSupabaseAnonKey

  $nodeScript = if ($TestLoginOnly) {
    'scripts/test_production_owner_login.mjs'
  } else {
    'scripts/verify_phase_2b2b5_production_runtime.mjs'
  }

  $runtimeResult = Invoke-ProductionNodeScript -ScriptPath $nodeScript
  Write-Host $runtimeResult.Output.TrimEnd()
  exit $runtimeResult.ExitCode
}
finally {
  Clear-ProductionOperatorEnv
}
