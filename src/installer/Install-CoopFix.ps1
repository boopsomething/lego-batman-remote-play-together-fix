[CmdletBinding()]
param(
    [string]$GameRoot,
    [string]$SteamRoot,
    [string]$DonorDirectory,
    [switch]$NonInteractive,
    [switch]$SkipVcRuntimeCheck
)

$ErrorActionPreference = 'Stop'

$internalRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$packageRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $internalRoot)).Path
$launcherSource = Join-Path $internalRoot 'Launcher\BlastZone2Demo.exe'
$readmeSource = Join-Path $packageRoot 'README.md'
$sotaLinkSource = Join-Path $packageRoot 'SOTAVPN_GAMING.url'
$vcRuntimeLinkSource = Join-Path $internalRoot 'Prerequisites\INSTALL_VC_RUNTIME.url'
$gameExeRelative = 'LEGOBatmanLotDK\Binaries\Win64\LEGOBatmanLotDK-Win64-Shipping.exe'
$expectedGameExeName = 'LEGOBatmanLotDK-Win64-Shipping.exe'
$knownDistributionHash = '07535E4FC4B78D5C3B9F8F299A41C69CC6AD423366FDA4EAF58BD8E3A3F64041'
$minimumVcRuntimeVersion = [Version]'14.38.0.0'
$vcRuntimeUrl = 'https://aka.ms/vc14/vc_redist.x64.exe'

function Normalize-InputPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    return [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"').Trim())
}

function Add-UniqueExistingPath {
    param([System.Collections.Generic.List[string]]$List, [string]$Path)
    $candidate = Normalize-InputPath $Path
    if ([string]::IsNullOrWhiteSpace($candidate) -or -not (Test-Path -LiteralPath $candidate -PathType Container)) {
        return
    }

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

    $registryCandidates = @(
        @{ Path = 'HKCU:\Software\Valve\Steam'; Name = 'SteamPath' },
        @{ Path = 'HKLM:\SOFTWARE\Valve\Steam'; Name = 'InstallPath' },
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam'; Name = 'InstallPath' }
    )

    foreach ($candidate in $registryCandidates) {
        try {
            Add-UniqueExistingPath $roots ((Get-ItemProperty -LiteralPath $candidate.Path -ErrorAction Stop).($candidate.Name))
        } catch { }
    }

    foreach ($drive in Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue) {
        foreach ($relative in @('Steam', 'SteamLibrary', 'Games\Steam', 'Program Files (x86)\Steam', 'Program Files\Steam')) {
            Add-UniqueExistingPath $roots (Join-Path $drive.Root $relative)
        }
    }

    Add-LibrariesFromVdf $roots

    return $roots
}

function Test-DonorFolder {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    foreach ($name in @('BlastZone2Demo.exe', 'BlastZone2Demo.sotavpn-backup.exe', 'BlastZone2Demo.original.exe')) {
        if (Test-Path -LiteralPath (Join-Path $Path $name) -PathType Leaf) { return $true }
    }
    return $false
}

