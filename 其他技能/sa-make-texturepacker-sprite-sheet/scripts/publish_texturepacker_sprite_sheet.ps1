[CmdletBinding(DefaultParameterSetName = "Publish")]
param(
    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Publish")]
    [ValidateNotNullOrEmpty()]
    [string]$SourceDirectory,

    [Parameter(Mandatory = $true, ParameterSetName = "SelfTest")]
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Keep this script ASCII-compatible so Windows PowerShell 5.1 reads it consistently.
$offsetPath = "D:\src\github.com\sa.project\server\docs\offset.yaml"
$skillDirectory = [System.IO.Directory]::GetParent($PSScriptRoot).FullName
$skillsDirectory = [System.IO.Directory]::GetParent($skillDirectory).FullName
$publisherPath = Join-Path $skillsDirectory "sa-texturepacker-core\scripts\publish_sprite_sheet.ps1"
$normalizerPath = Join-Path $PSScriptRoot "normalize_tpsheet.py"

function Write-ErrorMessage {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Red
}

function Write-SuccessMessage {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
}

function Test-SamePath {
    param([string]$Left, [string]$Right)
    return [System.IO.Path]::GetFullPath($Left).Equals(
        [System.IO.Path]::GetFullPath($Right),
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function Read-OffsetYaml {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Offset YAML does not exist: $Path"
    }
    $offsets = New-Object "System.Collections.Generic.Dictionary[int,object]"
    $lineNumber = 0
    foreach ($rawLine in [System.IO.File]::ReadAllLines($Path)) {
        $lineNumber++
        $line = if ($lineNumber -eq 1) { $rawLine.TrimStart([char]0xFEFF) } else { $rawLine }
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith("#")) {
            continue
        }
        $match = [regex]::Match(
            $line,
            '^\s*(?<frameId>\d+)\s*:\s*\[\s*(?<offsetX>[+-]?\d+)\s*,\s*(?<offsetY>[+-]?\d+)\s*,\s*(?<width>\d+)\s*,\s*(?<height>\d+)\s*\]\s*$'
        )
        if (-not $match.Success) {
            throw "Invalid offset YAML at line ${lineNumber}: $line"
        }
        $frameId = 0
        $offsetX = 0
        $offsetY = 0
        $width = 0
        $height = 0
        if (-not [int]::TryParse($match.Groups["frameId"].Value, [ref]$frameId) -or $frameId -lt 1) {
            throw "Invalid frame ID in offset YAML at line ${lineNumber}."
        }
        if (-not [int]::TryParse($match.Groups["offsetX"].Value, [ref]$offsetX) -or
            -not [int]::TryParse($match.Groups["offsetY"].Value, [ref]$offsetY)) {
            throw "Invalid offset in offset YAML at line ${lineNumber}."
        }
        if (-not [int]::TryParse($match.Groups["width"].Value, [ref]$width) -or $width -lt 1 -or
            -not [int]::TryParse($match.Groups["height"].Value, [ref]$height) -or $height -lt 1) {
            throw "Invalid frame size in offset YAML at line ${lineNumber}."
        }
        if ($offsets.ContainsKey($frameId)) {
            throw "Duplicate frame ID in offset YAML: $frameId"
        }
        $offsets.Add($frameId, @($offsetX, $offsetY, $width, $height))
    }
    return ,$offsets
}

function Confirm-ExistingAtlas {
    param([string]$SheetPath, [string]$TexturePath, [string]$SpriteName)

    # A same-name PNG is excluded from source frames only after its atlas pair is validated.
    try {
        if (-not (Test-Path -LiteralPath $SheetPath -PathType Leaf)) {
            throw "The matching tpsheet is missing."
        }
        $sheet = Get-Content -LiteralPath $SheetPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (@($sheet.textures).Count -ne 1) {
            throw "Expected exactly one texture."
        }
        $texture = $sheet.textures[0]
        if ($texture.image -cne [System.IO.Path]::GetFileName($TexturePath)) {
            throw "The texture reference does not match the output PNG."
        }
        Add-Type -AssemblyName System.Drawing
        $image = [System.Drawing.Image]::FromFile($TexturePath)
        try {
            if ($image.RawFormat.Guid -ne [System.Drawing.Imaging.ImageFormat]::Png.Guid -or
                $texture.size.w -ne $image.Width -or $texture.size.h -ne $image.Height) {
                throw "PNG format or atlas dimensions do not match the tpsheet."
            }
            $sprites = @($texture.sprites)
            if ($sprites.Count -eq 0) {
                throw "The atlas has no sprites."
            }
            $seen = New-Object "System.Collections.Generic.HashSet[int]"
            foreach ($sprite in $sprites) {
                if ($sprite.frameid -isnot [int] -or $sprite.frameid -lt 1 -or
                    -not $seen.Add($sprite.frameid)) {
                    throw "Atlas frame IDs must be unique positive integers."
                }
                if ($sprite.frameid.ToString() -eq $SpriteName) {
                    throw "The output filename collides with a frame listed in the atlas."
                }
                $region = $sprite.region
                foreach ($field in @("x", "y", "w", "h")) {
                    if ($region.$field -isnot [int]) {
                        throw "Atlas regions must contain integer coordinates and sizes."
                    }
                }
                if ($region.x -lt 0 -or $region.y -lt 0 -or $region.w -le 0 -or $region.h -le 0 -or
                    [long]$region.x + $region.w -gt $image.Width -or
                    [long]$region.y + $region.h -gt $image.Height) {
                    throw "A sprite region lies outside the atlas PNG."
                }
            }
        }
        finally {
            $image.Dispose()
        }
    }
    catch {
        throw "Cannot verify existing output PNG as an atlas; refusing to exclude or overwrite it: $TexturePath. $($_.Exception.Message)"
    }
}

function Get-PublishPlan {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Source directory does not exist: $Path"
    }
    $directory = Get-Item -LiteralPath $Path -Force
    $spriteName = $directory.Name
    if ([string]::IsNullOrWhiteSpace($spriteName) -or
        $spriteName.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        throw "Source directory name cannot be used as the sprite-sheet name: $spriteName"
    }
    $sheetPath = Join-Path $directory.FullName ($spriteName + ".tpsheet")
    $texturePath = Join-Path $directory.FullName ($spriteName + ".png")
    if (Test-Path -LiteralPath $texturePath -PathType Leaf) {
        Confirm-ExistingAtlas -SheetPath $sheetPath -TexturePath $texturePath -SpriteName $spriteName
    }
    $sourceFiles = @(
        Get-ChildItem -LiteralPath $directory.FullName -Force |
            Where-Object {
                -not $_.PSIsContainer -and
                -not (Test-SamePath -Left $_.FullName -Right $sheetPath) -and
                -not (Test-SamePath -Left $_.FullName -Right $texturePath)
            } |
            Sort-Object FullName
    )
    if ($sourceFiles.Count -eq 0) {
        throw "Source directory contains no frame PNG files."
    }

    $invalidFiles = New-Object System.Collections.Generic.List[string]
    $frameIds = New-Object System.Collections.Generic.List[int]
    $seen = New-Object "System.Collections.Generic.HashSet[int]"
    foreach ($file in $sourceFiles) {
        if (-not $file.Extension.Equals(".png", [System.StringComparison]::OrdinalIgnoreCase) -or
            $file.BaseName -notmatch '^[1-9]\d*$') {
            $invalidFiles.Add($file.Name)
            continue
        }
        $frameId = 0
        if (-not [int]::TryParse($file.BaseName, [ref]$frameId) -or $frameId -lt 1) {
            $invalidFiles.Add($file.Name)
            continue
        }
        if (-not $seen.Add($frameId)) {
            throw "Duplicate frame ID: $frameId"
        }
        $frameIds.Add($frameId)
    }
    if ($invalidFiles.Count -gt 0) {
        throw "Source directory contains invalid files: $($invalidFiles -join ', ')"
    }

    return [PSCustomObject]@{
        SourceDirectory = $directory.FullName
        SpriteName = $spriteName
        SheetPath = $sheetPath
        TexturePath = $texturePath
        SourceFiles = $sourceFiles
        FrameIds = @($frameIds | Sort-Object)
    }
}

