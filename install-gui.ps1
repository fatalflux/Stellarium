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
} else {
    Fail "Unsupported architecture for Comet GUI: $arch"
}

$zipName = "stellarium-windows-$architecture.zip"
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

    $installerPath = Join-Path $extractDir 'Comet Setup.exe'
    if (!(Test-Path $installerPath)) {
        $installer = Get-ChildItem -Path $extractDir -Filter '*.exe' -File | Select-Object -First 1
        if (!$installer) {
            Fail 'Archive did not contain a top-level Comet installer executable.'
        }
        $installerPath = $installer.FullName
    }

    Write-Info "Launching Comet installer: $installerPath"
    $process = Start-Process -FilePath $installerPath -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        Fail "Comet installer exited with code $($process.ExitCode)."
    }

    Write-Info 'Comet GUI installer completed.'
    Write-Warn 'Launch Comet from the Start menu to get started.'
} finally {
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
