# Rotate production Owner Auth password (operator-only; never logs secrets).
param(
  [switch]$ConfirmProduction
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot
. (Join-Path $PSScriptRoot 'lib/ProductionOperator.ps1')

try {
  Assert-ProductionConfirmed -ConfirmProduction:$ConfirmProduction

  $projectRef = Read-Host 'Confirm production Supabase project ref (expected: bfhptqhgxignyggyxxkx)'
  if ($projectRef -ne 'bfhptqhgxignyggyxxkx') {
    throw "Refusing password rotation for unexpected project ref: $projectRef"
  }

  $secretKey = Read-SecurePlainText 'SUPABASE_SECRET_KEY (Dashboard -> Project Settings -> API; input hidden)'
  $newPassword = Read-SecurePlainText 'New production Owner password for reve (input hidden)'

  $env:SUPABASE_URL = 'https://bfhptqhgxignyggyxxkx.supabase.co'
  $env:SUPABASE_SECRET_KEY = $secretKey
  $env:NEW_OWNER_PASSWORD = $newPassword
  $secretKey = $null
  $newPassword = $null
  [GC]::Collect()

  $result = Invoke-ProductionNodeScript -ScriptPath 'scripts/reset-production-owner-password.mjs'
  Write-Host $result.Output.TrimEnd()
  if ($result.ExitCode -ne 0) {
    exit $result.ExitCode
  }

  Write-Host ''
  Write-Host 'Password rotation submitted. Verify login with:'
  Write-Host '  powershell -ExecutionPolicy Bypass -File scripts/run_phase_2b2b5_production_runtime.ps1 -ConfirmProduction -AllowSecurePrompt -TestLoginOnly'
}
finally {
  Clear-ProductionOperatorEnv
}