function Invoke-ExternalPowerShell {
    param([string]$ScriptPath, [string[]]$Arguments, [string]$Description)

    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    if ($exitCode -ne 0) {
        throw "$Description failed with exit code $exitCode."
    }
}

function Test-FinalOutputs {
    param([object]$Plan, [System.Collections.Generic.Dictionary[int,object]]$Offsets)

    foreach ($path in @($Plan.SheetPath, $Plan.TexturePath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-Item -LiteralPath $path -Force).Length -eq 0) {
            throw "Published output is missing or empty: $path"
        }
    }
    $rawSheet = Get-Content -LiteralPath $Plan.SheetPath -Raw -Encoding UTF8
    try {
        $sheet = $rawSheet | ConvertFrom-Json
    }
    catch {
        throw "Published tpsheet is not valid JSON: $($_.Exception.Message)"
    }
    if (@($sheet.textures).Count -ne 1 -or
        $sheet.textures[0].image -ne [System.IO.Path]::GetFileName($Plan.TexturePath)) {
        throw "Published tpsheet texture reference is invalid."
    }
    $sprites = @($sheet.textures[0].sprites)
    if ($sprites.Count -ne $Plan.FrameIds.Count) {
        throw "Published sprite count does not match source frame count."
    }
    $actualFrameIds = New-Object System.Collections.Generic.List[int]
    foreach ($sprite in $sprites) {
        $frameId = [int]$sprite.frameid
        if (-not $Offsets.ContainsKey($frameId) -or
            @($sprite.offset).Count -ne 2 -or
            [int]$sprite.offset[0] -ne [int]$Offsets[$frameId][0] -or
            [int]$sprite.offset[1] -ne [int]$Offsets[$frameId][1]) {
            throw "Published offset is invalid for frame ID: $frameId"
        }
        $actualFrameIds.Add($frameId)
    }
    $differences = @(
        Compare-Object -ReferenceObject @($Plan.FrameIds) -DifferenceObject @($actualFrameIds | Sort-Object)
    )
    if ($differences.Count -gt 0) {
        throw "Published frame IDs do not match source frame IDs."
    }
    $spriteLines = [regex]::Matches(
        $rawSheet,
        '(?m)^\s*\{[^\r\n]*"frameid"[^\r\n]*"offset"[^\r\n]*\},?\s*$'
    )
    if ($spriteLines.Count -ne $sprites.Count) {
        throw "Each sprite must occupy exactly one line with frameid and offset."
    }
}

