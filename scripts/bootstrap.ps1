param(
    [switch]$InstallOnly,
    [switch]$StartOnly,
    [switch]$SkipFrontend,
    [switch]$SkipBackend
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$repoRoot = (Get-Item -Path (Join-Path -Path $scriptRoot -ChildPath '..')).FullName
$backendDir = Join-Path $repoRoot 'backend'
$frontendDir = Join-Path $repoRoot 'frontend'
$venvDir = Join-Path $repoRoot '.venv'
$envFile = Join-Path $repoRoot '.env'
$envTemplate = Join-Path $repoRoot '.env.example'
$startScript = Join-Path $scriptRoot 'start-all.ps1'
$logDir = Join-Path $repoRoot '.logs'

$doInstall = -not $StartOnly
$doStart = -not $InstallOnly

function Ensure-EnvFile {
    param(
        [string]$Template,
        [string]$Destination
    )

    if (-not (Test-Path $Destination)) {
        if (Test-Path $Template) {
            Copy-Item -Path $Template -Destination $Destination
            Write-Host "Created .env from template. Update the values with your secrets." -ForegroundColor Yellow
        }
        else {
            Write-Warning ".env template was not found. Create $Destination manually before starting services."
        }
    }
}

function Get-PythonExecutable {
    if (Test-Path (Join-Path $venvDir 'Scripts\python.exe')) {
        return (Join-Path $venvDir 'Scripts\python.exe')
    }

    $candidates = @('py', 'python3', 'python')
    foreach ($candidate in $candidates) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) {
            if ($command.Name -eq 'py') {
                try {
                    $python = & $command.Source -3 -c "import sys; print(sys.executable)"
                    if ($LASTEXITCODE -eq 0 -and $python) {
                        return $python.Trim()
                    }
                }
                catch {
                    continue
                }
            }
            else {
                return $command.Source
            }
        }
    }

    throw 'Python 3 is required but was not found on PATH.'
}

function Ensure-VirtualEnv {
    if ($SkipBackend) { return }

    if (-not (Test-Path $venvDir)) {
        $python = Get-PythonExecutable
        Write-Host "Creating Python virtual environment..."
        & $python -m venv $venvDir
    }
}

function Install-BackendDependencies {
    if ($SkipBackend) { return }

    $python = Get-PythonExecutable
    Write-Host "Installing backend requirements..."
    & $python -m pip install --upgrade pip wheel
    & $python -m pip install -r (Join-Path $backendDir 'requirements.txt')
}

function Install-FrontendDependencies {
    if ($SkipFrontend) { return }

    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npm) {
        throw 'npm not found. Install Node.js 20+ or use the devcontainer.'
    }

    Write-Host "Installing frontend dependencies..."
    Push-Location $frontendDir
    try {
        & $npm.Source install
    }
    finally {
        Pop-Location
    }
}

if ($doInstall) {
    Ensure-EnvFile -Template $envTemplate -Destination $envFile
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    Ensure-VirtualEnv
    Install-BackendDependencies
    Install-FrontendDependencies
}

if ($doStart) {
    if (-not (Test-Path $startScript)) {
        throw "Start script '$startScript' not found."
    }

    $args = @()
    if ($SkipFrontend) { $args += '-SkipFrontend' }
    if ($SkipBackend) { $args += '-SkipBackend' }

    Write-Host "Launching services..."
    & $startScript @args
}
