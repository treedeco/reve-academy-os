# Contract tests for cleanup runner production confirmation propagation.
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $repoRoot
. (Join-Path $repoRoot 'scripts/lib/ProductionOperator.ps1')

$failures = @()
$probeScripts = @()

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

function New-ProbeScript {
  param([string]$Body)

  $path = Join-Path $env:TEMP ("reve-cleanup-probe-$([Guid]::NewGuid().ToString()).mjs")
  Set-Content -Path $path -Value $Body -Encoding utf8
  $script:probeScripts += $path
  return $path
}

function Invoke-CleanupRunnerConfirmationProbe {
  param(
    [switch]$ConfirmProduction,
    [switch]$Apply,
    [string]$RunId,
    [string]$ProbeScript,
    [int]$TimeoutSeconds = 30
  )

  $nodeArgs = @()
  $output = $null
  $exitCode = 0

  try {
    Assert-ProductionConfirmed -ConfirmProduction:$ConfirmProduction

    if ($Apply) {
      if ([string]::IsNullOrWhiteSpace($RunId)) {
        throw 'Apply requires -RunId from the prior dry-run output.'
      }
      $env:REVE_CLEANUP_APPLY_RUN_ID = $RunId
      $nodeArgs += '--apply'
    }

    $result = Invoke-ProductionNodeScript -ScriptPath $ProbeScript -NodeArgs $nodeArgs -TimeoutSeconds $TimeoutSeconds
    $output = $result.Output
    $exitCode = $result.ExitCode
  }
  finally {
    Clear-ProductionOperatorEnv
    Restore-ProductionConfirmation
  }

  return @{
    Output = $output
    ExitCode = $exitCode
    NodeArgs = $nodeArgs
  }
}

$confirmationProbeScript = New-ProbeScript @'
const confirmed = process.env.REVE_CONFIRM_PRODUCTION === '1';
process.stdout.write(JSON.stringify({ confirmed }));
process.exit(confirmed ? 0 : 1);
'@

$failureProbeScript = New-ProbeScript "process.stderr.write('fail'); process.exit(9);"

$timeoutProbeScript = New-ProbeScript "setInterval(() => {}, 1000);"

Assert-ContractTest 'cleanup runner with ConfirmProduction propagates REVE_CONFIRM_PRODUCTION=1 to child probe' {
  Remove-Item Env:REVE_CONFIRM_PRODUCTION -ErrorAction SilentlyContinue
  $result = Invoke-CleanupRunnerConfirmationProbe -ConfirmProduction -ProbeScript $confirmationProbeScript
  if ($result.ExitCode -ne 0) {
    throw "Expected child exit code 0, got $($result.ExitCode)"
  }
  $payload = $result.Output.Trim() | ConvertFrom-Json
  if (-not $payload.confirmed) {
    throw 'Child probe did not observe REVE_CONFIRM_PRODUCTION=1'
  }
}

Assert-ContractTest 'cleanup runner without ConfirmProduction fails closed' {
  Remove-Item Env:REVE_CONFIRM_PRODUCTION -ErrorAction SilentlyContinue
  Assert-ThrowsLike {
    Invoke-CleanupRunnerConfirmationProbe -ProbeScript $confirmationProbeScript
  } 'Explicit production confirmation is required'
}

Assert-ContractTest 'prior REVE_CONFIRM_PRODUCTION value is restored after success' {
  $env:REVE_CONFIRM_PRODUCTION = 'prior-value'
  $result = Invoke-CleanupRunnerConfirmationProbe -ConfirmProduction -ProbeScript $confirmationProbeScript
  if ($result.ExitCode -ne 0) {
    throw "Expected success exit code, got $($result.ExitCode)"
  }
  if ($env:REVE_CONFIRM_PRODUCTION -ne 'prior-value') {
    throw "Expected restored prior value, got '$($env:REVE_CONFIRM_PRODUCTION)'"
  }
}

Assert-ContractTest 'prior REVE_CONFIRM_PRODUCTION value is restored after child failure' {
  $env:REVE_CONFIRM_PRODUCTION = 'prior-value'
  try {
    $result = Invoke-CleanupRunnerConfirmationProbe -ConfirmProduction -ProbeScript $failureProbeScript
    if ($result.ExitCode -ne 9) {
      throw "Expected child exit code 9, got $($result.ExitCode)"
    }
  }
  finally {
    if ($env:REVE_CONFIRM_PRODUCTION -ne 'prior-value') {
      throw "Expected restored prior value after failure, got '$($env:REVE_CONFIRM_PRODUCTION)'"
    }
  }
}

Assert-ContractTest 'prior REVE_CONFIRM_PRODUCTION value is restored after timeout' {
  $env:REVE_CONFIRM_PRODUCTION = 'prior-value'
  try {
    Assert-ThrowsLike {
      Invoke-CleanupRunnerConfirmationProbe -ConfirmProduction -ProbeScript $timeoutProbeScript -TimeoutSeconds 2
    } 'timed out'
  }
  finally {
    if ($env:REVE_CONFIRM_PRODUCTION -ne 'prior-value') {
      throw "Expected restored prior value after timeout, got '$($env:REVE_CONFIRM_PRODUCTION)'"
    }
  }
}

Assert-ContractTest 'dry-run remains the default without --apply child argument' {
  Remove-Item Env:REVE_CONFIRM_PRODUCTION -ErrorAction SilentlyContinue
  $result = Invoke-CleanupRunnerConfirmationProbe -ConfirmProduction -ProbeScript $confirmationProbeScript
  if ($result.NodeArgs -contains '--apply') {
    throw 'Dry-run must not pass --apply to the cleanup child process.'
  }
}

Assert-ContractTest 'Apply still requires both ConfirmProduction and a valid RunId' {
  Remove-Item Env:REVE_CONFIRM_PRODUCTION -ErrorAction SilentlyContinue
  Assert-ThrowsLike {
    Invoke-CleanupRunnerConfirmationProbe -ConfirmProduction -Apply -ProbeScript $confirmationProbeScript
  } 'Apply requires -RunId'
}

Assert-ContractTest 'Apply without ConfirmProduction fails closed before RunId validation' {
  Remove-Item Env:REVE_CONFIRM_PRODUCTION -ErrorAction SilentlyContinue
  Assert-ThrowsLike {
    Invoke-CleanupRunnerConfirmationProbe -Apply -RunId 'CLEANUP-PHASE2B2B5-TEST-000001' -ProbeScript $confirmationProbeScript
  } 'Explicit production confirmation is required'
}

foreach ($probeScript in $probeScripts) {
  Remove-Item $probeScript -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
  Write-Host ""
  Write-Host "Cleanup runner contract test failures: $($failures.Count)"
  exit 1
}

Write-Host ""
Write-Host 'All cleanup runner contract tests passed.'
exit 0
