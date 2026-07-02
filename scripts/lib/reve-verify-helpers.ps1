function Invoke-PgtapSuite {
  param(
    [Parameter(Mandatory = $true)][string]$Label
  )

  Write-Host "=== $Label ==="
  $previousErrorAction = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $output = npx supabase test db 2>&1 | Out-String
  }
  finally {
    $ErrorActionPreference = $previousErrorAction
  }
  Write-Host $output

  if ($output -notmatch 'Result: PASS') {
    throw "$Label failed: Result: PASS not found in output"
  }

  if ($output -match 'Files=\d+,\s*Tests=(\d+)') {
    Write-Host "$Label assertion count: $($Matches[1])"
    return [int]$Matches[1]
  }

  return $null
}

function Invoke-DbLintBaseline {
  Write-Host '=== db lint baseline verification ==='
  $scriptsRoot = Split-Path -Parent $PSScriptRoot
  & (Join-Path $scriptsRoot 'verify_db_lint_baseline.ps1')
  if ($LASTEXITCODE -ne 0) {
    throw "db lint baseline verification failed with exit code $LASTEXITCODE"
  }
}