function Find-BlastZoneDirectory {
    $explicit = Normalize-InputPath $DonorDirectory
    if ($explicit) {
        if (Test-DonorFolder $explicit) { return (Resolve-Path -LiteralPath $explicit).Path }
        throw "Указанная папка не похожа на BlastZone 2 Demo: $explicit"
    }

    foreach ($library in Get-SteamLibraryRoots) {
        $candidate = Join-Path $library 'steamapps\common\BlastZone 2 Demo'
        if (Test-DonorFolder $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    return $null
}

function Get-GameRootFromExecutable {
    param([string]$Executable)
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { return $null }
    if (-not [string]::Equals((Split-Path -Leaf $Executable), $expectedGameExeName, [StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    $directory = (Get-Item -LiteralPath $Executable).Directory
    if ($directory -and $directory.Parent -and $directory.Parent.Parent -and $directory.Parent.Parent.Parent) {
        return $directory.Parent.Parent.Parent.FullName
    }
    return $null
}

function Resolve-GameRoot {
    param([string]$InputPath)
    $candidate = Normalize-InputPath $InputPath
    if ([string]::IsNullOrWhiteSpace($candidate)) { return $null }

    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        if ([string]::Equals((Split-Path -Leaf $candidate), 'LEGOBatmanLotDK.exe', [StringComparison]::OrdinalIgnoreCase)) {
            $candidate = Split-Path -Parent $candidate
        } else {
            $candidate = Get-GameRootFromExecutable $candidate
        }
    } elseif (Test-Path -LiteralPath $candidate -PathType Container) {
        $directExe = Join-Path $candidate $gameExeRelative
        if (-not (Test-Path -LiteralPath $directExe -PathType Leaf)) {
            $nestedExe = Join-Path $candidate $expectedGameExeName
            $candidate = Get-GameRootFromExecutable $nestedExe
        }
    } else {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($candidate)) { return $null }
    $candidate = (Resolve-Path -LiteralPath $candidate).Path
    if (Test-Path -LiteralPath (Join-Path $candidate $gameExeRelative) -PathType Leaf) { return $candidate }
    return $null
}

function Get-RootFromExistingConfig {
    param([string]$ConfigPath)
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return $null }
    foreach ($line in Get-Content -LiteralPath $ConfigPath -Encoding UTF8) {
        if ($line -match '^\s*GameExecutable\s*=\s*(.+?)\s*$') {
            return Get-GameRootFromExecutable (Normalize-InputPath $Matches[1])
        }
    }
    return $null
}

function Find-DownloadedGameRoots {
    $matches = New-Object 'System.Collections.Generic.List[string]'
    $downloads = Join-Path $env:USERPROFILE 'Downloads'
    if (-not (Test-Path -LiteralPath $downloads -PathType Container)) { return $matches }

    foreach ($folder in Get-ChildItem -LiteralPath $downloads -Directory -ErrorAction SilentlyContinue) {
        $root = Resolve-GameRoot $folder.FullName
        if ($root) { Add-UniqueExistingPath $matches $root }
    }
    return $matches
}

function ConvertTo-Version {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $match = [regex]::Match($Value, '\d+\.\d+\.\d+(?:\.\d+)?')
    if (-not $match.Success) { return $null }
    try { return [Version]$match.Value } catch { return $null }
}

function Get-VcRuntimeStatus {
    param([string]$GameExecutable)

    $requiredFiles = @('MSVCP140.dll', 'VCRUNTIME140.dll', 'VCRUNTIME140_1.dll')
    $searchDirectories = @(
        (Split-Path -Parent $GameExecutable),
        (Join-Path $env:WINDIR 'System32')
    )
    $foundFiles = @{}

    foreach ($name in $requiredFiles) {
        foreach ($directory in $searchDirectories) {
            $candidate = Join-Path $directory $name
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $foundFiles[$name] = $candidate
                break
            }
        }
    }

    $missing = @($requiredFiles | Where-Object { -not $foundFiles.ContainsKey($_) })
    $versions = @(
        $foundFiles.Values |
            ForEach-Object { ConvertTo-Version (Get-Item -LiteralPath $_).VersionInfo.FileVersion } |
            Where-Object { $_ }
    )
    $lowestVersion = $versions | Sort-Object | Select-Object -First 1
    $sufficient = ($missing.Count -eq 0 -and $versions.Count -eq $requiredFiles.Count -and $lowestVersion -ge $minimumVcRuntimeVersion)

    return [pscustomobject]@{
        Sufficient = $sufficient
        Missing = $missing
        LowestVersion = $lowestVersion
        MinimumVersion = $minimumVcRuntimeVersion
    }
}

if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'Требуется 64-битная Windows 10 или Windows 11.'
}

foreach ($required in @($launcherSource, $readmeSource, $sotaLinkSource, $vcRuntimeLinkSource)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Пакет повреждён: отсутствует $required"
    }
}

$donorDirectory = Find-BlastZoneDirectory
if ([string]::IsNullOrWhiteSpace($donorDirectory)) {
    if ($NonInteractive) { throw 'BlastZone 2 Demo (AppID 349620) не найден в библиотеках Steam.' }
    Write-Host ''
    Write-Host 'BlastZone 2 Demo не найден автоматически.' -ForegroundColor Yellow
    Write-Host 'Установите его через steam://install/349620 или укажите папку вручную.'
    $donorDirectory = Normalize-InputPath (Read-Host 'Папка BlastZone 2 Demo')
    if (-not (Test-DonorFolder $donorDirectory)) { throw "Некорректная папка BlastZone 2 Demo: $donorDirectory" }
    $donorDirectory = (Resolve-Path -LiteralPath $donorDirectory).Path
}

