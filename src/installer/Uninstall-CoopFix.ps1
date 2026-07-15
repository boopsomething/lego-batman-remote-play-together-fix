[CmdletBinding()]
param(
    [string]$SteamRoot,
    [string]$DonorDirectory,
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'

function Normalize-InputPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    return [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"').Trim())
}

function Add-UniqueExistingPath {
    param([System.Collections.Generic.List[string]]$List, [string]$Path)
    $candidate = Normalize-InputPath $Path
    if ([string]::IsNullOrWhiteSpace($candidate) -or -not (Test-Path -LiteralPath $candidate -PathType Container)) { return }
    $resolved = (Resolve-Path -LiteralPath $candidate).Path
    foreach ($existing in $List) {
        if ([string]::Equals($existing, $resolved, [StringComparison]::OrdinalIgnoreCase)) { return }
    }
    $List.Add($resolved)
}

function Add-LibrariesFromVdf {
    param([System.Collections.Generic.List[string]]$Roots)
    foreach ($baseRoot in @($Roots)) {
        $libraryFile = Join-Path $baseRoot 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $libraryFile -PathType Leaf)) { continue }
        $content = Get-Content -LiteralPath $libraryFile -Raw -Encoding UTF8
        foreach ($match in [regex]::Matches($content, '"path"\s+"([^"]+)"')) {
            Add-UniqueExistingPath $Roots ($match.Groups[1].Value.Replace('\\', '\'))
        }
    }
}

function Get-SteamLibraryRoots {
    $roots = New-Object 'System.Collections.Generic.List[string]'
    $explicitRoot = Normalize-InputPath $SteamRoot
    if ($explicitRoot) {
        Add-UniqueExistingPath $roots $explicitRoot
        if ($roots.Count -eq 0) { throw "Указанный SteamRoot не найден: $explicitRoot" }
        Add-LibrariesFromVdf $roots
        return $roots
    }

    foreach ($candidate in @(
        @{ Path = 'HKCU:\Software\Valve\Steam'; Name = 'SteamPath' },
        @{ Path = 'HKLM:\SOFTWARE\Valve\Steam'; Name = 'InstallPath' },
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam'; Name = 'InstallPath' }
    )) {
        try { Add-UniqueExistingPath $roots ((Get-ItemProperty -LiteralPath $candidate.Path -ErrorAction Stop).($candidate.Name)) } catch { }
    }

    foreach ($drive in Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue) {
        foreach ($relative in @('Steam', 'SteamLibrary', 'Games\Steam', 'Program Files (x86)\Steam', 'Program Files\Steam')) {
            Add-UniqueExistingPath $roots (Join-Path $drive.Root $relative)
        }
    }

    Add-LibrariesFromVdf $roots
    return $roots
}

function Find-DonorDirectory {
    $explicit = Normalize-InputPath $DonorDirectory
    if ($explicit) {
        if (Test-Path -LiteralPath $explicit -PathType Container) { return (Resolve-Path -LiteralPath $explicit).Path }
        throw "Папка BlastZone не найдена: $explicit"
    }

    foreach ($library in Get-SteamLibraryRoots) {
        $candidate = Join-Path $library 'steamapps\common\BlastZone 2 Demo'
        if (Test-Path -LiteralPath (Join-Path $candidate 'BlastZone2Demo.sotavpn-backup.exe') -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

$donorDirectory = Find-DonorDirectory
if (-not $donorDirectory) {
    if ($NonInteractive) { throw 'Установленный SOTAVPN COOP Fix не найден в библиотеках Steam.' }
    $donorDirectory = Normalize-InputPath (Read-Host 'Укажите папку BlastZone 2 Demo')
    if (-not (Test-Path -LiteralPath $donorDirectory -PathType Container)) { throw "Папка не найдена: $donorDirectory" }
    $donorDirectory = (Resolve-Path -LiteralPath $donorDirectory).Path
}

if (Get-Process -Name 'BlastZone2Demo', 'LEGOBatmanLotDK-Win64-Shipping' -ErrorAction SilentlyContinue) {
    throw 'Закройте LEGO Batman и BlastZone 2 Demo перед удалением фикса.'
}

$activeExe = Join-Path $donorDirectory 'BlastZone2Demo.exe'
$backupExe = Join-Path $donorDirectory 'BlastZone2Demo.sotavpn-backup.exe'
$restoreTemp = Join-Path $donorDirectory 'BlastZone2Demo.sotavpn-restore.exe'

if (-not (Test-Path -LiteralPath $backupExe -PathType Leaf)) { throw "Резервная копия BlastZone не найдена: $backupExe" }
if ((Get-Item -LiteralPath $backupExe).Length -le 100000) { throw 'Резервная копия выглядит некорректно: размер слишком мал.' }

$expectedHash = (Get-FileHash -LiteralPath $backupExe -Algorithm SHA256).Hash
try {
    Copy-Item -LiteralPath $backupExe -Destination $restoreTemp -Force
    if ((Get-FileHash -LiteralPath $restoreTemp -Algorithm SHA256).Hash -ne $expectedHash) {
        throw 'Проверка временной копии оригинального EXE не пройдена.'
    }
    Move-Item -LiteralPath $restoreTemp -Destination $activeExe -Force
    if ((Get-FileHash -LiteralPath $activeExe -Algorithm SHA256).Hash -ne $expectedHash) {
        throw 'Проверка восстановленного EXE по SHA-256 не пройдена.'
    }
} finally {
    Remove-Item -LiteralPath $restoreTemp -Force -ErrorAction SilentlyContinue
}

foreach ($name in @(
    'SOTAVPN-CoopLauncher.ini',
    'SOTAVPN-CoopLauncher.ini.new',
    'SOTAVPN-COOP-README.md',
    'SOTAVPN-COOP-README.txt',
    'SOTAVPN_GAMING.url'
)) {
    Remove-Item -LiteralPath (Join-Path $donorDirectory $name) -Force -ErrorAction SilentlyContinue
}

Remove-Item -LiteralPath $backupExe -Force

Write-Host ''
Write-Host 'SOTAVPN COOP Fix удалён. Оригинальный BlastZone2Demo.exe восстановлен.' -ForegroundColor Green
Write-Host "Папка: $donorDirectory"
Write-Host "SHA-256 оригинала: $expectedHash"

