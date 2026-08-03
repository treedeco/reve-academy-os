# Shared helpers for production operator PowerShell runners.
# Dot-source from scripts/*.ps1 — never log secrets.

function Write-ProductionOperatorStage {
  param([string]$Stage)

  Write-Host "[production-operator] stage=$Stage"
}

function Assert-ProductionProjectRefConfirmed {
  param(
    [Parameter(Mandatory = $true)][string]$ProvidedRef,
    [string]$ExpectedRef = 'bfhptqhgxignyggyxxkx'
  )

  $normalized = $ProvidedRef.Trim()
  if ($normalized.Length -eq 0) {
    throw 'Production project ref confirmation is required.'
  }
  if ($normalized -ne $ExpectedRef) {
    throw "Production project ref mismatch: expected $ExpectedRef."
  }

  return $normalized
}

function Read-SecureBackupEncryptionPassphrase {
  Remove-Item Env:REVE_BACKUP_ENCRYPTION_PASSPHRASE -ErrorAction SilentlyContinue
  Write-Host 'Enter the backup encryption passphrase (min 12 chars). Input is hidden. This is NOT stored in the manifest.'
  $secure = Read-Host 'Backup encryption passphrase' -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    $env:REVE_BACKUP_ENCRYPTION_PASSPHRASE = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
  }
  finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    $secure.Dispose()
  }
}

function Read-SecureProductionDbPassword {
  Remove-Item Env:REVE_PRODUCTION_DB_PASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
  Write-Host 'Enter the production Postgres password (Supabase Dashboard -> Project Settings -> Database). Input is hidden.'
  $securePassword = Read-Host 'Production database password' -AsSecureString
  $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
  try {
    $env:REVE_PRODUCTION_DB_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto($passwordPointer)
  }
  finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    $securePassword.Dispose()
    Remove-Variable securePassword, passwordPointer -ErrorAction SilentlyContinue
  }
}

function Read-SecureProductionOwnerPassword {
  Remove-Item Env:PRODUCTION_OWNER_PASSWORD -ErrorAction SilentlyContinue
  Write-Host 'Enter the production Owner password used at /login (username: reve). Input is hidden.'
  $securePassword = Read-Host 'Production Owner password' -AsSecureString
  $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
  try {
    $env:PRODUCTION_OWNER_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto($passwordPointer)
  }
  finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    $securePassword.Dispose()
    Remove-Variable securePassword, passwordPointer -ErrorAction SilentlyContinue
  }
}

function Read-SecurePlainText {
  param([string]$Prompt)
  $secure = Read-Host $Prompt -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    return [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
  }
  finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    $secure.Dispose()
  }
}

function Assert-ProductionConfirmed {
  param([switch]$ConfirmProduction)

  if (-not $ConfirmProduction) {
    throw 'Explicit production confirmation is required. Re-run with -ConfirmProduction.'
  }

  $script:SavedReveConfirmProduction = $env:REVE_CONFIRM_PRODUCTION
  $env:REVE_CONFIRM_PRODUCTION = '1'
}

function Restore-ProductionConfirmation {
  if (Get-Variable -Name SavedReveConfirmProduction -Scope Script -ErrorAction SilentlyContinue) {
    if ($null -ne $script:SavedReveConfirmProduction -and $script:SavedReveConfirmProduction -ne '') {
      $env:REVE_CONFIRM_PRODUCTION = $script:SavedReveConfirmProduction
    }
    else {
      Remove-Item Env:REVE_CONFIRM_PRODUCTION -ErrorAction SilentlyContinue
    }
    Remove-Variable SavedReveConfirmProduction -Scope Script -ErrorAction SilentlyContinue
  }
}

function Set-ProductionSupabaseAnonKey {
  param(
    [string]$ProjectRef = 'bfhptqhgxignyggyxxkx',
    [int]$TimeoutSeconds = 120
  )

  if ($ProjectRef -ne 'bfhptqhgxignyggyxxkx') {
    throw "Refusing production operator action for unexpected project ref: $ProjectRef"
  }

  Write-ProductionOperatorStage 'resolve_anon_key_start'
  $keysFile = Join-Path $env:TEMP ("reve-prod-keys-$([Guid]::NewGuid().ToString()).json")
  $env:REVE_ANON_KEY_OUTPUT_PATH = $keysFile
  $env:REVE_SUPABASE_PROJECT_REF = $ProjectRef

  try {
    $result = Invoke-ProductionNodeScript `
      -ScriptPath 'scripts/lib/resolve-production-supabase-anon-key.mjs' `
      -TimeoutSeconds $TimeoutSeconds

    if ($result.Output.Trim().Length -gt 0) {
      Write-Host $result.Output.Trim()
    }

    if ($result.ExitCode -ne 0) {
      throw 'Failed to resolve production anon key.'
    }
    if (-not (Test-Path $keysFile)) {
      throw 'Production anon key output file was not created.'
    }

    $keysPayload = Get-Content $keysFile -Raw | ConvertFrom-Json
    if ($keysPayload.projectRef -ne $ProjectRef) {
      throw 'Production anon key project ref mismatch.'
    }
    if ([string]::IsNullOrWhiteSpace($keysPayload.anonKey)) {
      throw 'Failed to resolve production anon key.'
    }

    $env:PRODUCTION_SUPABASE_URL = "https://$ProjectRef.supabase.co"
    $env:PRODUCTION_SUPABASE_ANON_KEY = $keysPayload.anonKey
    $env:PRODUCTION_URL = 'https://reve-academy-os.vercel.app'
    Write-ProductionOperatorStage 'resolve_anon_key_complete'
  }
  finally {
    Remove-Item $keysFile -Force -ErrorAction SilentlyContinue
    Remove-Item Env:REVE_ANON_KEY_OUTPUT_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:REVE_SUPABASE_PROJECT_REF -ErrorAction SilentlyContinue
  }
}

