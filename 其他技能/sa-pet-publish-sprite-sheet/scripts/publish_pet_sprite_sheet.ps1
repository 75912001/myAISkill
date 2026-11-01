[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceDirectory,

    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = "D:\src\github.com\sa.project\sa.desktop\assets\pet",

    [switch]$Overwrite
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# The pet entry owns its default output directory; shared GUI behavior lives in the core.
$skillDirectory = Split-Path -Parent $PSScriptRoot
$skillsDirectory = Split-Path -Parent $skillDirectory
$publisherPath = Join-Path $skillsDirectory "sa-texturepacker-core\scripts\publish_sprite_sheet.ps1"
if (-not (Test-Path -LiteralPath $publisherPath -PathType Leaf)) {
    Write-Host "TexturePacker core publisher is missing: $publisherPath" -ForegroundColor Red
    exit 1
}

$arguments = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $publisherPath,
    "-SourceDirectory", $SourceDirectory,
    "-OutputDirectory", $OutputDirectory
)
if ($Overwrite) {
    $arguments += "-Overwrite"
}
& powershell.exe @arguments
exit $LASTEXITCODE
