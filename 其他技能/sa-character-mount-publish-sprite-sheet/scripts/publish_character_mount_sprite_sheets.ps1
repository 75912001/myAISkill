[CmdletBinding()]
param(
    [switch]$PlanOnly,

    [switch]$Overwrite,

    [switch]$AcceptPlanCountChange,

    [string]$RoleName,

    [string]$MountDirectoryName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$consoleUtf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $consoleUtf8
$OutputEncoding = $consoleUtf8
$env:PYTHONUTF8 = "1"

$rolePetRoot = "D:\src\github.com\role_pet"
$characterConfigPath = "D:\src\github.com\sa.project\server\config\character.yaml"
$petConfigPath = "D:\src\github.com\sa.project\server\config\pet.yaml"
$offsetConfigPath = "D:\src\github.com\sa.project\server\docs\offset.yaml"
$outputDirectory = "D:\src\github.com\sa.project\sa.desktop\assets\character"
$petOutputDirectory = "D:\src\github.com\sa.project\sa.desktop\assets\pet"
$planScriptPath = Join-Path $PSScriptRoot "build_publish_plan.py"
$normalizeScriptPath = Join-Path $PSScriptRoot "normalize_tpsheet.py"
$skillRoot = Split-Path -Parent $PSScriptRoot
$skillsRoot = Split-Path -Parent $skillRoot
$texturePackerPublisherPath = Join-Path $skillsRoot (
    "sa-texturepacker-core\scripts\publish_sprite_sheet.ps1"
)
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)

function Print-Error {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host $Message -ForegroundColor Red
}

function Print-Success {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host $Message -ForegroundColor Green
}

function Get-SourceSpriteNames {
    param([Parameter(Mandatory = $true)][string]$SourceDirectory)

    $files = @(
        Get-ChildItem -LiteralPath $SourceDirectory -Force |
            Where-Object { -not $_.PSIsContainer } |
            Sort-Object -Property FullName
    )
    if ($files.Count -eq 0) {
        throw "源目录没有可发布文件: $SourceDirectory"
    }
    $unsupported = @(
        $files | Where-Object {
            -not $_.Name.EndsWith(
                ".png",
                [System.StringComparison]::OrdinalIgnoreCase
            )
        }
    )
    if ($unsupported.Count -gt 0) {
        throw (
            "角色骑宠源目录只允许 PNG: {0}" -f
            (($unsupported | ForEach-Object { $_.FullName }) -join ", ")
        )
    }
    $names = @($files | ForEach-Object { $_.BaseName } | Sort-Object)
    $duplicates = @(
        $names |
            Group-Object |
            Where-Object { $_.Count -gt 1 } |
            ForEach-Object { $_.Name }
    )
    if ($duplicates.Count -gt 0) {
        throw "源目录产生重复精灵名称: $($duplicates -join ', ')"
    }
    return $names
}