function Resolve-ProductionNodeProcessArguments {
  param(
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [AllowNull()][object[]]$NodeArgs = @()
  )

  if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
    Write-ProductionOperatorStage 'node_args_invalid reason=missing_script_path'
    throw 'Node script path is required.'
  }

  if ($null -eq $NodeArgs) {
    Write-ProductionOperatorStage 'node_args_invalid reason=null_node_args_collection'
    throw 'Node script arguments must not be null; omit the parameter or pass an empty array.'
  }

  $validatedArgs = New-Object System.Collections.Generic.List[string]
  for ($index = 0; $index -lt $NodeArgs.Count; $index++) {
    $value = $NodeArgs[$index]
    if ($null -eq $value) {
      Write-ProductionOperatorStage "node_args_invalid reason=null_element index=$index"
      throw "Node script argument at index $index is null."
    }
    if ($value -isnot [string]) {
      Write-ProductionOperatorStage "node_args_invalid reason=invalid_type index=$index"
      throw "Node script argument at index $index must be a string."
    }
    [void]$validatedArgs.Add($value)
  }

  if ($validatedArgs.Count -eq 0) {
    return ,@($ScriptPath)
  }

  return ,(@($ScriptPath) + @($validatedArgs.ToArray()))
}

function Resolve-ProductionChildProcessExitCode {
  param(
    [Parameter(Mandatory = $true)]
    $Process,
    [int]$RetryCount = 5,
    [int]$RetryDelayMs = 50
  )

  if ($null -eq $Process) {
    Write-ProductionOperatorStage 'process_exit_code_unavailable reason=null_process'
    throw 'Child process exit code is unavailable.'
  }

  if (-not $Process.HasExited) {
    Write-ProductionOperatorStage 'process_exit_code_unavailable reason=process_not_exited'
    throw 'Child process exit code is unavailable because the process has not exited.'
  }

  for ($attempt = 0; $attempt -le $RetryCount; $attempt++) {
    try {
      $Process.Refresh()
    }
    catch {
      # Refresh can race briefly after WaitForExit; retry within the finite window.
    }

    if ($null -ne $Process.ExitCode) {
      return [int]$Process.ExitCode
    }

    if ($attempt -lt $RetryCount) {
      Start-Sleep -Milliseconds $RetryDelayMs
    }
  }

  Write-ProductionOperatorStage 'process_exit_code_unavailable reason=exit_code_null_after_refresh'
  throw 'Child process exit code is unavailable after process exit.'
}

function ConvertTo-ProductionProcessArgumentsString {
  param(
    [Parameter(Mandatory = $true)][string[]]$ArgumentList
  )

  return (($ArgumentList | ForEach-Object {
    $arg = [string]$_
    if ($arg -match '[\s"]') {
      '"' + ($arg -replace '\\', '\\' -replace '"', '\"') + '"'
    }
    else {
      $arg
    }
  }) -join ' ')
}

function Resolve-ProductionCmdWrappedExitCode {
  param(
    [Parameter(Mandatory = $true)]
    $Process,
    [string]$ExitCodeFile,
    [int]$RetryCount = 5,
    [int]$RetryDelayMs = 50
  )

  for ($attempt = 0; $attempt -le $RetryCount; $attempt++) {
    try {
      $Process.Refresh()
    }
    catch {
      # Refresh can race briefly after WaitForExit; retry within the finite window.
    }

    if ($null -ne $Process.ExitCode) {
      return [int]$Process.ExitCode
    }

    if ($ExitCodeFile -and (Test-Path $ExitCodeFile)) {
      $rawContent = Get-Content $ExitCodeFile -Raw -ErrorAction SilentlyContinue
      if ($null -ne $rawContent) {
        $raw = $rawContent.Trim()
        if ($raw -match '^\d+$') {
          return [int]$raw
        }
      }
    }

    if ($attempt -lt $RetryCount) {
      Start-Sleep -Milliseconds $RetryDelayMs
    }
  }

  Write-ProductionOperatorStage 'process_exit_code_unavailable reason=exit_code_null_after_refresh'
  throw 'Child process exit code is unavailable after process exit.'
}

