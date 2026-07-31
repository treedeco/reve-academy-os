# Legacy alias — prefer scripts/run_rotate_production_owner_password.ps1
param(
  [switch]$ConfirmProduction
)

& (Join-Path $PSScriptRoot 'run_rotate_production_owner_password.ps1') @PSBoundParameters
