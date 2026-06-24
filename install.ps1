$ErrorActionPreference = 'Stop'

function Write-Info($Message) {
    Write-Host $Message -ForegroundColor Green
}

function Write-Warn($Message) {
    Write-Host $Message -ForegroundColor Yellow
}

function Fail($Message) {
    Write-Host $Message -ForegroundColor Red
    exit 1
}

function Get-PlainTextPassword {
    $secure = Read-Host -Prompt 'Enter password' -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Get-SevenZip {
    foreach ($name in @('7zz.exe', '7z.exe', '7za.exe')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) {
            return $cmd.Source
        }
    }

    foreach ($path in @(
        "$env:ProgramFiles\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
    )) {
        if ($path -and (Test-Path $path)) {
            return $path
        }
    }

    return $null
}

$arch = $env:PROCESSOR_ARCHITECTURE
if ($arch -eq 'AMD64' -or $arch -eq 'X64') {
    $architecture = 'x64'
} elseif ($arch -eq 'ARM64') {
    $architecture = 'arm64'
} else {
    Fail "Unsupported architecture: $arch"
}

if ($architecture -eq 'x64') {
    try {
        $hasAvx2 = (Add-Type -MemberDefinition '[DllImport("kernel32.dll")] public static extern bool IsProcessorFeaturePresent(int ProcessorFeature);' -Name 'Kernel32' -Namespace 'Win32' -PassThru -ErrorAction Stop)::IsProcessorFeaturePresent(40)
    } catch {
        try {
            $hasAvx2 = ([Win32.Kernel32]::IsProcessorFeaturePresent(40))
        } catch {
            $hasAvx2 = $false
        }
    }

    if (-not $hasAvx2) {
        $architecture = 'x64-baseline'
    }
}

$zipName = "stellar-windows-$architecture.zip"
$url = "https://github.com/fatalflux/Stellarium/releases/latest/download/$zipName"

if (!(Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    Fail 'curl.exe is required but not found. Please install curl or upgrade Windows.'
}

$sevenZip = Get-SevenZip
if (!$sevenZip) {
    Fail '7-Zip is required to extract the AES-encrypted zip. Install 7-Zip, then rerun this script.'
}

$tempRoot = New-TemporaryFile
Remove-Item $tempRoot -Force
$tempDir = New-Item -ItemType Directory -Path $tempRoot
$zipPath = Join-Path $tempDir $zipName
$extractDir = Join-Path $tempDir 'extract'
New-Item -ItemType Directory -Path $extractDir | Out-Null

try {
    Write-Info "Downloading $zipName"
    & curl.exe -fsSL -o $zipPath $url
    if ($LASTEXITCODE -ne 0) {
        Fail "Download failed: $url"
    }

    $password = Get-PlainTextPassword
    if ([string]::IsNullOrEmpty($password)) {
        Fail 'Password cannot be empty.'
    }

    Write-Info 'Extracting encrypted archive'
    & $sevenZip x -y "-p$password" "-o$extractDir" $zipPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Fail 'Extraction failed. Check the password and archive.'
    }

    $binaryPath = Join-Path $extractDir 'trail.exe'
    if (!(Test-Path $binaryPath)) {
        Fail 'Archive did not contain a top-level trail.exe binary.'
    }

    $installDir = Join-Path $HOME '.local\bin'
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    $installPath = Join-Path $installDir 'trail.exe'

    $trailProcesses = Get-Process -Name 'trail' -ErrorAction SilentlyContinue
    if ($trailProcesses) {
        Write-Info 'Stopping old trail process(es)'
        Stop-Process -Name 'trail' -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }

    Copy-Item -Path $binaryPath -Destination $installPath -Force

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $pathParts = @()
    if ($userPath) {
        $pathParts = $userPath -split ';'
    }

    if (!($pathParts | Where-Object { $_.TrimEnd('\') -ieq $installDir.TrimEnd('\') })) {
        $nextUserPath = if ($userPath) { "$userPath;$installDir" } else { $installDir }
        [Environment]::SetEnvironmentVariable('Path', $nextUserPath, 'User')
        $env:PATH = "$installDir;$env:PATH"
        Write-Warn "Added $installDir to your user PATH. Restart your terminal if 'trail' is not found."
    } else {
        Write-Info 'PATH already configured'
    }

    Write-Info "Trail installed successfully to $installPath"
    Write-Warn "Run 'trail' to get started."
} finally {
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