function Invoke-ProductionNodeScript {
  param(
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [object[]]$NodeArgs = @(),
    [int]$TimeoutSeconds = 180
  )

  $argumentList = Resolve-ProductionNodeProcessArguments -ScriptPath $ScriptPath -NodeArgs $NodeArgs

  Write-ProductionOperatorStage "node_start script=$ScriptPath"
  $stdoutFile = [System.IO.Path]::GetTempFileName()
  $stderrFile = [System.IO.Path]::GetTempFileName()
  $exitCodeFile = [System.IO.Path]::GetTempFileName()
  $process = $null

  try {
    $nodeCommand = 'node ' + (ConvertTo-ProductionProcessArgumentsString -ArgumentList $argumentList)
    $process = Start-Process `
      -FilePath 'cmd.exe' `
      -ArgumentList @('/d', '/v:on', '/c', "$nodeCommand 1> `"$stdoutFile`" 2> `"$stderrFile`" & (echo !ERRORLEVEL!)> `"$exitCodeFile`"") `
      -NoNewWindow `
      -PassThru

    $finished = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $finished) {
      if ($process.Id) {
        if ($IsWindows -or $env:OS -match 'Windows') {
          Start-Process -FilePath 'taskkill' -ArgumentList @('/pid', $process.Id, '/t', '/f') -NoNewWindow -Wait -ErrorAction SilentlyContinue | Out-Null
        } else {
          Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
      }
      Write-ProductionOperatorStage "node_timeout after=${TimeoutSeconds}s"
      throw "Node script timed out after ${TimeoutSeconds}s ($ScriptPath)."
    }

    $stdout = if (Test-Path $stdoutFile) { Get-Content $stdoutFile -Raw -ErrorAction SilentlyContinue } else { '' }
    $stderr = if (Test-Path $stderrFile) { Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue } else { '' }
    $combinedOutput = @(
      if ($stdout) { $stdout.TrimEnd() }
      if ($stderr) { $stderr.TrimEnd() }
    ) -join [Environment]::NewLine

    $exitCode = Resolve-ProductionCmdWrappedExitCode -Process $process -ExitCodeFile $exitCodeFile
    Write-ProductionOperatorStage "node_complete exit=$exitCode"
    return @{
      Output = $combinedOutput
      ExitCode = $exitCode
    }
  }
  finally {
    if ($process -and -not $process.HasExited) {
      if ($IsWindows -or $env:OS -match 'Windows') {
        Start-Process -FilePath 'taskkill' -ArgumentList @('/pid', $process.Id, '/t', '/f') -NoNewWindow -Wait -ErrorAction SilentlyContinue | Out-Null
      } else {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
      }
    }
    if ($process) {
      $process.Dispose()
    }
    Remove-Item $stdoutFile -Force -ErrorAction SilentlyContinue
    Remove-Item $stderrFile -Force -ErrorAction SilentlyContinue
    Remove-Item $exitCodeFile -Force -ErrorAction SilentlyContinue
  }
}

function Clear-ProductionOperatorEnv {
  Remove-Item Env:PRODUCTION_SUPABASE_ANON_KEY -ErrorAction SilentlyContinue
  Remove-Item Env:PRODUCTION_OWNER_PASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:REVE_CONFIRM_PRODUCTION -ErrorAction SilentlyContinue
  Remove-Item Env:REVE_CONFIRM_RESTORE_VALIDATION -ErrorAction SilentlyContinue
  Remove-Item Env:REVE_CLEANUP_APPLY_RUN_ID -ErrorAction SilentlyContinue
  Remove-Item Env:REVE_ANON_KEY_OUTPUT_PATH -ErrorAction SilentlyContinue
  Remove-Item Env:REVE_SUPABASE_PROJECT_REF -ErrorAction SilentlyContinue
  Remove-Item Env:REVE_PRODUCTION_PROJECT_REF_CONFIRM -ErrorAction SilentlyContinue
  Remove-Item Env:REVE_PRODUCTION_DB_PASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:REVE_BACKUP_LABEL -ErrorAction SilentlyContinue
  Remove-Item Env:REVE_BACKUP_ENCRYPTION_PASSPHRASE -ErrorAction SilentlyContinue
  Remove-Item Env:REVE_BACKUP_DESTINATION -ErrorAction SilentlyContinue
  Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:NEW_OWNER_PASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:SUPABASE_SECRET_KEY -ErrorAction SilentlyContinue
  Remove-Item Env:SUPABASE_SERVICE_ROLE_KEY -ErrorAction SilentlyContinue
}
