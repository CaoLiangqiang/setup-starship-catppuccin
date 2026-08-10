#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('Status', 'Install', 'Remove')]
    [string]$Action = 'Status',

    [string]$UserProfilePath = $env:USERPROFILE,

    [string[]]$PowerShellProfilePaths,

    [string]$WindowsTerminalSettingsPath,

    [string]$FontDirectoryPath,

    [string]$FontRegistryPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts',

    [string]$StarshipExecutable,

    [switch]$SkipStarshipInstall,

    [switch]$SkipFontRegistration,

    [switch]$TestMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$skillRoot = Split-Path -Parent $scriptRoot
$configAsset = Join-Path $skillRoot 'assets\starship\catppuccin-powerline.toml'
$fontAssetDirectory = Join-Path $skillRoot 'assets\fonts'
$markerStart = '# >>> setup-starship-catppuccin >>>'
$markerEnd = '# <<< setup-starship-catppuccin <<<'
$fontFamily = 'CaskaydiaCove NF'
$fontFiles = @(
    @('CaskaydiaCoveNerdFont-Regular.ttf', 'CaskaydiaCove Nerd Font Regular (TrueType)'),
    @('CaskaydiaCoveNerdFont-Bold.ttf', 'CaskaydiaCove Nerd Font Bold (TrueType)'),
    @('CaskaydiaCoveNerdFont-Italic.ttf', 'CaskaydiaCove Nerd Font Italic (TrueType)'),
    @('CaskaydiaCoveNerdFont-BoldItalic.ttf', 'CaskaydiaCove Nerd Font Bold Italic (TrueType)')
)

if ([string]::IsNullOrWhiteSpace($UserProfilePath) -or $UserProfilePath -eq [IO.Path]::GetPathRoot($UserProfilePath)) {
    throw "Refusing invalid user profile path: '$UserProfilePath'"
}
$UserProfilePath = [IO.Path]::GetFullPath($UserProfilePath)
if (-not (Test-Path -LiteralPath $UserProfilePath -PathType Container)) {
    throw "User profile directory does not exist: $UserProfilePath"
}

if ($TestMode) {
    if (-not $SkipStarshipInstall -or -not $SkipFontRegistration) {
        throw '-TestMode requires -SkipStarshipInstall and -SkipFontRegistration.'
    }
} else {
    if ($UserProfilePath -ne [IO.Path]::GetFullPath($env:USERPROFILE)) {
        throw '-UserProfilePath may target another directory only with -TestMode.'
    }
    if ($FontRegistryPath -ne 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts') {
        throw '-FontRegistryPath may be overridden only with -TestMode.'
    }
}

