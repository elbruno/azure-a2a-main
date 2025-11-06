param(
    [switch]$SkipFrontend,
    [switch]$SkipBackend
)

$ErrorActionPreference = 'Stop'

function Resolve-RepoPath {
    param([string]$RelativePath)
    $repoRoot = (Get-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).FullName
    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        return $repoRoot
    }
    return (Join-Path -Path $repoRoot -ChildPath $RelativePath)
}

function New-LogFile {
    param(
        [string]$LogPath
    )
    $logDir = Split-Path -Path $LogPath -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    if (-not (Test-Path $LogPath)) {
        New-Item -ItemType File -Path $LogPath -Force | Out-Null
    }
}

function Start-ServiceProcess {
    param(
        [string]$Name,
        [string]$FilePath,
        [string]$Arguments,
        [string]$WorkingDirectory,
        [string]$LogPath
    )

    New-LogFile -LogPath $LogPath

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    # Preserve existing PATH so npm/python still resolve child tools
    $envPath = [System.Environment]::GetEnvironmentVariable('PATH', 'Process')
    $psi.Environment['PATH'] = $envPath

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    $process.EnableRaisingEvents = $true

    $encoding = New-Object System.Text.UTF8Encoding($false)
    $writer = New-Object System.IO.StreamWriter($LogPath, $true, $encoding)
    $syncRoot = New-Object object

    $writeLine = {
        param([string]$Line)
        if ([string]::IsNullOrWhiteSpace($Line)) { return }
        $timestamp = (Get-Date).ToString('u')
        $message = "[{0}] {1}" -f $Name, $Line
        Write-Host $message
        [System.Threading.Monitor]::Enter($syncRoot)
        try {
            $writer.WriteLine("{0} {1}" -f $timestamp, $message)
            $writer.Flush()
        }
        finally {
            [System.Threading.Monitor]::Exit($syncRoot)
        }
    }

    $outputHandler = [System.Diagnostics.DataReceivedEventHandler] { param($sender, $args) $args.Data | ForEach-Object { & $using:writeLine $_ } }
    $errorHandler = [System.Diagnostics.DataReceivedEventHandler] { param($sender, $args) $args.Data | ForEach-Object { & $using:writeLine $_ } }

    $process.add_OutputDataReceived($outputHandler)
    $process.add_ErrorDataReceived($errorHandler)

    $process.Start() | Out-Null
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()

    return [pscustomobject]@{
        Name          = $Name
        Process       = $process
        Writer        = $writer
        OutputHandler = $outputHandler
        ErrorHandler  = $errorHandler
    }
}

function Stop-ServiceProcess {
    param($Service)
    if ($null -eq $Service) { return }

    try {
        if ($Service.Process -and -not $Service.Process.HasExited) {
            Write-Host "Stopping $($Service.Name) (PID $($Service.Process.Id))"
            try {
                $Service.Process.Kill()
            }
            catch {
                $Service.Process.CloseMainWindow() | Out-Null
            }
            $Service.Process.WaitForExit()
        }
    }
    catch {
        Write-Warning "Failed to stop $($Service.Name): $_"
    }
    finally {
        if ($Service.OutputHandler) {
            $Service.Process.remove_OutputDataReceived($Service.OutputHandler)
        }
        if ($Service.ErrorHandler) {
            $Service.Process.remove_ErrorDataReceived($Service.ErrorHandler)
        }
        if ($Service.Writer) {
            $Service.Writer.Dispose()
        }
        if ($Service.Process) {
            $Service.Process.Dispose()
        }
    }
}

$repoRoot = Resolve-RepoPath ''
$backendDir = Resolve-RepoPath 'backend'
$frontendDir = Resolve-RepoPath 'frontend'
$logDir = Resolve-RepoPath '.logs'
$backendLog = Join-Path $logDir 'backend.log'
$frontendLog = Join-Path $logDir 'frontend.log'

$services = @()

try {
    if (-not $SkipBackend) {
        $pythonPath = Join-Path $repoRoot '.venv\Scripts\python.exe'
        if (-not (Test-Path $pythonPath)) {
            $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
            if (-not $pythonCmd) {
                throw "Python executable not found. Run bootstrap.ps1 to install dependencies."
            }
            $pythonPath = $pythonCmd.Source
        }

        Write-Host "Starting backend service..."
        $services += Start-ServiceProcess -Name 'backend' -FilePath $pythonPath -Arguments 'backend_production.py' -WorkingDirectory $backendDir -LogPath $backendLog
    }

    if (-not $SkipFrontend) {
        $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
        if (-not $npmCmd) {
            throw "npm is not available on PATH. Install Node.js 20+ or run inside the devcontainer."
        }

        Write-Host "Starting frontend service..."
        $services += Start-ServiceProcess -Name 'frontend' -FilePath $npmCmd.Source -Arguments 'run dev' -WorkingDirectory $frontendDir -LogPath $frontendLog
    }

    if ($services.Count -eq 0) {
        Write-Warning 'No services selected to start.'
        return
    }

    Write-Host "All services started. Press Ctrl+C to stop them."

    while ($true) {
        Start-Sleep -Seconds 1
        foreach ($svc in $services) {
            if ($svc.Process.HasExited) {
                $exitCode = $svc.Process.ExitCode
                Write-Warning "Service '$($svc.Name)' exited with code $exitCode."
                return
            }
        }
    }
}
catch [System.Exception] {
    Write-Warning $_.Exception.Message
}
finally {
    foreach ($svc in $services) {
        Stop-ServiceProcess -Service $svc
    }
}