function Test-OutputPair {
    param(
        [Parameter(Mandatory = $true)][string]$DataFilePath,
        [Parameter(Mandatory = $true)][string]$TextureFilePath,
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [string]$ExpectedTextureFileName
    )

    try {
        if (-not (Test-Path -LiteralPath $DataFilePath -PathType Leaf) -or
            -not (Test-Path -LiteralPath $TextureFilePath -PathType Leaf)) {
            throw "PNG 或 .tpsheet 缺失"
        }
        $dataFile = Get-Item -LiteralPath $DataFilePath -Force
        $textureFile = Get-Item -LiteralPath $TextureFilePath -Force
        if ($dataFile.Length -eq 0 -or $textureFile.Length -eq 0) {
            throw "PNG 或 .tpsheet 是空文件"
        }
        $rawSheet = Get-Content -LiteralPath $DataFilePath -Raw -Encoding UTF8
        $sheet = $rawSheet |
            ConvertFrom-Json
        if (@($sheet.textures).Count -ne 1) {
            throw ".tpsheet 必须只包含一个纹理"
        }
        if ([string]::IsNullOrWhiteSpace($ExpectedTextureFileName)) {
            $ExpectedTextureFileName = [System.IO.Path]::GetFileName(
                $TextureFilePath
            )
        }
        $actualTextureFileName = [System.IO.Path]::GetFileName(
            [string]$sheet.textures[0].image
        )
        if ($actualTextureFileName -ne $ExpectedTextureFileName) {
            throw (
                ".tpsheet 纹理引用错误: 预期 {0}, 实际 {1}" -f
                $ExpectedTextureFileName,
                $actualTextureFileName
            )
        }

        $expectedNames = @(Get-SourceSpriteNames -SourceDirectory $SourceDirectory)
        $actualNames = @(
            $sheet.textures[0].sprites |
                ForEach-Object {
                    if ($_.PSObject.Properties.Name -notcontains "frameid") {
                        throw "sprite 缺少 frameid"
                    }
                    if ($_.PSObject.Properties.Name -contains "filename") {
                        throw "sprite 不能继续使用 filename"
                    }
                    if (@($_.offset).Count -ne 2) {
                        throw "sprite offset 必须是 [x, y]"
                    }
                    [string]$_.frameid
                } |
                Sort-Object
        )
        if ($actualNames.Count -ne $expectedNames.Count) {
            throw (
                "输出精灵数不匹配: 预期 {0}, 实际 {1}" -f
                $expectedNames.Count,
                $actualNames.Count
            )
        }
        $differences = @(
            Compare-Object `
                -ReferenceObject $expectedNames `
                -DifferenceObject $actualNames
        )
        if ($differences.Count -gt 0) {
            throw "输出精灵名称与源文件不一致"
        }
        $frameLineCount = [regex]::Matches(
            $rawSheet,
            '(?m)^\s*\{[^\r\n]*"frameid"[^\r\n]*"offset"[^\r\n]*\},?\s*$'
        ).Count
        if ($frameLineCount -ne $actualNames.Count) {
            throw "每个 sprite 必须独占一行并同时包含 frameid 和 offset"
        }
        return [PSCustomObject]@{ Valid = $true; Error = $null }
    }
    catch {
        return [PSCustomObject]@{
            Valid = $false
            Error = $_.Exception.Message
        }
    }
}

function Get-PublishPlan {
    if (-not (Test-Path -LiteralPath $planScriptPath -PathType Leaf)) {
        throw "发布计划脚本不存在: $planScriptPath"
    }
    $arguments = @(
        $planScriptPath,
        "--role-pet-root", $rolePetRoot,
        "--character-config", $characterConfigPath,
        "--pet-config", $petConfigPath
    )
    if (-not [string]::IsNullOrWhiteSpace($RoleName)) {
        $arguments += @("--role-name", $RoleName)
    }
    if (-not [string]::IsNullOrWhiteSpace($MountDirectoryName)) {
        $arguments += @("--mount-directory-name", $MountDirectoryName)
    }

    $planJson = & python @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "角色骑宠发布计划生成失败."
    }
    try {
        return $planJson | ConvertFrom-Json
    }
    catch {
        throw "角色骑宠发布计划不是有效 JSON: $($_.Exception.Message)"
    }
}

function Get-OutputPaths {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$OutputBase
    )
    return [PSCustomObject]@{
        Data = Join-Path $Directory ($OutputBase + ".tpsheet")
        Texture = Join-Path $Directory ($OutputBase + ".png")
    }
}