if (-not $PowerShellProfilePaths) {
    $documents = [Environment]::GetFolderPath('MyDocuments')
    $profiles = [Collections.Generic.List[string]]::new()
    $profiles.Add((Join-Path $documents 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'))
    if ((Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue) -or
        (Test-Path -LiteralPath (Join-Path $documents 'PowerShell'))) {
        $profiles.Add((Join-Path $documents 'PowerShell\Microsoft.PowerShell_profile.ps1'))
    }
    $PowerShellProfilePaths = $profiles.ToArray()
}

if (-not $FontDirectoryPath) {
    $FontDirectoryPath = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
}
if (-not $WindowsTerminalSettingsPath) {
    $terminalCandidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    $WindowsTerminalSettingsPath = $terminalCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}

$configDirectory = Join-Path $UserProfilePath '.config'
$configPath = Join-Path $configDirectory 'starship.toml'
$configBackupPath = "$configPath.setup-starship-catppuccin.backup"
$configStampPath = "$configPath.setup-starship-catppuccin.sha256"

foreach ($asset in @($configAsset, (Join-Path $fontAssetDirectory 'OFL.txt'))) {
    if (-not (Test-Path -LiteralPath $asset -PathType Leaf)) {
        throw "Missing bundled asset: $asset"
    }
}
foreach ($font in $fontFiles) {
    $asset = Join-Path $fontAssetDirectory $font[0]
    if (-not (Test-Path -LiteralPath $asset -PathType Leaf)) {
        throw "Missing bundled font: $asset"
    }
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    $normalized = [Text.RegularExpressions.Regex]::Replace($Content, '\r?\n', "`r`n")
    [IO.File]::WriteAllText($Path, $normalized, (New-Object Text.UTF8Encoding($false)))
}

function Get-TerminalFontFace {
    param([Parameter(Mandatory = $true)]$Settings)

    if ($null -eq $Settings.PSObject.Properties['profiles']) { return $null }
    if ($null -eq $Settings.profiles.PSObject.Properties['defaults']) { return $null }
    if ($null -eq $Settings.profiles.defaults.PSObject.Properties['font']) { return $null }
    if ($null -eq $Settings.profiles.defaults.font.PSObject.Properties['face']) { return $null }
    return [string]$Settings.profiles.defaults.font.face
}

function Backup-File {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }
    $backup = "$Path.setup-starship-catppuccin.backup.$([Guid]::NewGuid().ToString('N'))"
    Copy-Item -LiteralPath $Path -Destination $backup
    Write-Output "Backup: $backup"
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-StarshipExecutable {
    if ($StarshipExecutable) {
        if (Test-Path -LiteralPath $StarshipExecutable -PathType Leaf) {
            return [IO.Path]::GetFullPath($StarshipExecutable)
        }
        return $null
    }

    $command = Get-Command starship -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        return $command.Source
    }

    $wingetPackageRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    $candidate = Get-ChildItem -LiteralPath $wingetPackageRoot -Filter starship.exe -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match 'Starship\.Starship_' } |
        Select-Object -First 1
    if ($candidate) {
        return $candidate.FullName
    }
    return $null
}

