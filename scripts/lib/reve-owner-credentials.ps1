function Import-ReveEnvLocal {
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot
  )

  $envLocalPath = Join-Path $RepoRoot '.env.local'
  if (-not (Test-Path $envLocalPath)) {
    return
  }

  Get-Content $envLocalPath | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith('#')) {
      return
    }
    $parts = $line -split '=', 2
    if ($parts.Count -ne 2) {
      return
    }
    $name = $parts[0].Trim()
    $value = $parts[1].Trim().Trim('"').Trim("'")
    if (-not [string]::IsNullOrWhiteSpace($name) -and [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
      Set-Item -Path "Env:$name" -Value $value
    }
  }
}

function Get-ReveOwnerSeedPassword {
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot
  )

  Import-ReveEnvLocal -RepoRoot $RepoRoot

  foreach ($name in @('OWNER_PASSWORD', 'E2E_OWNER_PASSWORD')) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if (-not [string]::IsNullOrWhiteSpace($value)) {
      return $value
    }
  }

  throw 'Owner seed password is not configured. Set OWNER_PASSWORD in .env.local (gitignored).'
}

function Get-ReveOwnerAuthEmail {
  return 'reve@owner.local'
}