function Copy-OutputAlias {
    param(
        [Parameter(Mandatory = $true)][string]$SourceBase,
        [Parameter(Mandatory = $true)][string]$DestinationBase,
        [Parameter(Mandatory = $true)][string]$SourceDirectory
    )

    $sourcePaths = Get-OutputPaths `
        -Directory $outputDirectory `
        -OutputBase $SourceBase
    $destinationPaths = Get-OutputPaths `
        -Directory $outputDirectory `
        -OutputBase $DestinationBase
    $existingDestination = @(
        @($destinationPaths.Data, $destinationPaths.Texture) |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
    )
    if ($existingDestination.Count -gt 0 -and -not $Overwrite) {
        throw (
            "目标输出已存在, 需要用户确认覆盖: {0}" -f
            ($existingDestination -join ", ")
        )
    }

    $rawSheet = Get-Content -LiteralPath $sourcePaths.Data -Raw -Encoding UTF8
    $destinationTextureName = [System.IO.Path]::GetFileName(
        $destinationPaths.Texture
    )
    $imagePattern = '("image"\s*:\s*")[^"]+("\s*)'
    $script:replacementCount = 0
    $updatedSheet = [System.Text.RegularExpressions.Regex]::Replace(
        $rawSheet,
        $imagePattern,
        {
            param($match)
            $script:replacementCount++
            return (
                $match.Groups[1].Value +
                $destinationTextureName +
                $match.Groups[2].Value
            )
        },
        1
    )
    if ($script:replacementCount -ne 1) {
        throw "无法唯一改写 .tpsheet 的纹理文件名: $SourceBase"
    }

    $temporarySuffix = ".tmp." + [Guid]::NewGuid().ToString("N")
    $temporaryDataPath = $destinationPaths.Data + $temporarySuffix
    $temporaryTexturePath = $destinationPaths.Texture + $temporarySuffix
    try {
        Copy-Item `
            -LiteralPath $sourcePaths.Texture `
            -Destination $temporaryTexturePath
        [System.IO.File]::WriteAllText(
            $temporaryDataPath,
            $updatedSheet,
            $utf8WithoutBom
        )
        $validation = Test-OutputPair `
            -DataFilePath $temporaryDataPath `
            -TextureFilePath $temporaryTexturePath `
            -SourceDirectory $SourceDirectory `
            -ExpectedTextureFileName $destinationTextureName
        if (-not $validation.Valid) {
            throw "复用输出验证失败: $($validation.Error)"
        }
        Move-Item `
            -LiteralPath $temporaryTexturePath `
            -Destination $destinationPaths.Texture `
            -Force:$Overwrite
        Move-Item `
            -LiteralPath $temporaryDataPath `
            -Destination $destinationPaths.Data `
            -Force:$Overwrite
    }
    finally {
        if (Test-Path -LiteralPath $temporaryDataPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryDataPath -Force
        }
        if (Test-Path -LiteralPath $temporaryTexturePath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryTexturePath -Force
        }
    }

    $finalValidation = Test-OutputPair `
        -DataFilePath $destinationPaths.Data `
        -TextureFilePath $destinationPaths.Texture `
        -SourceDirectory $SourceDirectory
    if (-not $finalValidation.Valid) {
        throw "复用后的最终输出验证失败: $($finalValidation.Error)"
    }
}

function Publish-PrimaryOutput {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [Parameter(Mandatory = $true)][string]$OutputBase
    )

    if (-not (Test-Path -LiteralPath $texturePackerPublisherPath -PathType Leaf)) {
        throw "TexturePacker 基础发布脚本不存在: $texturePackerPublisherPath"
    }
    $destinationPaths = Get-OutputPaths `
        -Directory $outputDirectory `
        -OutputBase $OutputBase
    $petPaths = Get-OutputPaths `
        -Directory $petOutputDirectory `
        -OutputBase $OutputBase

    $stagingRoot = Join-Path `
        ([System.IO.Path]::GetTempPath()) `
        "sa-character-mount-publish"
    $stagingParent = Join-Path `
        $stagingRoot `
        ([Guid]::NewGuid().ToString("N"))
    $junctionPath = Join-Path $stagingParent $OutputBase
    New-Item -ItemType Directory -Path $stagingParent | Out-Null
    try {
        New-Item `
            -ItemType Junction `
            -Path $junctionPath `
            -Target $SourceDirectory | Out-Null

        $petValidation = Test-OutputPair `
            -DataFilePath $petPaths.Data `
            -TextureFilePath $petPaths.Texture `
            -SourceDirectory $SourceDirectory
        $petOutputExists = (
            (Test-Path -LiteralPath $petPaths.Data -PathType Leaf) -or
            (Test-Path -LiteralPath $petPaths.Texture -PathType Leaf)
        )
        if ($petOutputExists -and -not $petValidation.Valid -and -not $Overwrite) {
            throw (
                "assets/pet 存在同名暂存输出且验证失败, " +
                "确认覆盖后才能继续: $($petValidation.Error)"
            )
        }

        if (-not $petValidation.Valid -or $Overwrite) {
            $arguments = @(
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-File", $texturePackerPublisherPath,
                "-SourceDirectory", $junctionPath,
                "-OutputDirectory", $petOutputDirectory
            )
            if ($Overwrite -or $petOutputExists) {
                $arguments += "-Overwrite"
            }
            & powershell.exe @arguments
            if ($LASTEXITCODE -ne 0) {
                throw "TexturePacker 发布失败: $OutputBase"
            }
            & python `
                $normalizeScriptPath `
                --sheet $petPaths.Data `
                --texture-file-name ([System.IO.Path]::GetFileName($petPaths.Texture)) `
                --source-directory $SourceDirectory `
                --offset-config $offsetConfigPath
            if ($LASTEXITCODE -ne 0) {
                throw "TexturePacker 暂存 tpsheet 规范化失败: $OutputBase"
            }
            $petValidation = Test-OutputPair `
                -DataFilePath $petPaths.Data `
                -TextureFilePath $petPaths.Texture `
                -SourceDirectory $SourceDirectory
            if (-not $petValidation.Valid) {
                throw "TexturePacker 暂存输出验证失败: $($petValidation.Error)"
            }
        }

        $existingDestination = @(
            @($destinationPaths.Data, $destinationPaths.Texture) |
                Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
        )
        if ($existingDestination.Count -gt 0 -and -not $Overwrite) {
            throw (
                "目标输出已存在, 需要用户确认覆盖: {0}" -f
                ($existingDestination -join ", ")
            )
        }
        Move-Item `
            -LiteralPath $petPaths.Texture `
            -Destination $destinationPaths.Texture `
            -Force:$Overwrite
        Move-Item `
            -LiteralPath $petPaths.Data `
            -Destination $destinationPaths.Data `
            -Force:$Overwrite

        & python `
            $normalizeScriptPath `
            --sheet $destinationPaths.Data `
            --texture-file-name ([System.IO.Path]::GetFileName($destinationPaths.Texture)) `
            --source-directory $SourceDirectory `
            --offset-config $offsetConfigPath
        if ($LASTEXITCODE -ne 0) {
            throw "角色骑宠 tpsheet 规范化失败: $OutputBase"
        }

        $validation = Test-OutputPair `
            -DataFilePath $destinationPaths.Data `
            -TextureFilePath $destinationPaths.Texture `
            -SourceDirectory $SourceDirectory
        if (-not $validation.Valid) {
            throw "最终输出验证失败: $($validation.Error)"
        }
    }
    finally {
        if (Test-Path -LiteralPath $junctionPath) {
            $junction = Get-Item -LiteralPath $junctionPath -Force
            if ($junction.LinkType -ne "Junction") {
                throw "拒绝移除非目录连接的暂存路径: $junctionPath"
            }
            [System.IO.Directory]::Delete($junctionPath, $false)
        }
        if (Test-Path -LiteralPath $stagingParent -PathType Container) {
            $remaining = @(Get-ChildItem -LiteralPath $stagingParent -Force)
            if ($remaining.Count -eq 0) {
                Remove-Item -LiteralPath $stagingParent -Force
            }
        }
    }
}

function Invoke-CharacterMountPublish {
    foreach ($requiredPath in @(
            $rolePetRoot,
            $characterConfigPath,
            $petConfigPath,
            $offsetConfigPath,
            $outputDirectory,
            $petOutputDirectory
        )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "必需路径不存在: $requiredPath"
        }
    }

    $plan = Get-PublishPlan
    $items = @($plan.items)
    Write-Output ("SOURCE_DIRECTORY_COUNT={0}" -f $plan.source_directory_count)
    Write-Output ("OUTPUT_GROUP_COUNT={0}" -f $plan.output_group_count)
    if ($items.Count -eq 0) {
        throw "发布计划为空."
    }
    $isFullPlan = (
        [string]::IsNullOrWhiteSpace($RoleName) -and
        [string]::IsNullOrWhiteSpace($MountDirectoryName)
    )
    if ($isFullPlan -and
        ($plan.source_directory_count -ne 216 -or
            $plan.output_group_count -ne 216) -and
        -not $AcceptPlanCountChange) {
        throw (
            "完整计划数量变化: 预期 216 个源目录和 216 组输出, " +
            "实际 $($plan.source_directory_count) 和 $($plan.output_group_count). " +
            "用户确认后使用 -AcceptPlanCountChange."
        )
    }

    $validExistingCount = 0
    $invalidExisting = New-Object System.Collections.Generic.List[string]
    foreach ($item in $items) {
        $paths = Get-OutputPaths `
            -Directory $outputDirectory `
            -OutputBase $item.output_base
        $hasAnyOutput = (
            (Test-Path -LiteralPath $paths.Data -PathType Leaf) -or
            (Test-Path -LiteralPath $paths.Texture -PathType Leaf)
        )
        if (-not $hasAnyOutput) {
            continue
        }
        $validation = Test-OutputPair `
            -DataFilePath $paths.Data `
            -TextureFilePath $paths.Texture `
            -SourceDirectory $item.source_directory
        if ($validation.Valid) {
            $validExistingCount++
        }
        else {
            $invalidExisting.Add(
                "$($item.output_base): $($validation.Error)"
            )
        }
    }
    Write-Output ("VALID_EXISTING_COUNT={0}" -f $validExistingCount)
    Write-Output ("INVALID_EXISTING_COUNT={0}" -f $invalidExisting.Count)
    if ($invalidExisting.Count -gt 0 -and -not $Overwrite) {
        throw (
            "存在不完整或无效输出, 用户确认覆盖后才能继续: " +
            ($invalidExisting -join "; ")
        )
    }

    if ($PlanOnly) {
        foreach ($item in $items) {
            Write-Output (
                "PLAN={0}|{1}|sprite:{2}" -f
                $item.source_directory,
                $item.output_base,
                $item.mount_sprite_id
            )
        }
        Print-Success "角色骑宠精灵表发布计划验证成功, 未操作 TexturePacker."
        return
    }

    $generatedCount = 0
    $reusedCount = 0
    $skippedCount = 0
    $sourceGroups = @($items | Group-Object -Property source_directory)
    for ($sourceIndex = 0; $sourceIndex -lt $sourceGroups.Count; $sourceIndex++) {
        $group = $sourceGroups[$sourceIndex]
        $sourceDirectory = [string]$group.Name
        $groupItems = @($group.Group | Sort-Object -Property output_base)
        Write-Output (
            "SOURCE_PROGRESS={0}/{1}|{2}" -f
            ($sourceIndex + 1),
            $sourceGroups.Count,
            $sourceDirectory
        )

        $pendingItems = New-Object System.Collections.Generic.List[object]
        $templateItem = $null
        foreach ($item in $groupItems) {
            $paths = Get-OutputPaths `
                -Directory $outputDirectory `
                -OutputBase $item.output_base
            $validation = Test-OutputPair `
                -DataFilePath $paths.Data `
                -TextureFilePath $paths.Texture `
                -SourceDirectory $sourceDirectory
            if ($validation.Valid -and -not $Overwrite) {
                if ($null -eq $templateItem) {
                    $templateItem = $item
                }
                $skippedCount++
                continue
            }
            $pendingItems.Add($item)
        }
        if ($pendingItems.Count -eq 0) {
            continue
        }

        if ($null -eq $templateItem -or $Overwrite) {
            $templateItem = $pendingItems[0]
            Publish-PrimaryOutput `
                -SourceDirectory $sourceDirectory `
                -OutputBase $templateItem.output_base
            $generatedCount++
            [void]$pendingItems.Remove($templateItem)
        }

        foreach ($item in $pendingItems) {
            Copy-OutputAlias `
                -SourceBase $templateItem.output_base `
                -DestinationBase $item.output_base `
                -SourceDirectory $sourceDirectory
            $reusedCount++
        }
    }

    foreach ($item in $items) {
        $paths = Get-OutputPaths `
            -Directory $outputDirectory `
            -OutputBase $item.output_base
        $validation = Test-OutputPair `
            -DataFilePath $paths.Data `
            -TextureFilePath $paths.Texture `
            -SourceDirectory $item.source_directory
        if (-not $validation.Valid) {
            throw "最终批量复核失败: $($item.output_base): $($validation.Error)"
        }
        Write-Output ("OUTPUT_FILE={0}" -f $paths.Data)
        Write-Output ("OUTPUT_FILE={0}" -f $paths.Texture)
    }
    Write-Output ("TEXTUREPACKER_PUBLISH_COUNT={0}" -f $generatedCount)
    Write-Output ("REUSED_OUTPUT_COUNT={0}" -f $reusedCount)
    Write-Output ("SKIPPED_OUTPUT_COUNT={0}" -f $skippedCount)
    Write-Output ("OUTPUT_FILE_COUNT={0}" -f ($items.Count * 2))
    Print-Success "角色骑宠精灵表全部发布成功, 左侧精灵列表已清空."
}

try {
    Invoke-CharacterMountPublish
}
catch {
    Print-Error ("角色骑宠精灵表发布失败: {0}" -f $_.Exception.Message)
    Print-Error ("失败位置: {0}" -f $_.InvocationInfo.PositionMessage)
    Print-Error ("调用堆栈: {0}" -f $_.ScriptStackTrace)
    exit 1
}
