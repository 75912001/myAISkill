Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Load function definitions only, so this regression test never starts the GUI.
$scriptPath = Join-Path $PSScriptRoot "publish_texturepacker_sprite_sheet.ps1"
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw "Publisher syntax validation failed." }
foreach ($statement in $ast.EndBlock.Statements) {
    if ($statement -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
        . ([scriptblock]::Create($statement.Extent.Text))
    }
}

$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ("sa-recovery-test-" + [guid]::NewGuid().ToString("N"))
$retainedBackup = $null
try {
    [void](New-Item -ItemType Directory -Path $testDirectory)
    $SourceDirectory = $testDirectory
    $offsetPath = $scriptPath
    $publisherPath = $scriptPath
    $normalizerPath = $scriptPath
    $planFixture = [pscustomobject]@{
        SourceDirectory = $testDirectory
        SheetPath = Join-Path $testDirectory "sample.tpsheet"
        TexturePath = Join-Path $testDirectory "sample.png"
        FrameIds = @(101)
    }
    function Get-PublishPlan { param($Path) return $planFixture }
    function Read-OffsetYaml { param($Path) return @{101 = @(0, 0, 1, 1)} }
    function Invoke-ExternalPowerShell {
        param($ScriptPath, $Arguments, $Description)
        throw "Injected publish failure."
    }

    # Completed recovery restores both files and permits backup cleanup.
    [IO.File]::WriteAllText($planFixture.SheetPath, "old-sheet")
    [IO.File]::WriteAllText($planFixture.TexturePath, "old-png")
    $realRestore = ${function:Restore-Outputs}
    function Restore-Outputs {
        param($Plan, $BackupDirectory, $Backups)
        $script:retainedBackup = $BackupDirectory
        & $realRestore -Plan $Plan -BackupDirectory $BackupDirectory -Backups $Backups
    }
    $failure = $null
    try { Invoke-Publish } catch { $failure = $_.Exception.Message }
    if ($failure -notlike "*Injected publish failure.*Output recovery completed.*") { throw "Recovery completion was not reported: $failure" }
    if ([IO.File]::ReadAllText($planFixture.SheetPath) -ne "old-sheet" -or
        [IO.File]::ReadAllText($planFixture.TexturePath) -ne "old-png") { throw "Old outputs were not restored." }
    if (Test-Path -LiteralPath $retainedBackup) { throw "Completed recovery did not clean its backup." }

    # A failed restore must keep both original copies and report both errors and the path.
    function Restore-Outputs {
        param($Plan, $BackupDirectory, $Backups)
        $script:retainedBackup = $BackupDirectory
        throw "Injected restore failure."
    }
    $failure = $null
    try { Invoke-Publish } catch { $failure = $_.Exception.Message }
    if ($failure -notlike "*Injected publish failure.*Injected restore failure.*" -or
        -not $failure.Contains($retainedBackup)) { throw "Recovery failure details were lost: $failure" }
    if ([IO.File]::ReadAllText((Join-Path $retainedBackup "sample.tpsheet")) -ne "old-sheet" -or
        [IO.File]::ReadAllText((Join-Path $retainedBackup "sample.png")) -ne "old-png") { throw "Recovery backups were lost." }

    $success = Write-SuccessMessage "Test success" 6>&1
    $failureOutput = Write-ErrorMessage "Test failure" 6>&1
    if ($success.MessageData.ForegroundColor -ne [ConsoleColor]::Green -or
        $failureOutput.MessageData.ForegroundColor -ne [ConsoleColor]::Red) { throw "Status colors are incorrect." }
    Write-SuccessMessage "Output recovery and status color regression tests passed."
}
finally {
    # Remove only the isolated test directory and the backup captured from this test.
    foreach ($path in @($testDirectory, $retainedBackup)) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            $resolved = [IO.Path]::GetFullPath($path)
            if ([IO.Path]::GetDirectoryName($resolved) -ne [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')) {
                throw "Refusing cleanup outside the temporary directory: $resolved"
            }
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}