function Restore-Outputs {
    param([object]$Plan, [string]$BackupDirectory, [hashtable]$Backups)

    foreach ($path in @($Plan.SheetPath, $Plan.TexturePath)) {
        if ($Backups.ContainsKey($path)) {
            Copy-Item -LiteralPath $Backups[$path] -Destination $path -Force
        }
        elseif (Test-Path -LiteralPath $path -PathType Leaf) {
            Remove-Item -LiteralPath $path -Force
        }
    }
}

function Invoke-SelfTest {
    $temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("sa-make-tpsheet-selftest-" + [Guid]::NewGuid().ToString("N"))
    try {
        $sourceDirectory = Join-Path $temporaryDirectory "sample"
        [void](New-Item -ItemType Directory -Path $sourceDirectory -Force)
        [System.IO.File]::WriteAllBytes((Join-Path $sourceDirectory "101.png"), [byte[]]@(1))
        [System.IO.File]::WriteAllBytes((Join-Path $sourceDirectory "202.PNG"), [byte[]]@(2))
        Add-Type -AssemblyName System.Drawing
        $bitmap = New-Object System.Drawing.Bitmap 4, 2
        try {
            $bitmap.Save((Join-Path $sourceDirectory "sample.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally {
            $bitmap.Dispose()
        }
        $validSheet = '{"textures":[{"image":"sample.png","size":{"w":4,"h":2},"sprites":[{"frameid":101,"region":{"x":0,"y":0,"w":2,"h":2}},{"frameid":202,"region":{"x":2,"y":0,"w":2,"h":2}}]}]}'
        [System.IO.File]::WriteAllText((Join-Path $sourceDirectory "sample.tpsheet"), $validSheet)
        $plan = Get-PublishPlan -Path $sourceDirectory
        if ($plan.FrameIds.Count -ne 2 -or $plan.FrameIds[0] -ne 101 -or $plan.FrameIds[1] -ne 202) {
            throw "Publish-plan self-test failed."
        }
        $numericDirectory = Join-Path $temporaryDirectory "277"
        [void](New-Item -ItemType Directory -Path $numericDirectory)
        Copy-Item -LiteralPath (Join-Path $sourceDirectory "101.png") -Destination $numericDirectory
        Copy-Item -LiteralPath (Join-Path $sourceDirectory "202.PNG") -Destination $numericDirectory
        $numericPlan = Get-PublishPlan -Path $numericDirectory
        if ($numericPlan.FrameIds.Count -ne 2 -or $numericPlan.SpriteName -ne "277") {
            throw "Numeric source directory self-test failed."
        }
        Copy-Item -LiteralPath $plan.TexturePath -Destination $numericPlan.TexturePath
        $numericSheet = $validSheet.Replace("sample.png", "277.png")
        [System.IO.File]::WriteAllText($numericPlan.SheetPath, $numericSheet)
        $numericPlan = Get-PublishPlan -Path $numericDirectory
        if ($numericPlan.FrameIds.Count -ne 2 -or $numericPlan.FrameIds -contains 277) {
            throw "Verified numeric atlas was not excluded from source frames."
        }
        # Exercise ambiguous and corrupt pairs without invoking GUI or changing the candidate files.
        $invalidSheets = @(
            $null,
            "{",
            "{}",
            $numericSheet.Replace("277.png", "other.png"),
            $numericSheet.Replace('"w":4', '"w":8'),
            $numericSheet.Replace('"frameid":101', '"frameid":277'),
            $numericSheet.Replace('"frameid":202', '"frameid":101'),
            $numericSheet.Replace('"x":2', '"x":4')
        )
        foreach ($invalidSheet in $invalidSheets) {
            if ($null -eq $invalidSheet) {
                Remove-Item -LiteralPath $numericPlan.SheetPath
            }
            else {
                [System.IO.File]::WriteAllText($numericPlan.SheetPath, $invalidSheet)
            }
            $pngBefore = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($numericPlan.TexturePath))
            $rejected = $false
            try {
                $null = Get-PublishPlan -Path $numericDirectory
            }
            catch {
                if ($_.Exception.Message -notlike "Cannot verify existing output PNG as an atlas;*") { throw }
                $rejected = $true
            }
            if (-not $rejected -or
                [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($numericPlan.TexturePath)) -ne $pngBefore) {
                throw "Unverified same-name PNG was accepted or changed."
            }
            if ($null -ne $invalidSheet -and
                [System.IO.File]::ReadAllText($numericPlan.SheetPath) -cne $invalidSheet) {
                throw "Invalid tpsheet was changed during preflight."
            }
        }
        [System.IO.File]::WriteAllText($numericPlan.SheetPath, $numericSheet)
        [System.IO.File]::WriteAllBytes($numericPlan.TexturePath, [byte[]]@(1, 2, 3))
        $rejected = $false
        try {
            $null = Get-PublishPlan -Path $numericDirectory
        }
        catch {
            if ($_.Exception.Message -notlike "Cannot verify existing output PNG as an atlas;*") { throw }
            $rejected = $true
        }
        if (-not $rejected -or [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($numericPlan.TexturePath)) -ne "AQID") {
            throw "Corrupt PNG was accepted or changed."
        }
        $testOffsetPath = Join-Path $temporaryDirectory "offset.yaml"
        [System.IO.File]::WriteAllText($testOffsetPath, "101: [-1,-2,2,2]`n202: [3,4,2,2]`n")
        $offsets = Read-OffsetYaml -Path $testOffsetPath
        if ($offsets.Count -ne 2 -or $offsets[202][1] -ne 4) {
            throw "Offset-parser self-test failed."
        }
        # Override only this test scope; never read production metadata or launch an external process.
        $offsetPath = $testOffsetPath
        $publisherPath = $testOffsetPath
        $normalizerPath = $testOffsetPath
        function Invoke-ExternalPowerShell {
            param([string]$ScriptPath, [string[]]$Arguments, [string]$Description)
            throw "Self-test forbids external process calls."
        }
        [System.IO.File]::WriteAllText($testOffsetPath, "303: [0,0,2,2]`n")
        $beforeContents = @{}
        foreach ($file in @(Get-ChildItem -LiteralPath $sourceDirectory -File) + @(Get-Item -LiteralPath $testOffsetPath)) {
            $beforeContents[$file.FullName] = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($file.FullName))
        }
        $rejectedMissingMetadata = $false
        try {
            Invoke-Publish
        }
        catch {
            if ($_.Exception.Message -notlike "Frame metadata is missing for frame IDs: 101, 202.*") {
                throw "Missing-metadata self-test failed: $($_.Exception.Message)"
            }
            $rejectedMissingMetadata = $true
        }
        if (-not $rejectedMissingMetadata) {
            throw "Missing-metadata self-test failed: publishing was not rejected."
        }
        foreach ($path in $beforeContents.Keys) {
            if ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($path)) -ne $beforeContents[$path]) {
                throw "Missing-metadata self-test changed a protected file: $path"
            }
        }
        Write-SuccessMessage "publish_texturepacker_sprite_sheet self-test passed."
    }
    finally {
        if (Test-Path -LiteralPath $temporaryDirectory -PathType Container) {
            Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
        }
    }
}