function Install-Starship {
    $resolved = Get-StarshipExecutable
    if ($resolved) {
        return $resolved
    }
    if ($SkipStarshipInstall) {
        throw 'Starship is missing and -SkipStarshipInstall was selected.'
    }
    $winget = Get-Command winget -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $winget) {
        throw 'winget is required for the non-elevated Windows Starship installation.'
    }
    & $winget.Source install --id Starship.Starship --exact --source winget --scope user --silent `
        --accept-package-agreements --accept-source-agreements --disable-interactivity |
        ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "winget failed to install Starship (exit $LASTEXITCODE)."
    }
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
        [Environment]::GetEnvironmentVariable('Path', 'User')
    $resolved = Get-StarshipExecutable
    if (-not $resolved) {
        throw 'Starship installation completed but starship.exe was not found.'
    }
    return $resolved
}

function Get-ProfileBlock {
    return @(
        $markerStart,
        'Invoke-Expression (&starship init powershell)',
        $markerEnd
    ) -join "`r`n"
}

function Get-ProfileBlockState {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return 'Missing' }
    $content = [IO.File]::ReadAllText($Path)
    $startCount = ([regex]::Matches($content, [regex]::Escape($markerStart))).Count
    $endCount = ([regex]::Matches($content, [regex]::Escape($markerEnd))).Count
    if ($startCount -eq 0 -and $endCount -eq 0) {
        if ($content -match 'starship\s+init\s+powershell') { return 'Foreign' }
        return 'Absent'
    }
    if ($startCount -ne 1 -or $endCount -ne 1) { return 'Malformed' }
    $pattern = '(?ms)^' + [regex]::Escape($markerStart) + '.*?^' + [regex]::Escape($markerEnd) + '\r?$'
    $match = [regex]::Match($content, $pattern)
    if (-not $match.Success) { return 'Malformed' }
    if ($match.Value.TrimEnd() -eq (Get-ProfileBlock).TrimEnd()) { return 'Owned' }
    return 'Collision'
}

function Install-ProfileBlock {
    param([Parameter(Mandatory = $true)][string]$Path)

    $state = Get-ProfileBlockState -Path $Path
    if ($state -eq 'Owned') { return }
    if ($state -notin @('Missing', 'Absent')) {
        throw "Refusing $state Starship block state in $Path"
    }
    $content = ''
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Backup-File -Path $Path
        $content = [IO.File]::ReadAllText($Path).TrimEnd() + "`r`n`r`n"
    }
    Write-Utf8File -Path $Path -Content ($content + (Get-ProfileBlock) + "`r`n")
    Write-Output "Installed PowerShell profile block: $Path"
}

function Remove-ProfileBlock {
    param([Parameter(Mandatory = $true)][string]$Path)

    $state = Get-ProfileBlockState -Path $Path
    if ($state -in @('Missing', 'Absent', 'Foreign')) {
        Write-Output "No owned PowerShell profile block: $Path"
        return
    }
    if ($state -ne 'Owned') {
        throw "Refusing $state Starship block state in $Path"
    }
    Backup-File -Path $Path
    $content = [IO.File]::ReadAllText($Path)
    $pattern = '(?ms)\r?\n?' + [regex]::Escape($markerStart) + '.*?' + [regex]::Escape($markerEnd) + '\r?\n?'
    $content = [regex]::Replace($content, $pattern, "`r`n").TrimEnd() + "`r`n"
    Write-Utf8File -Path $Path -Content $content
    Write-Output "Removed PowerShell profile block: $Path"
}

function Install-StarshipConfig {
    $assetHash = Get-FileSha256 -Path $configAsset
    $currentHash = if (Test-Path -LiteralPath $configPath -PathType Leaf) { Get-FileSha256 -Path $configPath } else { '' }
    $recordedHash = if (Test-Path -LiteralPath $configStampPath -PathType Leaf) {
        ([IO.File]::ReadAllText($configStampPath)).Trim().ToLowerInvariant()
    } else { '' }

    if ($recordedHash -and $currentHash -and $currentHash -ne $recordedHash) {
        throw "Refusing to overwrite a Starship config changed after installation: $configPath"
    }
    if ($currentHash -and -not $recordedHash -and -not (Test-Path -LiteralPath $configBackupPath)) {
        Copy-Item -LiteralPath $configPath -Destination $configBackupPath
        Write-Output "Saved original Starship config: $configBackupPath"
    }
    if (-not (Test-Path -LiteralPath $configDirectory)) {
        New-Item -ItemType Directory -Force -Path $configDirectory | Out-Null
    }
    Copy-Item -LiteralPath $configAsset -Destination $configPath -Force
    Write-Utf8File -Path $configStampPath -Content ($assetHash + "`r`n")
    Write-Output "Installed Catppuccin Powerline config: $configPath"
}

function Remove-StarshipConfig {
    if (-not (Test-Path -LiteralPath $configStampPath -PathType Leaf)) {
        Write-Output 'No owned Starship config stamp.'
        return
    }
    $recordedHash = ([IO.File]::ReadAllText($configStampPath)).Trim().ToLowerInvariant()
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $currentHash = Get-FileSha256 -Path $configPath
        if ($currentHash -ne $recordedHash) {
            throw "Refusing to remove a Starship config changed after installation: $configPath"
        }
    }
    if (Test-Path -LiteralPath $configBackupPath -PathType Leaf) {
        Move-Item -LiteralPath $configBackupPath -Destination $configPath -Force
        Write-Output "Restored original Starship config: $configPath"
    } else {
        Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
        Write-Output "Removed owned Starship config: $configPath"
    }
    Remove-Item -LiteralPath $configStampPath -Force
}

function Initialize-FontApi {
    if ($SkipFontRegistration -or ('FontNativeMethods' -as [type])) { return }
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class FontNativeMethods
{
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int AddFontResourceEx(string fileName, uint flags, IntPtr reserved);
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool RemoveFontResourceEx(string fileName, uint flags, IntPtr reserved);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wParam, IntPtr lParam, uint flags, uint timeout, out UIntPtr result);
}
'@
}

function Send-FontChange {
    if ($SkipFontRegistration) { return }
    $result = [UIntPtr]::Zero
    [void][FontNativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x001D, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 2000, [ref]$result)
}

function Install-Fonts {
    Initialize-FontApi
    if (-not (Test-Path -LiteralPath $FontDirectoryPath)) {
        New-Item -ItemType Directory -Force -Path $FontDirectoryPath | Out-Null
    }
    foreach ($font in $fontFiles) {
        $source = Join-Path $fontAssetDirectory $font[0]
        $target = Join-Path $FontDirectoryPath $font[0]
        $backup = "$target.setup-starship-catppuccin.backup"
        if ((Test-Path -LiteralPath $target -PathType Leaf) -and
            (Get-FileSha256 $source) -ne (Get-FileSha256 $target) -and
            -not (Test-Path -LiteralPath $backup)) {
            Copy-Item -LiteralPath $target -Destination $backup
        }
        Copy-Item -LiteralPath $source -Destination $target -Force
        if (-not $SkipFontRegistration) {
            New-ItemProperty -Path $FontRegistryPath -Name $font[1] -Value $target -PropertyType String -Force | Out-Null
            if ([FontNativeMethods]::AddFontResourceEx($target, 0, [IntPtr]::Zero) -eq 0) {
                throw "Windows could not load font: $target"
            }
        }
        Write-Output "Installed font: $target"
    }
    Copy-Item -LiteralPath (Join-Path $fontAssetDirectory 'OFL.txt') -Destination (Join-Path $FontDirectoryPath 'OFL.txt') -Force
    Send-FontChange
}

function Remove-Fonts {
    Initialize-FontApi
    foreach ($font in $fontFiles) {
        $source = Join-Path $fontAssetDirectory $font[0]
        $target = Join-Path $FontDirectoryPath $font[0]
        $backup = "$target.setup-starship-catppuccin.backup"
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            if ((Get-FileSha256 $source) -ne (Get-FileSha256 $target)) {
                throw "Refusing to remove a changed font file: $target"
            }
            if (-not $SkipFontRegistration) {
                [void][FontNativeMethods]::RemoveFontResourceEx($target, 0, [IntPtr]::Zero)
                Remove-ItemProperty -Path $FontRegistryPath -Name $font[1] -ErrorAction SilentlyContinue
            }
            if (Test-Path -LiteralPath $backup -PathType Leaf) {
                Move-Item -LiteralPath $backup -Destination $target -Force
            } else {
                Remove-Item -LiteralPath $target -Force
            }
        }
    }
    Remove-Item -LiteralPath (Join-Path $FontDirectoryPath 'OFL.txt') -Force -ErrorAction SilentlyContinue
    Send-FontChange
}

function Install-TerminalFont {
    if (-not $WindowsTerminalSettingsPath) {
        Write-Warning 'Windows Terminal settings were not found; skipped Terminal font defaults.'
        return
    }
    $statePath = "$WindowsTerminalSettingsPath.setup-starship-catppuccin.json"
    $settings = [IO.File]::ReadAllText($WindowsTerminalSettingsPath) | ConvertFrom-Json
    if (-not $settings.profiles) {
        throw "Windows Terminal settings have no profiles object: $WindowsTerminalSettingsPath"
    }
    if (-not $settings.profiles.defaults) {
        $settings.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([PSCustomObject]@{})
    }
    $defaults = $settings.profiles.defaults
    $hadFont = $null -ne $defaults.PSObject.Properties['font']
    $hadFace = $hadFont -and $null -ne $defaults.font.PSObject.Properties['face']
    $originalFace = if ($hadFace) { [string]$defaults.font.face } else { $null }
    if ((Test-Path -LiteralPath $statePath -PathType Leaf) -and $originalFace -eq $fontFamily) {
        return
    }
    if (-not (Test-Path -LiteralPath $statePath)) {
        $state = [PSCustomObject]@{ HadFont = $hadFont; HadFace = $hadFace; OriginalFace = $originalFace; InstalledFace = $fontFamily }
        Write-Utf8File -Path $statePath -Content (($state | ConvertTo-Json -Depth 5) + "`r`n")
    }
    if (-not $hadFont) {
        $defaults | Add-Member -NotePropertyName font -NotePropertyValue ([PSCustomObject]@{})
    }
    if ($null -eq $defaults.font.PSObject.Properties['face']) {
        $defaults.font | Add-Member -NotePropertyName face -NotePropertyValue $fontFamily
    } else {
        $defaults.font.face = $fontFamily
    }
    Backup-File -Path $WindowsTerminalSettingsPath
    Write-Utf8File -Path $WindowsTerminalSettingsPath -Content (($settings | ConvertTo-Json -Depth 100) + "`r`n")
    Write-Output "Configured Windows Terminal default font: $fontFamily"
}

function Remove-TerminalFont {
    if (-not $WindowsTerminalSettingsPath) { return }
    $statePath = "$WindowsTerminalSettingsPath.setup-starship-catppuccin.json"
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        Write-Output 'No owned Windows Terminal font state.'
        return
    }
    $state = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json
    $settings = [IO.File]::ReadAllText($WindowsTerminalSettingsPath) | ConvertFrom-Json
    $currentFace = Get-TerminalFontFace -Settings $settings
    if ($currentFace -ne $state.InstalledFace) {
        throw "Refusing to replace a Windows Terminal font changed after installation: $currentFace"
    }
    if ($state.HadFace) {
        $settings.profiles.defaults.font.face = $state.OriginalFace
    } else {
        $settings.profiles.defaults.font.PSObject.Properties.Remove('face')
        if (-not $state.HadFont -and @($settings.profiles.defaults.font.PSObject.Properties).Count -eq 0) {
            $settings.profiles.defaults.PSObject.Properties.Remove('font')
        }
    }
    Backup-File -Path $WindowsTerminalSettingsPath
    Write-Utf8File -Path $WindowsTerminalSettingsPath -Content (($settings | ConvertTo-Json -Depth 100) + "`r`n")
    Remove-Item -LiteralPath $statePath -Force
    Write-Output 'Restored Windows Terminal font defaults.'
}

function Test-Ready {
    $ready = $true
    if (-not (Get-StarshipExecutable)) { Write-Host 'CHANGE NEEDED: Starship executable is missing.'; $ready = $false }
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf) -or
        (Get-FileSha256 $configAsset) -ne (Get-FileSha256 $configPath)) {
        Write-Host 'CHANGE NEEDED: Starship config differs or is missing.'
        $ready = $false
    }
    foreach ($profilePath in $PowerShellProfilePaths) {
        if ((Get-ProfileBlockState -Path $profilePath) -ne 'Owned') {
            Write-Host "CHANGE NEEDED: PowerShell profile block is not installed: $profilePath"
            $ready = $false
        }
    }
    foreach ($font in $fontFiles) {
        $asset = Join-Path $fontAssetDirectory $font[0]
        $target = Join-Path $FontDirectoryPath $font[0]
        if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or
            (Get-FileSha256 $asset) -ne (Get-FileSha256 $target)) {
            Write-Host "CHANGE NEEDED: font differs or is missing: $target"
            $ready = $false
        }
    }
    if ($WindowsTerminalSettingsPath) {
        $settings = [IO.File]::ReadAllText($WindowsTerminalSettingsPath) | ConvertFrom-Json
        if ((Get-TerminalFontFace -Settings $settings) -ne $fontFamily) {
            Write-Host 'CHANGE NEEDED: Windows Terminal default font is not configured.'
            $ready = $false
        }
    }
    if ($ready) { Write-Host 'OK: Windows Starship, Catppuccin config, fonts, profiles, and Terminal settings are ready.' }
    return $ready
}

function Assert-InstallSafe {
    if ((Test-Path -LiteralPath $configStampPath -PathType Leaf) -and
        (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        $recordedHash = ([IO.File]::ReadAllText($configStampPath)).Trim().ToLowerInvariant()
        if ((Get-FileSha256 $configPath) -ne $recordedHash) {
            throw "Refusing to overwrite a Starship config changed after installation: $configPath"
        }
    }
    foreach ($profilePath in $PowerShellProfilePaths) {
        $state = Get-ProfileBlockState -Path $profilePath
        if ($state -notin @('Owned', 'Missing', 'Absent')) {
            throw "Refusing $state Starship block state in $profilePath"
        }
    }
    if ($WindowsTerminalSettingsPath) {
        $statePath = "$WindowsTerminalSettingsPath.setup-starship-catppuccin.json"
        if (Test-Path -LiteralPath $statePath -PathType Leaf) {
            $state = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json
            $settings = [IO.File]::ReadAllText($WindowsTerminalSettingsPath) | ConvertFrom-Json
            if ((Get-TerminalFontFace -Settings $settings) -ne $state.InstalledFace) {
                throw 'Refusing to overwrite Windows Terminal font settings changed after installation.'
            }
        }
    }
}

function Assert-RemoveSafe {
    if ((Test-Path -LiteralPath $configStampPath -PathType Leaf) -and
        (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        $recordedHash = ([IO.File]::ReadAllText($configStampPath)).Trim().ToLowerInvariant()
        if ((Get-FileSha256 $configPath) -ne $recordedHash) {
            throw "Refusing to remove a Starship config changed after installation: $configPath"
        }
    }
    foreach ($profilePath in $PowerShellProfilePaths) {
        $state = Get-ProfileBlockState -Path $profilePath
        if ($state -notin @('Owned', 'Missing', 'Absent', 'Foreign')) {
            throw "Refusing $state Starship block state in $profilePath"
        }
    }
    foreach ($font in $fontFiles) {
        $source = Join-Path $fontAssetDirectory $font[0]
        $target = Join-Path $FontDirectoryPath $font[0]
        if ((Test-Path -LiteralPath $target -PathType Leaf) -and
            (Get-FileSha256 $source) -ne (Get-FileSha256 $target)) {
            throw "Refusing to remove a changed font file: $target"
        }
    }
    if ($WindowsTerminalSettingsPath) {
        $statePath = "$WindowsTerminalSettingsPath.setup-starship-catppuccin.json"
        if (Test-Path -LiteralPath $statePath -PathType Leaf) {
            $state = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json
            $settings = [IO.File]::ReadAllText($WindowsTerminalSettingsPath) | ConvertFrom-Json
            if ((Get-TerminalFontFace -Settings $settings) -ne $state.InstalledFace) {
                throw 'Refusing to replace Windows Terminal font settings changed after installation.'
            }
        }
    }
}

switch ($Action) {
    'Status' {
        if (-not (Test-Ready)) { exit 1 }
    }
    'Install' {
        Assert-InstallSafe
        $resolvedStarship = Install-Starship
        Write-Output "Starship: $resolvedStarship"
        Install-StarshipConfig
        Install-Fonts
        foreach ($profilePath in $PowerShellProfilePaths) { Install-ProfileBlock -Path $profilePath }
        Install-TerminalFont
        if (-not (Test-Ready)) { throw 'Installation finished but verification did not pass.' }
    }
    'Remove' {
        Assert-RemoveSafe
        foreach ($profilePath in $PowerShellProfilePaths) { Remove-ProfileBlock -Path $profilePath }
        Remove-StarshipConfig
        Remove-TerminalFont
        Remove-Fonts
        Write-Output 'Removed owned Windows Starship configuration. The Starship package was retained.'
    }
}
