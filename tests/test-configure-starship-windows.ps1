#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'scripts\configure-starship-windows.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("setup-starship-windows-test-" + [Guid]::NewGuid().ToString('N'))

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

try {
    $userRoot = Join-Path $testRoot 'User'
    $profile = Join-Path $testRoot 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
    $settings = Join-Path $testRoot 'Terminal\settings.json'
    $fontDirectory = Join-Path $testRoot 'Fonts'
    $fakeStarship = Join-Path $testRoot 'starship.exe'
    New-Item -ItemType Directory -Force -Path $userRoot, (Split-Path $profile), (Split-Path $settings) | Out-Null
    [IO.File]::WriteAllText($profile, "# original profile`r`n")
    [IO.File]::WriteAllText($settings, '{"profiles":{"defaults":{"opacity":90},"list":[]}}')
    [IO.File]::WriteAllText($fakeStarship, 'fixture')
    New-Item -ItemType Directory -Force -Path (Join-Path $userRoot '.config') | Out-Null
    [IO.File]::WriteAllText((Join-Path $userRoot '.config\starship.toml'), "add_newline = false`r`n")

    $common = @{
        UserProfilePath = $userRoot
        PowerShellProfilePaths = @($profile)
        WindowsTerminalSettingsPath = $settings
        FontDirectoryPath = $fontDirectory
        StarshipExecutable = $fakeStarship
        SkipStarshipInstall = $true
        SkipFontRegistration = $true
        TestMode = $true
    }

    & $scriptPath -Action Install @common *> $null
    Assert-True ((Get-Content -Raw $profile) -match 'setup-starship-catppuccin') 'profile block missing'
    Assert-True ((Get-Content -Raw $profile) -match 'starship init powershell') 'PowerShell init missing'
    $terminal = Get-Content -Raw $settings | ConvertFrom-Json
    Assert-True ($terminal.profiles.defaults.font.face -eq 'CaskaydiaCove NF') 'Terminal font missing'
    Assert-True ((Get-FileHash (Join-Path $userRoot '.config\starship.toml')).Hash -eq
        (Get-FileHash (Join-Path $repoRoot 'assets\starship\catppuccin-powerline.toml')).Hash) 'theme mismatch'
    Get-ChildItem (Join-Path $repoRoot 'assets\fonts') -Filter '*.ttf' | ForEach-Object {
        $target = Join-Path $fontDirectory $_.Name
        Assert-True ((Test-Path $target) -and (Get-FileHash $_.FullName).Hash -eq (Get-FileHash $target).Hash) "font mismatch: $($_.Name)"
    }

    $before = Get-ChildItem $testRoot -File -Recurse | Sort-Object FullName | ForEach-Object { "$(Get-FileHash $_.FullName) $($_.FullName)" }
    & $scriptPath -Action Install @common *> $null
    $after = Get-ChildItem $testRoot -File -Recurse | Sort-Object FullName | ForEach-Object { "$(Get-FileHash $_.FullName) $($_.FullName)" }
    Assert-True (($before -join "`n") -eq ($after -join "`n")) 'second install was not idempotent'

    Add-Content -LiteralPath (Join-Path $userRoot '.config\starship.toml') -Value '# user change'
    $removeBefore = Get-ChildItem $testRoot -File -Recurse | Sort-Object FullName | ForEach-Object { "$(Get-FileHash $_.FullName) $($_.FullName)" }
    $failed = $false
    try { & $scriptPath -Action Remove @common *> $null } catch { $failed = $true }
    Assert-True $failed 'changed config removal should fail'
    $removeAfter = Get-ChildItem $testRoot -File -Recurse | Sort-Object FullName | ForEach-Object { "$(Get-FileHash $_.FullName) $($_.FullName)" }
    Assert-True (($removeBefore -join "`n") -eq ($removeAfter -join "`n")) 'failed remove made partial changes'
    Copy-Item (Join-Path $repoRoot 'assets\starship\catppuccin-powerline.toml') (Join-Path $userRoot '.config\starship.toml') -Force

    & $scriptPath -Action Remove @common *> $null
    Assert-True ((Get-Content -Raw (Join-Path $userRoot '.config\starship.toml')) -match 'add_newline = false') 'original config not restored'
    Assert-True ((Get-Content -Raw $profile) -notmatch 'setup-starship-catppuccin') 'profile marker remained'
    $terminal = Get-Content -Raw $settings | ConvertFrom-Json
    Assert-True ($null -eq $terminal.profiles.defaults.PSObject.Properties['font']) 'Terminal font default not restored'
    Assert-True (@(Get-ChildItem $fontDirectory -Filter '*.ttf' -ErrorAction SilentlyContinue).Count -eq 0) 'font files remained'

    Write-Output 'PASS: configure-starship-windows.ps1 is idempotent, reversible, and fixture-safe'
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
