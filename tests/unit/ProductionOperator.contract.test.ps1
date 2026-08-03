# Contract tests for ProductionOperator.ps1 node argument and exit-code handling.
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

  $path = Join-Path $env:TEMP ("reve-node-probe-$([Guid]::NewGuid().ToString()).mjs")
  Set-Content -Path $path -Value $Body -Encoding utf8
  $script:probeScripts += $path
  return $path
}

function Invoke-ResolverKeysFileLifecycleProbe {
  param(
    [Parameter(Mandatory = $true)][scriptblock]$InvokeChild
  )

  $keysFile = Join-Path $env:TEMP ("reve-prod-keys-$([Guid]::NewGuid().ToString()).json")
  $env:REVE_ANON_KEY_OUTPUT_PATH = $keysFile
  try {
    & $InvokeChild $keysFile
  }
  finally {
    Remove-Item $keysFile -Force -ErrorAction SilentlyContinue
    Remove-Item Env:REVE_ANON_KEY_OUTPUT_PATH -ErrorAction SilentlyContinue
  }

  if (Test-Path $keysFile) {
    throw "Resolver temp file was not removed: $keysFile"
  }
}

function New-MockExitedProcess {
  param(
    [object]$ExitCode,
    [int]$RefreshAttemptsBeforeExitCode = 999
  )

  $mock = New-Object PSObject -Property @{
    HasExited = $true
    ExitCode = $ExitCode
    RefreshCount = 0
    RefreshAttemptsBeforeExitCode = $RefreshAttemptsBeforeExitCode
  }

  $mock | Add-Member -MemberType ScriptMethod -Name Refresh -Value {
    $this.RefreshCount++
    if ($null -eq $this.ExitCode -and $this.RefreshCount -gt $this.RefreshAttemptsBeforeExitCode) {
      $this.ExitCode = 0
    }
  }

  return $mock
}

Assert-ContractTest 'zero Node arguments produce script path only' {
  $argumentList = Resolve-ProductionNodeProcessArguments -ScriptPath 'scripts/example.mjs'
  if ($argumentList.Count -ne 1 -or $argumentList[0] -ne 'scripts/example.mjs') {
    throw "Expected single script-path argument, got count=$($argumentList.Count)"
  }
  if ($argumentList -contains $null) {
    throw 'Argument list must not contain null.'
  }
}

Assert-ContractTest 'one normal Node argument is preserved' {
  $argumentList = Resolve-ProductionNodeProcessArguments -ScriptPath 'scripts/example.mjs' -NodeArgs @('--apply')
  if ($argumentList.Count -ne 2 -or $argumentList[0] -ne 'scripts/example.mjs' -or $argumentList[1] -ne '--apply') {
    throw "Unexpected argument list: $($argumentList -join ', ')"
  }
}

Assert-ContractTest 'explicit null NodeArgs collection is rejected' {
  Assert-ThrowsLike {
    Resolve-ProductionNodeProcessArguments -ScriptPath 'scripts/example.mjs' -NodeArgs $null
  } 'must not be null'
}

Assert-ContractTest 'null element in NodeArgs array is rejected' {
  Assert-ThrowsLike {
    Resolve-ProductionNodeProcessArguments -ScriptPath 'scripts/example.mjs' -NodeArgs @([string]'ok', [object]$null)
  } 'argument at index 1 is null'
}

Assert-ContractTest 'missing script path is rejected' {
  Assert-ThrowsLike {
    Resolve-ProductionNodeProcessArguments -ScriptPath ' '
  } 'Node script path is required'
}

Assert-ContractTest 'Resolve-ProductionChildProcessExitCode returns explicit zero' {
  $process = New-MockExitedProcess -ExitCode 0
  $exitCode = Resolve-ProductionChildProcessExitCode -Process $process -RetryCount 0 -RetryDelayMs 0
  if ($exitCode -ne 0) {
    throw "Expected exit code 0, got $exitCode"
  }
}

Assert-ContractTest 'Resolve-ProductionChildProcessExitCode preserves explicit non-zero code' {
  $process = New-MockExitedProcess -ExitCode 7
  $exitCode = Resolve-ProductionChildProcessExitCode -Process $process -RetryCount 0 -RetryDelayMs 0
  if ($exitCode -ne 7) {
    throw "Expected exit code 7, got $exitCode"
  }
}

Assert-ContractTest 'Resolve-ProductionChildProcessExitCode fails closed on unavailable exit code' {
  $process = New-MockExitedProcess -ExitCode $null -RefreshAttemptsBeforeExitCode 999
  Assert-ThrowsLike {
    Resolve-ProductionChildProcessExitCode -Process $process -RetryCount 1 -RetryDelayMs 0
  } 'exit code is unavailable'
}

Assert-ContractTest 'Resolve-ProductionChildProcessExitCode retries refresh before failing closed' {
  $process = New-MockExitedProcess -ExitCode $null -RefreshAttemptsBeforeExitCode 1
  $exitCode = Resolve-ProductionChildProcessExitCode -Process $process -RetryCount 2 -RetryDelayMs 0
  if ($exitCode -ne 0) {
    throw "Expected synchronized exit code 0 after refresh retry, got $exitCode"
  }
}

