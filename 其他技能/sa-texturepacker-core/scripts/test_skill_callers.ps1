[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$coreRoot = Split-Path -Parent $PSScriptRoot
$skillsRoot = Split-Path -Parent $coreRoot
$publisherPath = Join-Path $PSScriptRoot "publish_sprite_sheet.ps1"
$petPath = Join-Path $skillsRoot "sa-pet-publish-sprite-sheet/scripts/publish_pet_sprite_sheet.ps1"
$genericPath = Join-Path $skillsRoot "sa-make-texturepacker-sprite-sheet/scripts/publish_texturepacker_sprite_sheet.ps1"
$mountPath = Join-Path $skillsRoot "sa-character-mount-publish-sprite-sheet/scripts/publish_character_mount_sprite_sheets.ps1"

foreach ($path in @($publisherPath, $petPath, $genericPath, $mountPath)) {
    $tokens = $null
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw "PowerShell parse failed: $path" }
}
$command = Get-Command $publisherPath
foreach ($name in @("SourceDirectory", "OutputDirectory")) {
    $mandatory = @($command.Parameters[$name].Attributes | Where-Object {
        $_ -is [System.Management.Automation.ParameterAttribute] -and
        $_.ParameterSetName -eq "Publish" -and $_.Mandatory
    })
    if ($mandatory.Count -ne 1) { throw "Core publish parameter must be required: $name" }
}
foreach ($path in @($petPath, $genericPath, $mountPath)) {
    $content = [System.IO.File]::ReadAllText($path)
    if (-not $content.Contains('sa-texturepacker-core\scripts\publish_sprite_sheet.ps1') -or
        -not $content.Contains('"-OutputDirectory"')) {
        throw "Caller does not explicitly target the core and its output directory: $path"
    }
    if ($content.Contains('sa-pet-publish-sprite-sheet\scripts\publish_pet_sprite_sheet.ps1')) {
        throw "A caller still depends on the pet publisher: $path"
    }
}

# Execute the real pet adapter against a replacement core in an isolated directory tree.
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sa-texturepacker-callers-test-" + [Guid]::NewGuid().ToString("N"))
try {
    $testPetScripts = Join-Path $testRoot "sa-pet-publish-sprite-sheet/scripts"
    $testCoreScripts = Join-Path $testRoot "sa-texturepacker-core/scripts"
    [void](New-Item -ItemType Directory -Path $testPetScripts -Force)
    [void](New-Item -ItemType Directory -Path $testCoreScripts -Force)
    $testPetPath = Join-Path $testPetScripts "publish_pet_sprite_sheet.ps1"
    Copy-Item -LiteralPath $petPath -Destination $testPetPath
    $stub = @'
param([string]$SourceDirectory, [string]$OutputDirectory, [switch]$Overwrite)
@{ source = $SourceDirectory; output = $OutputDirectory; overwrite = [bool]$Overwrite } | ConvertTo-Json -Compress
if ($SourceDirectory -eq "failure-case") { exit 7 }
exit 0
'@
    [System.IO.File]::WriteAllText((Join-Path $testCoreScripts "publish_sprite_sheet.ps1"), $stub)
    $source = Join-Path $testRoot "source with spaces"
    $output = Join-Path $testRoot "output with spaces"
    $raw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $testPetPath -SourceDirectory $source
    $exitCode = $LASTEXITCODE
    $result = $raw | ConvertFrom-Json
    if ($exitCode -ne 0 -or $result.source -cne $source -or $result.overwrite -or
        $result.output -cne "D:\src\github.com\sa.project\sa.desktop\assets\pet") {
        throw "Pet default parameters were not forwarded correctly."
    }
    $raw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $testPetPath -SourceDirectory $source -OutputDirectory $output -Overwrite
    $exitCode = $LASTEXITCODE
    $result = $raw | ConvertFrom-Json
    if ($exitCode -ne 0 -or $result.source -cne $source -or $result.output -cne $output -or -not $result.overwrite) {
        throw "Explicit parameters were not forwarded correctly."
    }
    $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $testPetPath -SourceDirectory "failure-case"
    if ($LASTEXITCODE -ne 7) { throw "Core failure exit code was not preserved." }
    Write-Host "Three caller contracts and pet adapter parameter/exit-code tests passed without GUI access." -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        $resolved = [System.IO.Path]::GetFullPath($testRoot)
        $parent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
        if ([System.IO.Path]::GetDirectoryName($resolved).TrimEnd('\') -ne $parent -or
            [System.IO.Path]::GetFileName($resolved) -notlike "sa-texturepacker-callers-test-*") {
            throw "Refusing to remove unexpected caller-test directory."
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
