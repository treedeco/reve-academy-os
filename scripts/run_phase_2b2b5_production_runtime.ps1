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
  Write-ProductionOperatorStage 'confirm_production_complete'

  if ($AllowSecurePrompt -or [string]::IsNullOrWhiteSpace($env:PRODUCTION_OWNER_PASSWORD)) {
    Write-ProductionOperatorStage 'secure_password_prompt_start'
    Read-SecureProductionOwnerPassword
    Write-ProductionOperatorStage 'secure_password_prompt_complete'
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
  if ($runtimeResult.Output.Trim().Length -gt 0) {
    Write-Host $runtimeResult.Output.TrimEnd()
  }
  Write-ProductionOperatorStage 'runner_complete'
  exit $runtimeResult.ExitCode
}
finally {
  Clear-ProductionOperatorEnv
  Restore-ProductionConfirmation
}