Assert-ContractTest 'Invoke-ProductionNodeScript returns explicit exit code 0' {
  $probeScript = New-ProbeScript "process.stdout.write('probe_ok');"
  $result = Invoke-ProductionNodeScript -ScriptPath $probeScript -TimeoutSeconds 30
  if ($result.ExitCode -ne 0 -or $result.Output.Trim() -ne 'probe_ok') {
    throw "Unexpected probe result: exit=$($result.ExitCode) output=$($result.Output)"
  }
}

Assert-ContractTest 'Invoke-ProductionNodeScript preserves explicit non-zero exit code' {
  $probeScript = New-ProbeScript "process.stderr.write('probe_fail'); process.exit(7);"
  $result = Invoke-ProductionNodeScript -ScriptPath $probeScript -TimeoutSeconds 30
  if ($result.ExitCode -ne 7) {
    throw "Expected exit code 7, got $($result.ExitCode)"
  }
}

Assert-ContractTest 'Invoke-ProductionNodeScript with zero Node arguments succeeds' {
  $probeScript = New-ProbeScript "process.stdout.write('probe_ok');"
  $result = Invoke-ProductionNodeScript -ScriptPath $probeScript -TimeoutSeconds 30
  if ($result.ExitCode -ne 0 -or $result.Output.Trim() -ne 'probe_ok') {
    throw "Unexpected probe result: exit=$($result.ExitCode) output=$($result.Output)"
  }
}

Assert-ContractTest 'Invoke-ProductionNodeScript rejects null NodeArgs collection' {
  Assert-ThrowsLike {
    Invoke-ProductionNodeScript -ScriptPath 'scripts/example.mjs' -NodeArgs $null
  } 'must not be null'
}

Assert-ContractTest 'Invoke-ProductionNodeScript rejects null element in NodeArgs' {
  Assert-ThrowsLike {
    Invoke-ProductionNodeScript -ScriptPath 'scripts/example.mjs' -NodeArgs @([string]'--apply', [object]$null)
  } 'argument at index 1 is null'
}

Assert-ContractTest 'Invoke-ProductionNodeScript timeout terminates child process tree and fails non-zero' {
  $probeScript = New-ProbeScript "setInterval(() => {}, 1000);"
  Assert-ThrowsLike {
    Invoke-ProductionNodeScript -ScriptPath $probeScript -TimeoutSeconds 2
  } 'timed out'
}

Assert-ContractTest 'resolver temp file is removed after child success' {
  $probeScript = New-ProbeScript @'
import fs from 'node:fs';
fs.writeFileSync(process.env.REVE_ANON_KEY_OUTPUT_PATH, '{"projectRef":"probe","anonKey":"probe"}');
process.stdout.write('resolver_ok');
'@
  Invoke-ResolverKeysFileLifecycleProbe -InvokeChild {
    param($KeysFile)
    $result = Invoke-ProductionNodeScript -ScriptPath $probeScript -TimeoutSeconds 30
    if ($result.ExitCode -ne 0) {
      throw "Expected success exit code, got $($result.ExitCode) output=$($result.Output)"
    }
  }
}

Assert-ContractTest 'resolver temp file is removed after child failure' {
  $probeScript = New-ProbeScript "process.stderr.write('fail'); process.exit(3);"
  try {
    Invoke-ResolverKeysFileLifecycleProbe -InvokeChild {
      param($KeysFile)
      $result = Invoke-ProductionNodeScript -ScriptPath $probeScript -TimeoutSeconds 30
      if ($result.ExitCode -ne 3) {
        throw "Expected exit code 3, got $($result.ExitCode)"
      }
    }
  }
  catch {
    if ($_.Exception.Message -notmatch 'Expected exit code 3') {
      throw
    }
  }
}

Assert-ContractTest 'resolver temp file is removed after child timeout' {
  $probeScript = New-ProbeScript "setInterval(() => {}, 1000);"
  try {
    Invoke-ResolverKeysFileLifecycleProbe -InvokeChild {
      param($KeysFile)
      Invoke-ProductionNodeScript -ScriptPath $probeScript -TimeoutSeconds 2 | Out-Null
    }
  }
  catch {
    if ($_.Exception.Message -notmatch 'timed out') {
      throw
    }
  }
}

foreach ($probeScript in $probeScripts) {
  Remove-Item $probeScript -Force -ErrorAction SilentlyContinue
}

$unexpectedTempFiles = Get-ChildItem -Path $env:TEMP -Filter 'reve-prod-keys-*.json' -ErrorAction SilentlyContinue
if ($unexpectedTempFiles -and $unexpectedTempFiles.Count -gt 0) {
  $failures += 'unexpected resolver temp files remain'
  Write-Host "FAIL unexpected resolver temp files remain"
  Write-Host "  count=$($unexpectedTempFiles.Count)"
}

$unexpectedProbeFiles = Get-ChildItem -Path $env:TEMP -Filter 'reve-node-probe-*.mjs' -ErrorAction SilentlyContinue
if ($unexpectedProbeFiles -and $unexpectedProbeFiles.Count -gt 0) {
  $failures += 'unexpected probe temp files remain'
  Write-Host "FAIL unexpected probe temp files remain"
  Write-Host "  count=$($unexpectedProbeFiles.Count)"
}

if ($failures.Count -gt 0) {
  Write-Host ""
  Write-Host "Contract test failures: $($failures.Count)"
  exit 1
}

Write-Host ""
Write-Host 'All ProductionOperator contract tests passed.'
exit 0
