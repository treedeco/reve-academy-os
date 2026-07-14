function Stop-RevePlaywrightDevServerIfStale {
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [int]$Port = 3000
  )

  $listeners = @()
  try {
    $listeners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop)
  }
  catch {
    Write-Host "No listener on port $Port; Playwright will start a fresh dev server."
    return
  }

  if ($listeners.Count -eq 0) {
    Write-Host "No listener on port $Port; Playwright will start a fresh dev server."
    return
  }

  $repoMarker = [regex]::Escape($RepoRoot.Replace('\', '/').ToLowerInvariant())

  foreach ($listener in ($listeners | Select-Object -ExpandProperty OwningProcess -Unique)) {
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $listener" -ErrorAction SilentlyContinue
    if (-not $process) {
      throw "Port $Port is in use by PID $listener but the process could not be verified. Stop it manually before verification."
    }

    $commandLine = [string]$process.CommandLine
    $normalized = $commandLine.Replace('\', '/').ToLowerInvariant()
    $ownedByRepo = $normalized -match $repoMarker
    $isPlaywrightDevServer =
      $normalized -match 'next(\.cmd)?(\s+|")dev' -or
      $normalized -match 'npm(\.cmd)?\s+run\s+dev' -or
      $normalized -match 'next/dist/server/lib/start-server\.js'

    if (-not ($ownedByRepo -and $isPlaywrightDevServer)) {
      throw "Port $Port is in use by PID $listener with unverified command line '$commandLine'. Refusing to terminate unrelated processes."
    }

    Write-Host "Stopping verified Playwright dev server PID $listener on port $Port"
    Stop-Process -Id $listener -Force -ErrorAction Stop
  }
}