function Invoke-Publish {
    foreach ($requiredPath in @($offsetPath, $publisherPath, $normalizerPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Required file does not exist: $requiredPath"
        }
    }
    if ($null -eq (Get-Command python -ErrorAction SilentlyContinue)) {
        throw "Python is not available on PATH."
    }

    $plan = Get-PublishPlan -Path $SourceDirectory
    $offsets = Read-OffsetYaml -Path $offsetPath
    # Metadata is read-only. Reject missing four-field records before touching GUI or outputs.
    $missingFrameIds = @($plan.FrameIds | Where-Object { -not $offsets.ContainsKey([int]$_) })
    if ($missingFrameIds.Count -gt 0) {
        throw "Frame metadata is missing for frame IDs: $($missingFrameIds -join ', '). Supply complete [offsetX, offsetY, width, height] records through the authoritative metadata workflow before publishing."
    }

    $backupDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("sa-make-tpsheet-backup-" + [Guid]::NewGuid().ToString("N"))
    [void](New-Item -ItemType Directory -Path $backupDirectory -Force)
    $backups = @{}
    foreach ($path in @($plan.SheetPath, $plan.TexturePath)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $backupPath = Join-Path $backupDirectory ([System.IO.Path]::GetFileName($path))
            Copy-Item -LiteralPath $path -Destination $backupPath -Force
            $backups[$path] = $backupPath
        }
    }

    $removeBackup = $false
    try {
        # Remove backed-up outputs before import because the TexturePacker file dialog
        # selects every visible PNG in the source directory.
        foreach ($path in @($plan.SheetPath, $plan.TexturePath)) {
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                Remove-Item -LiteralPath $path -Force
            }
        }
        Write-Host "Do not use TexturePacker, the mouse, or the keyboard while publishing."
        Invoke-ExternalPowerShell `
            -ScriptPath $publisherPath `
            -Arguments @("-SourceDirectory", $plan.SourceDirectory, "-OutputDirectory", $plan.SourceDirectory, "-Overwrite") `
            -Description "TexturePacker publish"

        $normalizeArguments = @(
            $normalizerPath,
            "--sheet", $plan.SheetPath,
            "--texture-file-name", [System.IO.Path]::GetFileName($plan.TexturePath),
            "--frame-ids", ($plan.FrameIds -join ","),
            "--offset-config", $offsetPath
        )
        $normalizeOutput = & python @normalizeArguments 2>&1
        $normalizeExitCode = $LASTEXITCODE
        $normalizeOutput | ForEach-Object { Write-Host $_ }
        if ($normalizeExitCode -ne 0) {
            throw "tpsheet normalization failed with exit code $normalizeExitCode."
        }
        Test-FinalOutputs -Plan $plan -Offsets $offsets
        $removeBackup = $true
    }
    catch {
        $publishError = $_
        try {
            Restore-Outputs -Plan $plan -BackupDirectory $backupDirectory -Backups $backups
            $removeBackup = $true
        }
        catch {
            throw ("{0} Output recovery failed: {1} Backup retained at: {2}" -f $publishError.Exception.Message, $_.Exception.Message, $backupDirectory)
        }
        throw ("{0} Output recovery completed." -f $publishError.Exception.Message)
    }
    finally {
        # Delete recovery copies only after successful publishing or completed recovery.
        if ($removeBackup -and (Test-Path -LiteralPath $backupDirectory -PathType Container)) {
            Remove-Item -LiteralPath $backupDirectory -Recurse -Force
        }
    }

    Write-Output ("FRAME_COUNT={0}" -f $plan.FrameIds.Count)
    Write-Output ("EXISTING_OFFSET_COUNT={0}" -f $plan.FrameIds.Count)
    Write-Output "ADDED_OFFSET_COUNT=0"
    Write-Output ("OUTPUT_FILE={0}" -f $plan.SheetPath)
    Write-Output ("OUTPUT_FILE={0}" -f $plan.TexturePath)
    Write-Output "OUTPUT_FILE_COUNT=2"
    Write-SuccessMessage "TexturePacker sprite sheet published and validated successfully."
}

try {
    if ($SelfTest) {
        Invoke-SelfTest
    }
    else {
        Invoke-Publish
    }
}
catch {
    Write-ErrorMessage ("TexturePacker sprite-sheet creation failed: {0}" -f $_.Exception.Message)
    exit 1
}
