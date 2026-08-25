#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'scripts\configure-starship-windows.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("setup-starship-windows-test-" + [Guid]::NewGuid().ToString('N'))
$testRegistryPath = "HKCU:\Software\setup-starship-catppuccin-tests\$([Guid]::NewGuid().ToString('N'))"
$unsupportedRegistryPath = "HKCU:\Software\setup-starship-catppuccin-tests\$([Guid]::NewGuid().ToString('N'))"
$ambiguousRegistryPath = "HKCU:\Software\setup-starship-catppuccin-tests\$([Guid]::NewGuid().ToString('N'))"
$legacyRegistryPath = "HKCU:\Software\setup-starship-catppuccin-tests\$([Guid]::NewGuid().ToString('N'))"

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Get-TreeHash {
    param([string]$Path)
    return (Get-ChildItem -LiteralPath $Path -File -Recurse | Sort-Object FullName |
        ForEach-Object { "$(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName | Select-Object -ExpandProperty Hash) $($_.FullName)" }) -join "`n"
}

function Assert-Fails {
    param([scriptblock]$Command, [string]$Message)
    $failed = $false
    $LASTEXITCODE = 0
    try {
        & $Command
        if ($LASTEXITCODE -ne 0) { $failed = $true }
    } catch { $failed = $true }
    Assert-True $failed $Message
}

function Get-RawRegistryValue {
    param([string]$Path, [string]$Name)
    $key = Get-Item -LiteralPath $Path
    return $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
}