$configPath = Join-Path $donorDirectory 'SOTAVPN-CoopLauncher.ini'
$resolvedGameRoot = Resolve-GameRoot $GameRoot
if (-not $resolvedGameRoot -and [string]::IsNullOrWhiteSpace($GameRoot)) {
    $resolvedGameRoot = Get-RootFromExistingConfig $configPath
    if ($resolvedGameRoot) { Write-Host "Сохранённый путь игры найден: $resolvedGameRoot" -ForegroundColor Cyan }
}

if (-not $resolvedGameRoot -and [string]::IsNullOrWhiteSpace($GameRoot)) {
    $autoMatches = @(Find-DownloadedGameRoots)
    if ($autoMatches.Count -eq 1) {
        $resolvedGameRoot = $autoMatches[0]
        Write-Host "Игра найдена автоматически: $resolvedGameRoot" -ForegroundColor Cyan
    } elseif ($NonInteractive) {
        throw 'GameRoot не указан, а автоматически найти единственную установку не удалось.'
    }
}

if (-not $resolvedGameRoot) {
    if ($NonInteractive) { throw "Некорректный GameRoot: $GameRoot" }
    Write-Host ''
    Write-Host 'Укажите корневую папку игры или сам LEGOBatmanLotDK-Win64-Shipping.exe.' -ForegroundColor Cyan
    $resolvedGameRoot = Resolve-GameRoot (Read-Host 'Путь к LEGO Batman')
    if (-not $resolvedGameRoot) { throw 'По указанному пути не найдена совместимая структура LEGO Batman.' }
}

$gameExecutable = Join-Path $resolvedGameRoot $gameExeRelative
$actualGameHash = (Get-FileHash -LiteralPath $gameExecutable -Algorithm SHA256).Hash
if ($actualGameHash -ne $knownDistributionHash) {
    Write-Warning 'SHA-256 основного EXE отличается от проверенной структуры раздачи.'
    Write-Warning "Проверенный: $knownDistributionHash"
    Write-Warning "Найденный:   $actualGameHash"
    Write-Warning 'Установка продолжится, но совместимость этой версии не гарантирована.'
}

$vcRuntime = Get-VcRuntimeStatus $gameExecutable
if (-not $vcRuntime.Sufficient) {
    Write-Host ''
    Write-Warning 'Для LEGO Batman требуется Microsoft Visual C++ v14 Redistributable x64 версии 14.38 или новее.'
    if ($vcRuntime.Missing.Count) { Write-Warning ('Не найдены: ' + ($vcRuntime.Missing -join ', ')) }
    if ($vcRuntime.LowestVersion) { Write-Warning "Найдена версия: $($vcRuntime.LowestVersion); требуется: $($vcRuntime.MinimumVersion) или новее." }
    Write-Host "Официальная загрузка Microsoft: $vcRuntimeUrl" -ForegroundColor Cyan

    if ($SkipVcRuntimeCheck) {
        Write-Warning 'Проверка Visual C++ Runtime пропущена параметром -SkipVcRuntimeCheck. Игра может не запуститься.'
    } elseif ($NonInteractive) {
        throw 'Установите Microsoft Visual C++ Redistributable x64 и повторно запустите INSTALL.cmd. Для осознанного пропуска используйте -SkipVcRuntimeCheck.'
    } else {
        Write-Host ''
        Write-Host '[O] Открыть официальную загрузку Microsoft' -ForegroundColor Cyan
        Write-Host '[S] Пропустить проверку и продолжить на свой риск' -ForegroundColor Yellow
        Write-Host '[Q] Отменить установку'
        $answer = (Read-Host 'Выбор [O/S/Q]').Trim()

        if ($answer -match '(?i)^(o|open|о|открыть)$') {
            Start-Process -FilePath $vcRuntimeLinkSource
            throw 'Официальная загрузка Microsoft открыта. Установите Visual C++ Redistributable x64 и снова запустите INSTALL.cmd.'
        } elseif ($answer -match '(?i)^(s|skip|п|пропустить)$') {
            Write-Warning 'Вы явно пропустили проверку Visual C++ Runtime. Игра может не запуститься.'
        } else {
            throw 'Установка отменена. Файлы BlastZone не изменялись.'
        }
    }
} else {
    Write-Host "Microsoft Visual C++ Runtime: OK ($($vcRuntime.LowestVersion))." -ForegroundColor DarkGray
}

if (Get-Process -Name 'BlastZone2Demo', 'LEGOBatmanLotDK-Win64-Shipping' -ErrorAction SilentlyContinue) {
    throw 'Закройте LEGO Batman и BlastZone 2 Demo перед установкой.'
}

