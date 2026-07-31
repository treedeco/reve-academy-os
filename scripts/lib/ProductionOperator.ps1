# Shared helpers for production operator PowerShell runners.
# Dot-source from scripts/*.ps1 — never log secrets.

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

  $env:REVE_CONFIRM_PRODUCTION = '1'
}

function Set-ProductionSupabaseAnonKey {
  param(
    [string]$ProjectRef = 'bfhptqhgxignyggyxxkx'
  )

  if ($ProjectRef -ne 'bfhptqhgxignyggyxxkx') {
    throw "Refusing production operator action for unexpected project ref: $ProjectRef"
  }

  $keysFile = Join-Path $env:TEMP ("reve-prod-keys-$([Guid]::NewGuid().ToString()).json")
  try {
    & npx supabase projects api-keys --project-ref $ProjectRef -o json | Out-File -FilePath $keysFile -Encoding utf8
    $keysPayload = Get-Content $keysFile -Raw | ConvertFrom-Json
    $anonKey = ($keysPayload | Where-Object { $_.id -eq 'anon' } | Select-Object -First 1).api_key
    if ([string]::IsNullOrWhiteSpace($anonKey)) {
      throw 'Failed to resolve production anon key.'
    }

    $env:PRODUCTION_SUPABASE_URL = "https://$ProjectRef.supabase.co"
    $env:PRODUCTION_SUPABASE_ANON_KEY = $anonKey
    $env:PRODUCTION_URL = 'https://reve-academy-os.vercel.app'
  }
  finally {
    Remove-Item $keysFile -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-ProductionNodeScript {
  param(
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$NodeArgs
  )

  $previousErrorAction = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $lines = @(& node $ScriptPath @NodeArgs 2>&1)
    return @{
      Output = ($lines | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) {
          $_.ToString()
        } else {
          [string]$_
        }
      }) -join [Environment]::NewLine
      ExitCode = $LASTEXITCODE
    }
  }
  finally {
    $ErrorActionPreference = $previousErrorAction
  }
}

function Clear-ProductionOperatorEnv {
  Remove-Item Env:PRODUCTION_SUPABASE_ANON_KEY -ErrorAction SilentlyContinue
  Remove-Item Env:REVE_CONFIRM_PRODUCTION -ErrorAction SilentlyContinue
  Remove-Item Env:REVE_CLEANUP_APPLY_RUN_ID -ErrorAction SilentlyContinue
  Remove-Item Env:NEW_OWNER_PASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:SUPABASE_SECRET_KEY -ErrorAction SilentlyContinue
  Remove-Item Env:SUPABASE_SERVICE_ROLE_KEY -ErrorAction SilentlyContinue
}