function New-Fixture {
    param([string]$Name, [switch]$JsonC)

    $root = Join-Path $testRoot $Name
    $userRoot = Join-Path $root 'User'
    $profile = Join-Path $root 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
    $settings = Join-Path $root 'Terminal\settings.json'
    $fontDirectory = Join-Path $root 'Fonts'
    $fakeStarship = Join-Path $root 'starship.exe'
    New-Item -ItemType Directory -Force -Path $userRoot, (Split-Path $profile), (Split-Path $settings), (Join-Path $userRoot '.config') | Out-Null
    [IO.File]::WriteAllText($profile, "# original profile`r`n")
    if ($JsonC) {
        [IO.File]::WriteAllText($settings, @'
{
  // Windows Terminal accepts this comment,
  "copy": "https://example.test//literal/*not a comment*/",
  "profiles": {
    /* and this block comment */
    "defaults": { "opacity": 90, },
    "list": [],
  },
}
'@)
    } else {
        [IO.File]::WriteAllText($settings, '{"profiles":{"defaults":{"opacity":90},"list":[]}}')
    }
    [IO.File]::WriteAllText($fakeStarship, 'fixture')
    [IO.File]::WriteAllText((Join-Path $userRoot '.config\starship.toml'), "add_newline = false`r`n")
    return [PSCustomObject]@{
        Root = $root; UserRoot = $userRoot; Profile = $profile; Settings = $settings
        FontDirectory = $fontDirectory; FakeStarship = $fakeStarship
    }
}

try {
    $fixture = New-Fixture -Name 'main' -JsonC
    $common = @{
        UserProfilePath = $fixture.UserRoot
        PowerShellProfilePaths = @($fixture.Profile)
        WindowsTerminalSettingsPath = $fixture.Settings
        FontDirectoryPath = $fixture.FontDirectory
        StarshipExecutable = $fixture.FakeStarship
        SkipStarshipInstall = $true
        SkipFontRegistration = $true
        TestMode = $true
    }

    # JSONC comments/trailing commas are accepted, while URL/comment-like string content remains literal.
    & $scriptPath -Action Install @common *> $null
    Assert-True ((Get-Content -Raw $fixture.Profile) -match 'setup-starship-catppuccin') 'profile block missing'
    $terminal = Get-Content -Raw $fixture.Settings | ConvertFrom-Json
    Assert-True ($terminal.copy -eq 'https://example.test//literal/*not a comment*/') 'JSONC reader altered string content'
    Assert-True ($terminal.profiles.defaults.font.face -eq 'CaskaydiaCove NF') 'Terminal font missing'
    Assert-True ((Get-FileHash (Join-Path $fixture.UserRoot '.config\starship.toml')).Hash -eq
        (Get-FileHash (Join-Path $repoRoot 'assets\starship\catppuccin-powerline.toml')).Hash) 'theme mismatch'
    Get-ChildItem (Join-Path $repoRoot 'assets\fonts') -Filter '*.ttf' | ForEach-Object {
        $target = Join-Path $fixture.FontDirectory $_.Name
        Assert-True ((Test-Path $target) -and (Get-FileHash $_.FullName).Hash -eq (Get-FileHash $target).Hash) "font mismatch: $($_.Name)"
    }

    $before = Get-TreeHash -Path $fixture.Root
    & $scriptPath -Action Install @common *> $null
    Assert-True ($before -eq (Get-TreeHash -Path $fixture.Root)) 'second install was not idempotent'

    Add-Content -LiteralPath (Join-Path $fixture.UserRoot '.config\starship.toml') -Value '# user change'
    $removeBefore = Get-TreeHash -Path $fixture.Root
    Assert-Fails { & $scriptPath -Action Remove @common *> $null } 'changed config removal should fail'
    Assert-True ($removeBefore -eq (Get-TreeHash -Path $fixture.Root)) 'failed config removal made partial changes'
    Copy-Item (Join-Path $repoRoot 'assets\starship\catppuccin-powerline.toml') (Join-Path $fixture.UserRoot '.config\starship.toml') -Force

    & $scriptPath -Action Remove @common *> $null
    Assert-True ((Get-Content -Raw (Join-Path $fixture.UserRoot '.config\starship.toml')) -match 'add_newline = false') 'original config not restored'
    Assert-True ((Get-Content -Raw $fixture.Profile) -notmatch 'setup-starship-catppuccin') 'profile marker remained'
    $terminal = Get-Content -Raw $fixture.Settings | ConvertFrom-Json
    Assert-True ($null -eq $terminal.profiles.defaults.PSObject.Properties['font']) 'Terminal font default not restored'
    Assert-True (@(Get-ChildItem $fixture.FontDirectory -Filter '*.ttf' -ErrorAction SilentlyContinue).Count -eq 0) 'font files remained'

    # A missing Terminal is not a reduced-success installation and must not modify other state.
    $missingTerminal = New-Fixture -Name 'missing-terminal'
    Remove-Item -LiteralPath $missingTerminal.Settings -Force
    $missingCommon = @{
        UserProfilePath = $missingTerminal.UserRoot; PowerShellProfilePaths = @($missingTerminal.Profile)
        WindowsTerminalSettingsPath = $missingTerminal.Settings; FontDirectoryPath = $missingTerminal.FontDirectory
        StarshipExecutable = $missingTerminal.FakeStarship; SkipStarshipInstall = $true
        SkipFontRegistration = $true; TestMode = $true
    }
    $missingBefore = Get-TreeHash -Path $missingTerminal.Root
    Assert-Fails { & $scriptPath -Action Install @missingCommon *> $null } 'missing Terminal installation should fail preflight'
    Assert-True ($missingBefore -eq (Get-TreeHash -Path $missingTerminal.Root)) 'missing Terminal preflight made a mutation'
    $powerShellHost = if ($PSVersionTable.PSEdition -eq 'Core') {
        Join-Path $PSHOME 'pwsh.exe'
    } else {
        Join-Path $PSHOME 'powershell.exe'
    }
    $statusOutput = & $powerShellHost -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass `
        -File $scriptPath -Action Status -UserProfilePath $missingTerminal.UserRoot `
        -PowerShellProfilePaths $missingTerminal.Profile -WindowsTerminalSettingsPath $missingTerminal.Settings `
        -FontDirectoryPath $missingTerminal.FontDirectory -StarshipExecutable $missingTerminal.FakeStarship `
        -SkipStarshipInstall -SkipFontRegistration -TestMode 2>&1
    $statusExitCode = $LASTEXITCODE
    Assert-True ($statusExitCode -ne 0 -and ($statusOutput -join "`n") -match 'CHANGE NEEDED: Windows Terminal settings') 'missing Terminal status was not a failure'
    $global:LASTEXITCODE = 0

    # Every install-time Terminal shape conflict must be rejected before profiles, config, or fonts change.
    $terminalCases = @{
        'missing-profiles' = '{}'
        'profiles-scalar' = '{"profiles":"invalid"}'
        'defaults-scalar' = '{"profiles":{"defaults":1}}'
        'font-scalar' = '{"profiles":{"defaults":{"font":false}}}'
        'face-nonstring' = '{"profiles":{"defaults":{"font":{"face":7}}}}'
    }
    foreach ($terminalCase in $terminalCases.GetEnumerator()) {
        $badTerminal = New-Fixture -Name ("terminal-" + $terminalCase.Key)
        [IO.File]::WriteAllText($badTerminal.Settings, $terminalCase.Value)
        $badCommon = @{
            UserProfilePath = $badTerminal.UserRoot; PowerShellProfilePaths = @($badTerminal.Profile)
            WindowsTerminalSettingsPath = $badTerminal.Settings; FontDirectoryPath = $badTerminal.FontDirectory
            StarshipExecutable = $badTerminal.FakeStarship; SkipStarshipInstall = $true
            SkipFontRegistration = $true; TestMode = $true
        }
        $badBefore = Get-TreeHash -Path $badTerminal.Root
        Assert-Fails { & $scriptPath -Action Install @badCommon *> $null } "invalid Terminal shape was accepted: $($terminalCase.Key)"
        Assert-True ($badBefore -eq (Get-TreeHash -Path $badTerminal.Root)) "invalid Terminal shape made a mutation: $($terminalCase.Key)"
    }

    $sidecarDirectory = New-Fixture -Name 'terminal-sidecar-directory'
    New-Item -ItemType Directory -Path "$($sidecarDirectory.Settings).setup-starship-catppuccin.json" | Out-Null
    $sidecarCommon = @{
        UserProfilePath = $sidecarDirectory.UserRoot; PowerShellProfilePaths = @($sidecarDirectory.Profile)
        WindowsTerminalSettingsPath = $sidecarDirectory.Settings; FontDirectoryPath = $sidecarDirectory.FontDirectory
        StarshipExecutable = $sidecarDirectory.FakeStarship; SkipStarshipInstall = $true
        SkipFontRegistration = $true; TestMode = $true
    }
    $sidecarBefore = Get-TreeHash -Path $sidecarDirectory.Root
    Assert-Fails { & $scriptPath -Action Install @sidecarCommon *> $null } 'Terminal state sidecar directory should fail preflight'
    Assert-True ($sidecarBefore -eq (Get-TreeHash -Path $sidecarDirectory.Root)) 'Terminal state sidecar rejection made a mutation'

    $adjacentTokens = New-Fixture -Name 'terminal-adjacent-comment'
    [IO.File]::WriteAllText($adjacentTokens.Settings, '{"profiles":{"defaults":{"opacity":1/*comment*/2}}}')
    $adjacentCommon = @{
        UserProfilePath = $adjacentTokens.UserRoot; PowerShellProfilePaths = @($adjacentTokens.Profile)
        WindowsTerminalSettingsPath = $adjacentTokens.Settings; FontDirectoryPath = $adjacentTokens.FontDirectory
        StarshipExecutable = $adjacentTokens.FakeStarship; SkipStarshipInstall = $true
        SkipFontRegistration = $true; TestMode = $true
    }
    $adjacentBefore = Get-TreeHash -Path $adjacentTokens.Root
    Assert-Fails { & $scriptPath -Action Install @adjacentCommon *> $null } 'adjacent JSONC comment tokens should fail'
    Assert-True ($adjacentBefore -eq (Get-TreeHash -Path $adjacentTokens.Root)) 'adjacent JSONC rejection made a mutation'

    # Production accepts only environment-derived paths; each caller override is rejected before work starts.
    foreach ($name in @('PowerShellProfilePaths', 'WindowsTerminalSettingsPath', 'FontDirectoryPath')) {
        $arguments = @{ Action = 'Status' }
        $arguments[$name] = if ($name -eq 'PowerShellProfilePaths') { @($fixture.Profile) } else { $fixture.Settings }
        Assert-Fails { & $scriptPath @arguments *> $null } "production path override was accepted: $name"
    }

    # Font checksums are validated before the first managed write.
    $checksumFixture = Join-Path $testRoot 'checksum-copy'
    Copy-Item -LiteralPath $repoRoot -Destination $checksumFixture -Recurse
    $checksumScript = Join-Path $checksumFixture 'scripts\configure-starship-windows.ps1'
    Assert-True (Test-Path -LiteralPath $checksumScript -PathType Leaf) 'checksum fixture script was not copied'
    Add-Content -LiteralPath (Join-Path $checksumFixture 'assets\fonts\CaskaydiaCoveNerdFont-Regular.ttf') -Value 'tampered'
    $checksumTarget = New-Fixture -Name 'checksum-target'
    $checksumCommon = @{
        UserProfilePath = $checksumTarget.UserRoot; PowerShellProfilePaths = @($checksumTarget.Profile)
        WindowsTerminalSettingsPath = $checksumTarget.Settings; FontDirectoryPath = $checksumTarget.FontDirectory
        StarshipExecutable = $checksumTarget.FakeStarship; SkipStarshipInstall = $true
        SkipFontRegistration = $true; TestMode = $true
    }
    $checksumBefore = Get-TreeHash -Path $checksumTarget.Root
    Assert-Fails { & $checksumScript -Action Install @checksumCommon *> $null } 'checksum mismatch should fail'
    Assert-True ($checksumBefore -eq (Get-TreeHash -Path $checksumTarget.Root)) 'checksum rejection made a mutation'

    $extraFontFixture = Join-Path $testRoot 'extra-font-copy'
    Copy-Item -LiteralPath $repoRoot -Destination $extraFontFixture -Recurse
    $extraFontScript = Join-Path $extraFontFixture 'scripts\configure-starship-windows.ps1'
    Assert-True (Test-Path -LiteralPath $extraFontScript -PathType Leaf) 'extra-font fixture script was not copied'
    [IO.File]::WriteAllText((Join-Path $extraFontFixture 'assets\fonts\Unexpected.ttf'), 'unexpected font')
    $extraFontTarget = New-Fixture -Name 'extra-font-target'
    $extraFontCommon = @{
        UserProfilePath = $extraFontTarget.UserRoot; PowerShellProfilePaths = @($extraFontTarget.Profile)
        WindowsTerminalSettingsPath = $extraFontTarget.Settings; FontDirectoryPath = $extraFontTarget.FontDirectory
        StarshipExecutable = $extraFontTarget.FakeStarship; SkipStarshipInstall = $true
        SkipFontRegistration = $true; TestMode = $true
    }
    $extraFontBefore = Get-TreeHash -Path $extraFontTarget.Root
    Assert-Fails { & $extraFontScript -Action Install @extraFontCommon *> $null } 'extra bundled font should fail'
    Assert-True ($extraFontBefore -eq (Get-TreeHash -Path $extraFontTarget.Root)) 'extra font rejection made a mutation'

    # TestMode exercises a test HKCU key while deliberately avoiding native GDI calls.
    $registryFixture = New-Fixture -Name 'registry'
    New-Item -Path $testRegistryPath -Force | Out-Null
    $regular = 'CaskaydiaCove Nerd Font Regular (TrueType)'
    $bold = 'CaskaydiaCove Nerd Font Bold (TrueType)'
    New-Item -ItemType Directory -Force -Path $registryFixture.FontDirectory | Out-Null
    $regularFile = Join-Path $registryFixture.FontDirectory 'CaskaydiaCoveNerdFont-Regular.ttf'
    [IO.File]::WriteAllText($regularFile, 'original user font')
    $priorRegistryValue = [IO.Path]::GetFullPath($regularFile)
    $expandRegistryValue = '%USERPROFILE%\FixtureFonts\original-bold.ttf'
    New-ItemProperty -Path $testRegistryPath -Name $regular -Value $priorRegistryValue -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $testRegistryPath -Name $bold -Value $expandRegistryValue -PropertyType ExpandString -Force | Out-Null
    $registryCommon = @{
        UserProfilePath = $registryFixture.UserRoot; PowerShellProfilePaths = @($registryFixture.Profile)
        WindowsTerminalSettingsPath = $registryFixture.Settings; FontDirectoryPath = $registryFixture.FontDirectory
        FontRegistryPath = $testRegistryPath; StarshipExecutable = $registryFixture.FakeStarship
        SkipStarshipInstall = $true; TestMode = $true
    }
    & $scriptPath -Action Install @registryCommon *> $null
    $managedTarget = [IO.Path]::GetFullPath($regularFile)
    Assert-True ((Get-RawRegistryValue -Path $testRegistryPath -Name $regular) -eq $managedTarget) 'managed registry value missing'
    $fontState = Join-Path $registryFixture.FontDirectory 'setup-starship-catppuccin.font-state.json'
    Assert-True (Test-Path -LiteralPath $fontState) 'font registration sidecar missing'
    & $scriptPath -Action Remove @registryCommon *> $null
    Assert-True ((Get-Content -Raw $regularFile) -eq 'original user font') 'conflicting font file was not restored'
    Assert-True ((Get-RawRegistryValue -Path $testRegistryPath -Name $regular) -eq $priorRegistryValue) 'same-target prior registry value was not restored'
    Assert-True ((Get-Item -LiteralPath $testRegistryPath).GetValueKind($regular).ToString() -eq 'String') 'same-target prior registry kind was not restored'
    Assert-True ((Get-Item -LiteralPath $testRegistryPath).GetValueKind($bold).ToString() -eq 'ExpandString') 'ExpandString kind was not restored'
    Assert-True ((Get-RawRegistryValue -Path $testRegistryPath -Name $bold) -eq $expandRegistryValue) 'ExpandString raw value was not restored'
    Assert-True (-not (Test-Path -LiteralPath $fontState)) 'font registration sidecar remained after restoration'

    & $scriptPath -Action Install @registryCommon *> $null
    New-ItemProperty -Path $testRegistryPath -Name $regular -Value 'C:\FixtureFonts\changed.ttf' -PropertyType String -Force | Out-Null
    $registryRemoveBefore = Get-TreeHash -Path $registryFixture.Root
    Assert-Fails { & $scriptPath -Action Remove @registryCommon *> $null } 'changed managed registry removal should fail'
    Assert-True ($registryRemoveBefore -eq (Get-TreeHash -Path $registryFixture.Root)) 'changed registry removal made partial changes'
    Assert-True ((Get-RawRegistryValue -Path $testRegistryPath -Name $regular) -eq 'C:\FixtureFonts\changed.ttf') 'changed registry value was overwritten'

    # Exact bytes and same target alone are ambiguous user state without a valid managed config stamp.
    $ambiguousFixture = New-Fixture -Name 'ambiguous-user-font'
    New-Item -Path $ambiguousRegistryPath -Force | Out-Null
    New-Item -ItemType Directory -Force -Path $ambiguousFixture.FontDirectory | Out-Null
    $ambiguousFile = Join-Path $ambiguousFixture.FontDirectory 'CaskaydiaCoveNerdFont-Regular.ttf'
    Copy-Item -LiteralPath (Join-Path $repoRoot 'assets\fonts\CaskaydiaCoveNerdFont-Regular.ttf') -Destination $ambiguousFile
    $ambiguousTarget = [IO.Path]::GetFullPath($ambiguousFile)
    New-ItemProperty -Path $ambiguousRegistryPath -Name $regular -Value $ambiguousTarget -PropertyType String -Force | Out-Null
    $ambiguousCommon = @{
        UserProfilePath = $ambiguousFixture.UserRoot; PowerShellProfilePaths = @($ambiguousFixture.Profile)
        WindowsTerminalSettingsPath = $ambiguousFixture.Settings; FontDirectoryPath = $ambiguousFixture.FontDirectory
        FontRegistryPath = $ambiguousRegistryPath; StarshipExecutable = $ambiguousFixture.FakeStarship
        SkipStarshipInstall = $true; TestMode = $true
    }
    & $scriptPath -Action Install @ambiguousCommon *> $null
    $ambiguousState = Get-Content -Raw (Join-Path $ambiguousFixture.FontDirectory 'setup-starship-catppuccin.font-state.json') | ConvertFrom-Json
    $ambiguousEntry = @($ambiguousState.Entries | Where-Object { $_.RegistryName -eq $regular })[0]
    Assert-True ($ambiguousEntry.HadFile -and $ambiguousEntry.HadValue -and -not $ambiguousEntry.LegacyManaged) 'ambiguous user font was misclassified as legacy'
    & $scriptPath -Action Remove @ambiguousCommon *> $null
    Assert-True ((Get-FileHash -Algorithm SHA256 -LiteralPath $ambiguousFile).Hash -eq (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repoRoot 'assets\fonts\CaskaydiaCoveNerdFont-Regular.ttf')).Hash) 'ambiguous user font bytes were removed'
    Assert-True ((Get-RawRegistryValue -Path $ambiguousRegistryPath -Name $regular) -eq $ambiguousTarget) 'ambiguous user registry value was removed'
    Assert-True ((Get-Item -LiteralPath $ambiguousRegistryPath).GetValueKind($regular).ToString() -eq 'String') 'ambiguous user registry kind changed'

    # Matching config and stamp are the required evidence for a v0.1 managed font with no sidecar.
    $legacyFixture = New-Fixture -Name 'legacy-v010-font'
    New-Item -Path $legacyRegistryPath -Force | Out-Null
    New-Item -ItemType Directory -Force -Path $legacyFixture.FontDirectory | Out-Null
    $legacyFile = Join-Path $legacyFixture.FontDirectory 'CaskaydiaCoveNerdFont-Regular.ttf'
    $configSource = Join-Path $repoRoot 'assets\starship\catppuccin-powerline.toml'
    $legacyConfig = Join-Path $legacyFixture.UserRoot '.config\starship.toml'
    Copy-Item -LiteralPath $configSource -Destination $legacyConfig -Force
    $configHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $configSource).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText("$legacyConfig.setup-starship-catppuccin.sha256", $configHash + "`r`n")
    Copy-Item -LiteralPath (Join-Path $repoRoot 'assets\fonts\CaskaydiaCoveNerdFont-Regular.ttf') -Destination $legacyFile
    $legacyTarget = [IO.Path]::GetFullPath($legacyFile)
    New-ItemProperty -Path $legacyRegistryPath -Name $regular -Value $legacyTarget -PropertyType String -Force | Out-Null
    $legacyCommon = @{
        UserProfilePath = $legacyFixture.UserRoot; PowerShellProfilePaths = @($legacyFixture.Profile)
        WindowsTerminalSettingsPath = $legacyFixture.Settings; FontDirectoryPath = $legacyFixture.FontDirectory
        FontRegistryPath = $legacyRegistryPath; StarshipExecutable = $legacyFixture.FakeStarship
        SkipStarshipInstall = $true; TestMode = $true
    }
    & $scriptPath -Action Install @legacyCommon *> $null
    $legacyState = Get-Content -Raw (Join-Path $legacyFixture.FontDirectory 'setup-starship-catppuccin.font-state.json') | ConvertFrom-Json
    $legacyEntry = @($legacyState.Entries | Where-Object { $_.RegistryName -eq $regular })[0]
    Assert-True ($legacyEntry.HadFile -and $legacyEntry.LegacyManaged -and -not $legacyEntry.HadValue) 'v0.1 font was not classified as legacy-managed'
    & $scriptPath -Action Remove @legacyCommon *> $null
    Assert-True (-not (Test-Path -LiteralPath $legacyFile)) 'legacy managed font file remained'
    Assert-True (@((Get-Item -LiteralPath $legacyRegistryPath).GetValueNames()) -notcontains $regular) 'legacy managed registry value remained'

    $unsupportedFixture = New-Fixture -Name 'unsupported-registry'
    New-Item -Path $unsupportedRegistryPath -Force | Out-Null
    New-ItemProperty -Path $unsupportedRegistryPath -Name $regular -Value 7 -PropertyType DWord -Force | Out-Null
    $unsupportedCommon = @{
        UserProfilePath = $unsupportedFixture.UserRoot; PowerShellProfilePaths = @($unsupportedFixture.Profile)
        WindowsTerminalSettingsPath = $unsupportedFixture.Settings; FontDirectoryPath = $unsupportedFixture.FontDirectory
        FontRegistryPath = $unsupportedRegistryPath; StarshipExecutable = $unsupportedFixture.FakeStarship
        SkipStarshipInstall = $true; TestMode = $true
    }
    $unsupportedBefore = Get-TreeHash -Path $unsupportedFixture.Root
    Assert-Fails { & $scriptPath -Action Install @unsupportedCommon *> $null } 'unsupported registry type should fail preflight'
    Assert-True ($unsupportedBefore -eq (Get-TreeHash -Path $unsupportedFixture.Root)) 'unsupported registry type made a mutation'
    Assert-True ((Get-Item -LiteralPath $unsupportedRegistryPath).GetValueKind($regular).ToString() -eq 'DWord') 'unsupported registry kind was changed'

    $global:LASTEXITCODE = 0
    Write-Output 'PASS: configure-starship-windows.ps1 validates JSONC, Terminal readiness, paths, checksums, and registry rollback.'
} finally {
    if (Test-Path -LiteralPath $testRegistryPath) { Remove-Item -LiteralPath $testRegistryPath -Recurse -Force }
    if (Test-Path -LiteralPath $unsupportedRegistryPath) { Remove-Item -LiteralPath $unsupportedRegistryPath -Recurse -Force }
    if (Test-Path -LiteralPath $ambiguousRegistryPath) { Remove-Item -LiteralPath $ambiguousRegistryPath -Recurse -Force }
    if (Test-Path -LiteralPath $legacyRegistryPath) { Remove-Item -LiteralPath $legacyRegistryPath -Recurse -Force }
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