$activeDonorExe = Join-Path $donorDirectory 'BlastZone2Demo.exe'
$backupDonorExe = Join-Path $donorDirectory 'BlastZone2Demo.sotavpn-backup.exe'
$legacyBackup = Join-Path $donorDirectory 'BlastZone2Demo.original.exe'
$launcherTemp = Join-Path $donorDirectory 'BlastZone2Demo.sotavpn-new.exe'
$configTemp = Join-Path $donorDirectory 'SOTAVPN-CoopLauncher.ini.new'
$backupWasCreated = $false

if (-not (Test-Path -LiteralPath $backupDonorExe -PathType Leaf)) {
    $backupCandidate = $null
    if ((Test-Path -LiteralPath $legacyBackup -PathType Leaf) -and (Get-Item -LiteralPath $legacyBackup).Length -gt 100000) {
        $backupCandidate = $legacyBackup
    } elseif ((Test-Path -LiteralPath $activeDonorExe -PathType Leaf) -and (Get-Item -LiteralPath $activeDonorExe).Length -gt 100000) {
        $backupCandidate = $activeDonorExe
    }

    if (-not $backupCandidate) {
        throw 'Оригинальный BlastZone2Demo.exe не найден. Выполните проверку файлов BlastZone в Steam и повторите установку.'
    }
    Copy-Item -LiteralPath $backupCandidate -Destination $backupDonorExe
    $backupWasCreated = $true
}

if ((Get-Item -LiteralPath $backupDonorExe).Length -le 100000) {
    throw 'Резервная копия BlastZone выглядит некорректно. Выполните проверку файлов игры в Steam.'
}

$backupHash = (Get-FileHash -LiteralPath $backupDonorExe -Algorithm SHA256).Hash
$sourceHash = (Get-FileHash -LiteralPath $launcherSource -Algorithm SHA256).Hash

try {
    $configLines = @(
        '# SOTAVPN LEGO Batman Remote Play Together Launcher',
        ('GameExecutable=' + $gameExecutable)
    )
    [IO.File]::WriteAllLines($configTemp, $configLines, (New-Object Text.UTF8Encoding($false)))

    Copy-Item -LiteralPath $launcherSource -Destination $launcherTemp -Force
    if ((Get-FileHash -LiteralPath $launcherTemp -Algorithm SHA256).Hash -ne $sourceHash) {
        throw 'Проверка подготовленного launcher по SHA-256 не пройдена.'
    }

    Move-Item -LiteralPath $configTemp -Destination $configPath -Force
    Move-Item -LiteralPath $launcherTemp -Destination $activeDonorExe -Force

    Copy-Item -LiteralPath $readmeSource -Destination (Join-Path $donorDirectory 'SOTAVPN-COOP-README.md') -Force
    Copy-Item -LiteralPath $sotaLinkSource -Destination (Join-Path $donorDirectory 'SOTAVPN_GAMING.url') -Force

    $selfTest = Start-Process -FilePath $activeDonorExe -ArgumentList @('--self-test', '--config', ('"' + $configPath + '"')) -Wait -PassThru
    if ($selfTest.ExitCode -ne 0) { throw "Self-test launcher завершился с кодом $($selfTest.ExitCode)." }
} catch {
    Remove-Item -LiteralPath $launcherTemp, $configTemp -Force -ErrorAction SilentlyContinue
    foreach ($generatedName in @('SOTAVPN-CoopLauncher.ini', 'SOTAVPN-COOP-README.md', 'SOTAVPN_GAMING.url')) {
        Remove-Item -LiteralPath (Join-Path $donorDirectory $generatedName) -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $backupDonorExe -PathType Leaf) {
        Copy-Item -LiteralPath $backupDonorExe -Destination $activeDonorExe -Force
    }
    throw
}

Write-Host ''
Write-Host 'SOTAVPN COOP Fix v1.3.1 установлен успешно.' -ForegroundColor Green
Write-Host "Игра:   $gameExecutable"
Write-Host "Донор:  $donorDirectory"
Write-Host "Backup: $backupDonorExe"
Write-Host "SHA-256 оригинала BlastZone: $backupHash"
if ($backupWasCreated) { Write-Host 'Резервная копия оригинала создана.' -ForegroundColor DarkGray }
Write-Host ''
Write-Host 'Теперь запускайте BlastZone 2 Demo из библиотеки Steam.' -ForegroundColor Cyan
Write-Host 'SOTAVPN: https://t.me/sota?start=gaming'
