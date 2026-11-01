[CmdletBinding(DefaultParameterSetName = "Extract")]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "Extract")]
    [ValidateRange(0, 2147483647)]
    [int]$AnimationIndex,

    [Parameter(ParameterSetName = "Extract")]
    [switch]$Overwrite,

    [Parameter(ParameterSetName = "Extract")]
    [switch]$UpdateComments,

    [Parameter(Mandatory = $true, ParameterSetName = "Probe")]
    [switch]$Probe,

    [Parameter(Mandatory = $true, ParameterSetName = "SelfTest")]
    [switch]$SelfTest,

    [string]$ExecutablePath,

    [ValidateRange(1, 120)]
    [int]$StartupTimeoutSeconds = 15,

    [ValidateRange(10, 5000)]
    [int]$RefreshDelayMilliseconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Keep this script ASCII-compatible so Windows PowerShell 5.1 can read it without a BOM.
if ($UpdateComments -and -not $Overwrite) {
    throw "UpdateComments requires Overwrite."
}

if (-not $SelfTest) {
    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) {
        $ExecutablePath = ConvertFrom-Json '"D:\\\u8f6f\u4ef6\\\u7d20\u6750\u5bfc\u51fa\u5de5\u5177\\\u77f3\u5668\u65f6\u4ee3\u8d44\u6e90\u63d0\u53d6\u5668.exe"'
    }

    $ExecutablePath = [System.IO.Path]::GetFullPath($ExecutablePath)
    if (-not [System.IO.File]::Exists($ExecutablePath)) {
        throw "Extractor executable does not exist: $ExecutablePath"
    }
}

$characterOutputPath = "D:\src\github.com\sa.project\server\config\character.sprite.yaml"
$offsetOutputPath = "D:\src\github.com\sa.project\server\docs\offset.yaml"
$characterMetadataToolPath = "D:\src\github.com\sa.project\server\tool\character_sprite_metadata.py"
$characterSpriteDataPath = "D:\csa_8.0\data\spr_115.bin"
$characterSpriteAddressPath = "D:\csa_8.0\data\spradrn_115.bin"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class CharacterExtractorNative
{
    public delegate bool EnumWindowProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    public sealed class WindowInfo
    {
        public long Handle { get; set; }
        public int ControlId { get; set; }
        public string ClassName { get; set; }
        public string Text { get; set; }
        public bool Visible { get; set; }
        public int Left { get; set; }
        public int Top { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
    }

    [DllImport("user32.dll")]
    private static extern bool EnumChildWindows(IntPtr hWndParent, EnumWindowProc callback, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr hWnd, StringBuilder className, int maxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);

    [DllImport("user32.dll")]
    private static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out Rect rect);

    [DllImport("user32.dll")]
    private static extern bool GetClientRect(IntPtr hWnd, out Rect rect);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern int GetDlgCtrlID(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int command);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr processId);

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    private static extern bool AttachThreadInput(uint sourceThreadId, uint targetThreadId, bool attach);

    [DllImport("user32.dll")]
    private static extern IntPtr SetFocus(IntPtr hWnd);

    public static void FocusControl(IntPtr window, IntPtr control)
    {
        ShowWindow(window, 5);
        SetForegroundWindow(window);

        uint currentThreadId = GetCurrentThreadId();
        uint targetThreadId = GetWindowThreadProcessId(control, IntPtr.Zero);
        bool attached = currentThreadId != targetThreadId &&
            AttachThreadInput(currentThreadId, targetThreadId, true);
        try
        {
            SetFocus(control);
        }
        finally
        {
            if (attached)
            {
                AttachThreadInput(currentThreadId, targetThreadId, false);
            }
        }
    }

    public static void ClickUpDown(IntPtr control, bool up)
    {
        Rect rect;
        if (!GetClientRect(control, out rect))
        {
            throw new InvalidOperationException("Could not read up-down control bounds.");
        }

        int width = rect.Right - rect.Left;
        int height = rect.Bottom - rect.Top;
        int x = Math.Max(1, width / 2);
        int y = up ? Math.Max(1, height / 4) : Math.Max(1, (height * 3) / 4);
        int packedPoint = (y << 16) | (x & 0xFFFF);

        SendMessage(control, 0x0201, new IntPtr(1), new IntPtr(packedPoint));
        SendMessage(control, 0x0202, IntPtr.Zero, new IntPtr(packedPoint));
    }

    public static List<WindowInfo> EnumerateChildren(IntPtr parent)
    {
        var result = new List<WindowInfo>();
        EnumChildWindows(parent, delegate(IntPtr child, IntPtr state)
        {
            var className = new StringBuilder(256);
            GetClassName(child, className, className.Capacity);

            int textLength = GetWindowTextLength(child);
            var text = new StringBuilder(Math.Max(textLength + 1, 2));
            GetWindowText(child, text, text.Capacity);

            Rect rect;
            GetWindowRect(child, out rect);

            result.Add(new WindowInfo
            {
                Handle = child.ToInt64(),
                ControlId = GetDlgCtrlID(child),
                ClassName = className.ToString(),
                Text = text.ToString(),
                Visible = IsWindowVisible(child),
                Left = rect.Left,
                Top = rect.Top,
                Width = rect.Right - rect.Left,
                Height = rect.Bottom - rect.Top
            });
            return true;
        }, IntPtr.Zero);
        return result;
    }
}
'@

$controlIds = @{
    AnimationIndex = "190"
    AnimationSpinner = 194
    ActionIndex = "200"
    ActionSpinner = 204
    FrameIndex = "230"
    FrameSpinner = 234
    TotalFrames = "480"
    TotalActions = "470"
    CurrentSequence = "450"
    SpecifiedSequence = "530"
    OffsetX = "400"
    OffsetY = "370"
    AutoPlay = 500
}

$directions = @(
    "down",
    "downleft",
    "left",
    "upleft",
    "up",
    "upright",
    "right",
    "downright"
)

$actionNames = @(
    "attack",
    "wave",
    "faint",
    "hurt",
    "defense",
    "sad",
    "angry",
    "sit",
    "stand",
    "throw",
    "nod",
    "walk",
    "happy"
)

$weaponNames = @("unarmed", "axe", "stick", "spear", "bow")
$fileCountLabel = ConvertFrom-Json '"\u4e2a\u6587\u4ef6"'

function Write-Status {
    param([string]$Message)
    [Console]::Error.WriteLine($Message)
}

function Find-ExtractorProcess {
    param([string]$Path)

    $comparison = [System.StringComparer]::OrdinalIgnoreCase
    return Get-Process | Where-Object {
        try {
            $comparison.Equals($_.MainModule.FileName, $Path)
        }
        catch {
            $false
        }
    } | Select-Object -First 1
}

function Wait-MainWindow {
    param(
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutSeconds
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $Process.Refresh()
        if ($Process.MainWindowHandle -ne [IntPtr]::Zero) {
            return $Process.MainWindowHandle
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)

    throw "Extractor did not create a main window within $TimeoutSeconds seconds."
}

function Get-SupportedPatternNames {
    param([System.Windows.Automation.AutomationElement]$Element)

    $names = @()
    foreach ($pattern in $Element.GetSupportedPatterns()) {
        $names += $pattern.ProgrammaticName
    }
    return $names
}

function Get-UiaElement {
    param(
        [System.Windows.Automation.AutomationElement]$Root,
        [string]$AutomationId,
        [string]$Description
    )

    $condition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
        $AutomationId
    )
    $element = $Root.FindFirst(
        [System.Windows.Automation.TreeScope]::Descendants,
        $condition
    )
    if ($null -eq $element) {
        throw "Required UI control was not found: $Description (AutomationId=$AutomationId)."
    }
    return $element
}

function Get-NativeControlHandle {
    param(
        [object[]]$Controls,
        [int]$ControlId,
        [string]$Description
    )

    $control = $Controls | Where-Object { $_.ControlId -eq $ControlId } | Select-Object -First 1
    if ($null -eq $control) {
        throw "Required native control was not found: $Description (ControlId=$ControlId)."
    }
    return [IntPtr]$control.Handle
}

function Read-IntegerElement {
    param(
        [System.Windows.Automation.AutomationElement]$Element,
        [string]$Description
    )

    $text = $Element.Current.Name.Trim()
    $value = 0
    if (-not [int]::TryParse($text, [ref]$value)) {
        throw "UI control does not contain an integer: $Description ('$text')."
    }
    return $value
}

function Set-NumericElement {
    param(
        [System.Windows.Automation.AutomationElement]$Element,
        [IntPtr]$ControlHandle,
        [IntPtr]$SpinnerHandle,
        [int]$ExpectedValue,
        [string]$Description,
        [IntPtr]$WindowHandle,
        [int]$DelayMilliseconds
    )

    for ($attempt = 1; $attempt -le 2; $attempt++) {
        [CharacterExtractorNative]::FocusControl($WindowHandle, $ControlHandle)
        Start-Sleep -Milliseconds 30
        $emSetSel = 0x00B1
        [CharacterExtractorNative]::SendMessage(
            $ControlHandle,
            $emSetSel,
            [IntPtr]::Zero,
            [IntPtr](-1)
        ) | Out-Null
        [System.Windows.Forms.SendKeys]::SendWait($ExpectedValue.ToString([System.Globalization.CultureInfo]::InvariantCulture))
        Start-Sleep -Milliseconds 30

        if ($ExpectedValue -gt 1) {
            [CharacterExtractorNative]::ClickUpDown($SpinnerHandle, $false)
            Start-Sleep -Milliseconds $DelayMilliseconds
            [CharacterExtractorNative]::ClickUpDown($SpinnerHandle, $true)
        }
        else {
            [CharacterExtractorNative]::ClickUpDown($SpinnerHandle, $true)
            Start-Sleep -Milliseconds $DelayMilliseconds
            [CharacterExtractorNative]::ClickUpDown($SpinnerHandle, $false)
        }

        $deadline = [DateTime]::UtcNow.AddSeconds(2)
        do {
            Start-Sleep -Milliseconds $DelayMilliseconds
            try {
                $actualValue = Read-IntegerElement -Element $Element -Description $Description
                if ($actualValue -eq $ExpectedValue) {
                    return
                }
            }
            catch {
                # The control may be temporarily empty while the application refreshes.
            }
        } while ([DateTime]::UtcNow -lt $deadline)
    }

    $finalValue = Read-IntegerElement -Element $Element -Description $Description
    for ($correction = 1; $correction -le 5 -and $finalValue -ne $ExpectedValue; $correction++) {
        if ([Math]::Abs($ExpectedValue - $finalValue) -gt 5) {
            break
        }

        $clickUp = $finalValue -lt $ExpectedValue
        [CharacterExtractorNative]::ClickUpDown($SpinnerHandle, $clickUp)
        Start-Sleep -Milliseconds ($DelayMilliseconds * 2)
        $finalValue = Read-IntegerElement -Element $Element -Description $Description
    }

    if ($finalValue -eq $ExpectedValue) {
        return
    }

    throw "Failed to set $Description to $ExpectedValue; current value is $finalValue."
}

function Disable-AutoPlay {
    param([IntPtr]$ButtonHandle)

    $bmGetCheck = 0x00F0
    $bmClick = 0x00F5
    $checked = [CharacterExtractorNative]::SendMessage(
        $ButtonHandle,
        $bmGetCheck,
        [IntPtr]::Zero,
        [IntPtr]::Zero
    ).ToInt64()

    if ($checked -ne 0) {
        [CharacterExtractorNative]::SendMessage(
            $ButtonHandle,
            $bmClick,
            [IntPtr]::Zero,
            [IntPtr]::Zero
        ) | Out-Null
        Start-Sleep -Milliseconds 100
    }

    $finalState = [CharacterExtractorNative]::SendMessage(
        $ButtonHandle,
        $bmGetCheck,
        [IntPtr]::Zero,
        [IntPtr]::Zero
    ).ToInt64()
    if ($finalState -ne 0) {
        throw "Failed to disable automatic frame playback."
    }
}

function Read-StableFrameData {
    param(
        [System.Windows.Automation.AutomationElement]$AnimationElement,
        [System.Windows.Automation.AutomationElement]$ActionElement,
        [System.Windows.Automation.AutomationElement]$FrameElement,
        [System.Windows.Automation.AutomationElement]$SequenceElement,
        [System.Windows.Automation.AutomationElement]$SpecifiedSequenceElement,
        [System.Windows.Automation.AutomationElement]$OffsetXElement,
        [System.Windows.Automation.AutomationElement]$OffsetYElement,
        [int]$ExpectedAnimation,
        [int]$ExpectedAction,
        [int]$ExpectedFrame,
        [int]$DelayMilliseconds
    )

    $deadline = [DateTime]::UtcNow.AddSeconds(3)
    $lastSample = ""
    $matchingSamples = 0
    $lastError = "UI values did not stabilize."

    do {
        Start-Sleep -Milliseconds $DelayMilliseconds
        try {
            $actualAnimation = Read-IntegerElement -Element $AnimationElement -Description "animation index"
            $actualAction = Read-IntegerElement -Element $ActionElement -Description "action index"
            $actualFrame = Read-IntegerElement -Element $FrameElement -Description "frame index"
            $sequence = Read-IntegerElement -Element $SequenceElement -Description "current sequence"
            $specifiedSequence = Read-IntegerElement -Element $SpecifiedSequenceElement -Description "specified sequence"
            $offsetX = Read-IntegerElement -Element $OffsetXElement -Description "image offset X"
            $offsetY = Read-IntegerElement -Element $OffsetYElement -Description "image offset Y"

            if ($actualAnimation -ne $ExpectedAnimation) {
                throw "Animation changed to $actualAnimation."
            }
            if ($actualAction -ne $ExpectedAction) {
                throw "Action changed to $actualAction."
            }
            if ($actualFrame -ne $ExpectedFrame) {
                throw "Frame changed to $actualFrame."
            }
            if ($sequence -ne $specifiedSequence) {
                throw "Sequence values disagree: $sequence and $specifiedSequence."
            }

            $sample = "$sequence|$offsetX|$offsetY"
            if ($sample -eq $lastSample) {
                $matchingSamples++
            }
            else {
                $lastSample = $sample
                $matchingSamples = 1
            }

            if ($matchingSamples -ge 2) {
                return [PSCustomObject]@{
                    FrameId = $specifiedSequence
                    OffsetX = $offsetX
                    OffsetY = $offsetY
                }
            }
        }
        catch {
            $lastError = $_.Exception.Message
            $matchingSamples = 0
        }
    } while ([DateTime]::UtcNow -lt $deadline)

    throw "Failed to read stable frame data for action $ExpectedAction frame ${ExpectedFrame}: $lastError"
}

function Write-ControlProbe {
    param([IntPtr]$WindowHandle)

    $root = [System.Windows.Automation.AutomationElement]::FromHandle($WindowHandle)
    if ($null -eq $root) {
        throw "UI Automation could not attach to the extractor window."
    }

    $uiaRows = @()
    $all = $root.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition
    )
    for ($index = 0; $index -lt $all.Count; $index++) {
        $element = $all.Item($index)
        $current = $element.Current
        $rect = $current.BoundingRectangle
        $uiaRows += [PSCustomObject]@{
            Index = $index
            Name = $current.Name
            AutomationId = $current.AutomationId
            ControlType = $current.ControlType.ProgrammaticName
            ClassName = $current.ClassName
            Enabled = $current.IsEnabled
            Left = [int]$rect.Left
            Top = [int]$rect.Top
            Width = [int]$rect.Width
            Height = [int]$rect.Height
            Patterns = @(Get-SupportedPatternNames -Element $element)
        }
    }

    $nativeRows = @(
        [CharacterExtractorNative]::EnumerateChildren($WindowHandle) |
            Sort-Object Top, Left
    )

    [PSCustomObject]@{
        ProcessWindowHandle = $WindowHandle.ToInt64()
        UiaControls = $uiaRows
        NativeControls = $nativeRows
    } | ConvertTo-Json -Depth 6
}

function Format-SequenceRange {
    param([System.Collections.IEnumerable]$Values)

    # Comments count unique sequence values; frame arrays still preserve duplicates.
    $uniqueValues = New-Object "System.Collections.Generic.HashSet[int]"
    $minimum = [int]::MaxValue
    $maximum = [int]::MinValue
    foreach ($value in $Values) {
        $sequence = [int]$value
        [void]$uniqueValues.Add($sequence)
        if ($sequence -lt $minimum) {
            $minimum = $sequence
        }
        if ($sequence -gt $maximum) {
            $maximum = $sequence
        }
    }

    if ($uniqueValues.Count -eq 0) {
        throw "Cannot format an empty sequence range."
    }

    return "[$minimum,$maximum] $($uniqueValues.Count) $fileCountLabel"
}

function Get-WeaponName {
    param([int]$Id)

    if ($Id -lt 0) {
        throw "Character sprite ID cannot be negative: $Id"
    }

    return $weaponNames[$Id % $weaponNames.Count]
}

function Get-AttackFrameCount {
    param([System.Collections.IDictionary]$CapturedFrames)

    $counts = New-Object "System.Collections.Generic.HashSet[int]"
    foreach ($direction in $directions) {
        $count = $CapturedFrames[$direction]["attack"].Count
        if ($count -lt 1) {
            throw "Attack action has no frames: $direction"
        }
        [void]$counts.Add([int]$count)
    }

    if ($counts.Count -ne 1) {
        $details = foreach ($direction in $directions) {
            "$direction=$($CapturedFrames[$direction]['attack'].Count)"
        }
        throw "Attack frame counts differ by direction; cannot derive one shared impact frame: $([string]::Join(', ', [string[]]$details))"
    }

    return [int](@($counts)[0])
}

function Get-CharacterEntryLines {
    param(
        [System.Collections.IDictionary]$CapturedFrames,
        [int]$Id,
        [string[]]$MetadataLines
    )

    $weaponName = Get-WeaponName -Id $Id
    $commentActionNames = @($actionNames)
    if ($weaponName -ne "unarmed") {
        $commentActionNames = @($actionNames | Where-Object { $_ -ne "throw" })
    }

    $allValues = New-Object System.Collections.Generic.List[int]
    foreach ($direction in $directions) {
        foreach ($actionName in $commentActionNames) {
            foreach ($value in $CapturedFrames[$direction][$actionName]) {
                $allValues.Add([int]$value)
            }
        }
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $entryRange = Format-SequenceRange -Values $allValues
    $lines.Add("  - id: $Id # ${weaponName}: #$entryRange")

    if ($null -eq $MetadataLines -or $MetadataLines.Count -eq 0) {
        $attackFrameCount = Get-AttackFrameCount -CapturedFrames $CapturedFrames
        $lines.Add("    attackImpactFrameNumberList: [$attackFrameCount]")
    }
    else {
        foreach ($metadataLine in $MetadataLines) {
            $lines.Add($metadataLine)
        }
    }

    foreach ($direction in $directions) {
        $directionValues = New-Object System.Collections.Generic.List[int]
        foreach ($actionName in $commentActionNames) {
            foreach ($value in $CapturedFrames[$direction][$actionName]) {
                $directionValues.Add([int]$value)
            }
        }

        $directionRange = Format-SequenceRange -Values $directionValues
        $lines.Add("    ${direction}: #$directionRange")
        foreach ($actionName in $actionNames) {
            $values = [string]::Join(",", [int[]]$CapturedFrames[$direction][$actionName])
            $lines.Add("      ${actionName}: [$values]")
        }
    }

    return $lines.ToArray()
}

function Get-ByteHash {
    param([byte[]]$Bytes)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha256.ComputeHash($Bytes)
        return ([System.BitConverter]::ToString($hashBytes)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-TextFileSnapshot {
    param([string]$Path)

    if (-not [System.IO.File]::Exists($Path)) {
        throw "Required output file does not exist: $Path"
    }

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF
    $contentOffset = if ($hasBom) { 3 } else { 0 }
    $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
    try {
        $content = $utf8.GetString($bytes, $contentOffset, $bytes.Length - $contentOffset)
    }
    catch {
        throw "File is not valid UTF-8: $Path"
    }

    $contentWithoutCrLf = $content.Replace("`r`n", "")
    if ($contentWithoutCrLf.Contains("`r")) {
        throw "File contains unsupported CR-only line endings: $Path"
    }
    if ($content.Contains("`r`n") -and $contentWithoutCrLf.Contains("`n")) {
        throw "File contains mixed CRLF and LF line endings: $Path"
    }

    $newLine = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    return [PSCustomObject]@{
        Path = $Path
        Hash = Get-ByteHash -Bytes $bytes
        Content = $content
        NewLine = $newLine
        HasBom = $hasBom
    }
}

function ConvertTo-Utf8Bytes {
    param(
        [string]$Content,
        [bool]$HasBom
    )

    $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $payload = $utf8.GetBytes($Content)
    if (-not $HasBom) {
        return ,$payload
    }

    $result = New-Object byte[] ($payload.Length + 3)
    $result[0] = 0xEF
    $result[1] = 0xBB
    $result[2] = 0xBF
    [System.Array]::Copy($payload, 0, $result, 3, $payload.Length)
    return ,$result
}

function Split-TextLines {
    param([string]$Content)

    return [regex]::Split($Content, "\r\n|\n")
}

function Get-CharacterSpriteEntries {
    param([string[]]$Lines)

    $rootCount = 0
    $starts = New-Object System.Collections.Generic.List[object]
    $seenIds = New-Object "System.Collections.Generic.HashSet[int]"
    for ($index = 0; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index] -match '^sprite:\s*(?:#.*)?$') {
            $rootCount++
        }

        $match = [regex]::Match($Lines[$index], '^  - id:\s*(?<id>\d+)(?:\s|$)')
        if (-not $match.Success) {
            continue
        }

        $id = [int]$match.Groups["id"].Value
        if (-not $seenIds.Add($id)) {
            throw "Duplicate character sprite ID in character.sprite.yaml: $id"
        }
        $starts.Add([PSCustomObject]@{
            Id = $id
            StartIndex = $index
        })
    }

    if ($rootCount -ne 1) {
        throw "Expected one top-level sprite mapping, found $rootCount."
    }
    if ($starts.Count -eq 0) {
        throw "character.sprite.yaml does not contain any sprite entries."
    }

    $entries = New-Object System.Collections.Generic.List[object]
    for ($entryIndex = 0; $entryIndex -lt $starts.Count; $entryIndex++) {
        $start = $starts[$entryIndex]
        $endIndex = $Lines.Count
        for ($lineIndex = $start.StartIndex + 1; $lineIndex -lt $Lines.Count; $lineIndex++) {
            if ($Lines[$lineIndex] -match '^  - id:\s*\d+(?:\s|$)' -or
                $Lines[$lineIndex] -match '^#{6,}\s*$') {
                $endIndex = $lineIndex
                break
            }
        }

        $entries.Add([PSCustomObject]@{
            Id = $start.Id
            StartIndex = $start.StartIndex
            EndIndex = $endIndex
        })
    }

    return $entries.ToArray()
}

function Get-EntryMetadataLines {
    param(
        [string[]]$Lines,
        [object]$Entry
    )

    $firstDirectionIndex = -1
    for ($index = $Entry.StartIndex + 1; $index -lt $Entry.EndIndex; $index++) {
        if ($Lines[$index] -match '^    down:\s*#') {
            $firstDirectionIndex = $index
            break
        }
    }
    if ($firstDirectionIndex -lt 0) {
        throw "Existing sprite ID $($Entry.Id) has no down direction."
    }

    $metadataLines = @($Lines[($Entry.StartIndex + 1)..($firstDirectionIndex - 1)])
    $impactCount = @($metadataLines | Where-Object {
        $_ -match '^    attackImpactFrameNumberList:\s*\[\s*[1-9]\d*(?:\s*,\s*[1-9]\d*)*\s*\]\s*(?:#.*)?$'
    }).Count
    if ($impactCount -ne 1) {
        throw "Existing sprite ID $($Entry.Id) must contain one valid attackImpactFrameNumberList."
    }

    return $metadataLines
}

function Assert-EntryActionSchema {
    param(
        [string[]]$Lines,
        [object]$Entry
    )

    $cursor = $Entry.StartIndex + 1
    while ($cursor -lt $Entry.EndIndex -and $Lines[$cursor] -notmatch '^    down:\s*#') {
        $cursor++
    }

    foreach ($direction in $directions) {
        if ($cursor -ge $Entry.EndIndex -or
            $Lines[$cursor] -notmatch "^    ${direction}:\s*#") {
            throw "Sprite ID $($Entry.Id) is missing direction '$direction' at the expected position."
        }
        $cursor++

        foreach ($actionName in $actionNames) {
            if ($cursor -ge $Entry.EndIndex -or
                $Lines[$cursor] -notmatch "^      ${actionName}:\s*\[\s*[1-9]\d*(?:\s*,\s*[1-9]\d*)*\s*\]\s*(?:#.*)?$") {
                throw "Sprite ID $($Entry.Id) is missing a valid '$direction.$actionName' frame array at the expected position."
            }
            $cursor++
            if ($cursor -lt $Entry.EndIndex -and
                $Lines[$cursor] -match "^      ${actionName}Raw:\s*\[\s*[1-9]\d*(?:\s*,\s*[1-9]\d*)*\s*\]\s*(?:#.*)?$") {
                $cursor++
            }
        }
    }

    while ($cursor -lt $Entry.EndIndex) {
        if (-not [string]::IsNullOrWhiteSpace($Lines[$cursor])) {
            throw "Sprite ID $($Entry.Id) contains unexpected content after the final action: $($Lines[$cursor])"
        }
        $cursor++
    }
}

function Resolve-OverwriteCommentLines {
    param(
        [string[]]$GeneratedLines,
        [string[]]$ExistingLines,
        [object]$Entry,
        [bool]$AllowUpdate
    )

    $existingComments = @{}
    $existingComments["entry"] = $ExistingLines[$Entry.StartIndex]
    for ($index = $Entry.StartIndex + 1; $index -lt $Entry.EndIndex; $index++) {
        $match = [regex]::Match(
            $ExistingLines[$index],
            '^    (?<direction>down|downleft|left|upleft|up|upright|right|downright):\s*#'
        )
        if ($match.Success) {
            $existingComments[$match.Groups["direction"].Value] = $ExistingLines[$index]
        }
    }

    $resolved = [string[]]$GeneratedLines.Clone()
    $changes = New-Object System.Collections.Generic.List[string]
    for ($index = 0; $index -lt $resolved.Count; $index++) {
        $key = $null
        if ($index -eq 0) {
            $key = "entry"
        }
        else {
            $match = [regex]::Match(
                $resolved[$index],
                '^    (?<direction>down|downleft|left|upleft|up|upright|right|downright):\s*#'
            )
            if ($match.Success) {
                $key = $match.Groups["direction"].Value
            }
        }

        if ($null -eq $key) {
            continue
        }
        if (-not $existingComments.ContainsKey($key)) {
            $changes.Add("Existing: <missing>`nProposed: $($resolved[$index])")
            continue
        }

        $existingLine = [string]$existingComments[$key]
        if ($existingLine.StartsWith($resolved[$index], [System.StringComparison]::Ordinal)) {
            $resolved[$index] = $existingLine
            continue
        }
        $changes.Add("Existing: $existingLine`nProposed: $($resolved[$index])")
    }

    if ($changes.Count -gt 0 -and -not $AllowUpdate) {
        $details = [string]::Join("`n", [string[]]$changes.ToArray())
        throw "Generated range comments differ from existing comments. No files were changed. Review and confirm these comment changes, then rerun with -Overwrite -UpdateComments:`n$details"
    }

    return $resolved
}

function Update-CharacterSpriteContent {
    param(
        [string]$Content,
        [string]$NewLine,
        [System.Collections.IDictionary]$CapturedFrames,
        [int]$Id,
        [bool]$AllowOverwrite,
        [bool]$AllowCommentUpdate
    )

    $lines = @(Split-TextLines -Content $Content)
    $entries = @(Get-CharacterSpriteEntries -Lines $lines)
    $targetEntries = @($entries | Where-Object { $_.Id -eq $Id })
    $resultLines = New-Object System.Collections.Generic.List[string]
    $mode = "appended"
    $metadataLines = $null
    $targetEntry = $null

    if ($targetEntries.Count -eq 1) {
        if (-not $AllowOverwrite) {
            throw "Character sprite ID $Id already exists. Confirm overwrite, then rerun with -Overwrite."
        }
        $targetEntry = $targetEntries[0]
        $metadataLines = @(Get-EntryMetadataLines -Lines $lines -Entry $targetEntry)
        $mode = "overwritten"
    }

    $generatedLines = @(
        Get-CharacterEntryLines `
            -CapturedFrames $CapturedFrames `
            -Id $Id `
            -MetadataLines $metadataLines
    )

    if ($null -ne $targetEntry) {
        $generatedLines = @(
            Resolve-OverwriteCommentLines `
                -GeneratedLines $generatedLines `
                -ExistingLines $lines `
                -Entry $targetEntry `
                -AllowUpdate $AllowCommentUpdate
        )
        for ($index = 0; $index -lt $targetEntry.StartIndex; $index++) {
            $resultLines.Add($lines[$index])
        }
        foreach ($line in $generatedLines) {
            $resultLines.Add($line)
        }
        for ($index = $targetEntry.EndIndex; $index -lt $lines.Count; $index++) {
            $resultLines.Add($lines[$index])
        }
    }
    else {
        $lastEntry = $entries[$entries.Count - 1]
        $insertIndex = $lastEntry.EndIndex
        for ($index = 0; $index -lt $insertIndex; $index++) {
            $resultLines.Add($lines[$index])
        }
        if (($Id % $weaponNames.Count) -eq 0 -and
            $insertIndex -gt 0 -and
            $lines[$insertIndex - 1] -notmatch '^#{6,}\s*$') {
            $resultLines.Add("######")
        }
        foreach ($line in $generatedLines) {
            $resultLines.Add($line)
        }
        for ($index = $insertIndex; $index -lt $lines.Count; $index++) {
            $resultLines.Add($lines[$index])
        }
    }

    $updatedContent = [string]::Join($NewLine, [string[]]$resultLines.ToArray())
    $updatedEntries = @(
        Get-CharacterSpriteEntries -Lines @(Split-TextLines -Content $updatedContent)
    )
    if (@($updatedEntries | Where-Object { $_.Id -eq $Id }).Count -ne 1) {
        throw "Updated character.sprite.yaml does not contain exactly one sprite ID $Id."
    }
    $updatedTargetEntry = @($updatedEntries | Where-Object { $_.Id -eq $Id })[0]
    Assert-EntryActionSchema `
        -Lines @(Split-TextLines -Content $updatedContent) `
        -Entry $updatedTargetEntry

    return [PSCustomObject]@{
        Content = $updatedContent
        EntryYaml = [string]::Join($NewLine, [string[]]$generatedLines) + $NewLine
        Mode = $mode
    }
}

function Read-OffsetYamlContent {
    param([string]$Content)

    $offsets = New-Object "System.Collections.Generic.Dictionary[int,object]"
    $lineNumber = 0
    $previousFrameId = -1
    foreach ($rawLine in @(Split-TextLines -Content $Content)) {
        $lineNumber++
        $line = $rawLine
        if ($lineNumber -eq 1) {
            $line = $line.TrimStart([char]0xFEFF)
        }
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
            throw "Invalid frame ID in offset YAML at line ${lineNumber}: $line"
        }
        if ($frameId -le $previousFrameId) {
            throw "Offset YAML frame IDs are not strictly ascending at line ${lineNumber}: $frameId"
        }
        if (-not [int]::TryParse($match.Groups["offsetX"].Value, [ref]$offsetX)) {
            throw "Invalid X offset in offset YAML at line ${lineNumber}: $line"
        }
        if (-not [int]::TryParse($match.Groups["offsetY"].Value, [ref]$offsetY)) {
            throw "Invalid Y offset in offset YAML at line ${lineNumber}: $line"
        }
        if (-not [int]::TryParse($match.Groups["width"].Value, [ref]$width) -or $width -lt 1) {
            throw "Invalid width in offset YAML at line ${lineNumber}: $line"
        }
        if (-not [int]::TryParse($match.Groups["height"].Value, [ref]$height) -or $height -lt 1) {
            throw "Invalid height in offset YAML at line ${lineNumber}: $line"
        }

        $offsets.Add($frameId, [PSCustomObject]@{
            OffsetX = $offsetX
            OffsetY = $offsetY
            Width = $width
            Height = $height
        })
        $previousFrameId = $frameId
    }

    return ,$offsets
}

function Confirm-FrameOffsets {
    param(
        [System.Collections.Generic.Dictionary[int,object]]$ExistingOffsets,
        [System.Collections.Generic.Dictionary[int,object]]$CapturedOffsets
    )

    foreach ($frameId in @($CapturedOffsets.Keys | Sort-Object)) {
        $captured = $CapturedOffsets[$frameId]
        if (-not $ExistingOffsets.ContainsKey([int]$frameId)) {
            throw "Frame metadata is missing for frame ID $frameId. The extractor only provides offsets, so width and height cannot be added safely."
        }

        $existing = $ExistingOffsets[$frameId]
        if ($existing.OffsetX -ne $captured.OffsetX -or $existing.OffsetY -ne $captured.OffsetY) {
            throw "Offset conflict for frame ID ${frameId}: metadata [$($existing.OffsetX),$($existing.OffsetY)], captured [$($captured.OffsetX),$($captured.OffsetY)]."
        }
    }
}

function Assert-SnapshotUnchanged {
    param([object]$Snapshot)

    if (-not [System.IO.File]::Exists($Snapshot.Path)) {
        throw "Output file disappeared during extraction: $($Snapshot.Path)"
    }

    $currentHash = Get-ByteHash -Bytes ([System.IO.File]::ReadAllBytes($Snapshot.Path))
    if ($currentHash -ne $Snapshot.Hash) {
        throw "Output file changed during extraction; refusing to overwrite concurrent changes: $($Snapshot.Path)"
    }
}

function Remove-TemporaryFile {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not [System.IO.File]::Exists($Path)) {
        return
    }
    try {
        [System.IO.File]::Delete($Path)
    }
    catch {
        Write-Status "Warning: failed to remove temporary file: $Path"
    }
}

function Write-OutputFilesTransactionally {
    param(
        [object]$CharacterSnapshot,
        [string]$CharacterContent,
        [object]$OffsetSnapshot,
        [string]$OffsetContent,
        [bool]$WriteOffset = $true
    )

    $characterDirectory = [System.IO.Path]::GetDirectoryName($CharacterSnapshot.Path)
    $characterName = [System.IO.Path]::GetFileName($CharacterSnapshot.Path)
    $offsetDirectory = [System.IO.Path]::GetDirectoryName($OffsetSnapshot.Path)
    $offsetName = [System.IO.Path]::GetFileName($OffsetSnapshot.Path)
    $characterTemporaryPath = [System.IO.Path]::Combine(
        $characterDirectory,
        ".${characterName}.$([Guid]::NewGuid().ToString('N')).tmp"
    )
    $characterBackupPath = [System.IO.Path]::Combine(
        $characterDirectory,
        ".${characterName}.$([Guid]::NewGuid().ToString('N')).bak"
    )
    $characterRollbackPath = [System.IO.Path]::Combine(
        $characterDirectory,
        ".${characterName}.$([Guid]::NewGuid().ToString('N')).rollback"
    )
    $offsetTemporaryPath = [System.IO.Path]::Combine(
        $offsetDirectory,
        ".${offsetName}.$([Guid]::NewGuid().ToString('N')).tmp"
    )
    $offsetBackupPath = [System.IO.Path]::Combine(
        $offsetDirectory,
        ".${offsetName}.$([Guid]::NewGuid().ToString('N')).bak"
    )
    $characterReplaced = $false

    try {
        [System.IO.File]::WriteAllBytes(
            $characterTemporaryPath,
            (ConvertTo-Utf8Bytes -Content $CharacterContent -HasBom $CharacterSnapshot.HasBom)
        )
        if ($WriteOffset) {
            [System.IO.File]::WriteAllBytes(
                $offsetTemporaryPath,
                (ConvertTo-Utf8Bytes -Content $OffsetContent -HasBom $OffsetSnapshot.HasBom)
            )
        }

        Assert-SnapshotUnchanged -Snapshot $CharacterSnapshot
        Assert-SnapshotUnchanged -Snapshot $OffsetSnapshot

        [System.IO.File]::Replace(
            $characterTemporaryPath,
            $CharacterSnapshot.Path,
            $characterBackupPath
        )
        $characterReplaced = $true
        if ($WriteOffset) {
        try {
            [System.IO.File]::Replace(
                $offsetTemporaryPath,
                $OffsetSnapshot.Path,
                $offsetBackupPath
            )
        }
        catch {
            $offsetError = $_.Exception.Message
            try {
                [System.IO.File]::Replace(
                    $characterBackupPath,
                    $CharacterSnapshot.Path,
                    $characterRollbackPath
                )
                $characterReplaced = $false
            }
            catch {
                throw "Failed to update offsets ($offsetError), and failed to restore character.sprite.yaml: $($_.Exception.Message)"
            }
            throw "Failed to update offsets; character.sprite.yaml was restored: $offsetError"
        }
        }
    }
    finally {
        Remove-TemporaryFile -Path $characterTemporaryPath
        Remove-TemporaryFile -Path $offsetTemporaryPath
        Remove-TemporaryFile -Path $characterBackupPath
        Remove-TemporaryFile -Path $characterRollbackPath
        Remove-TemporaryFile -Path $offsetBackupPath
    }
}

function Get-ExtractionPreflight {
    param(
        [int]$Id,
        [bool]$AllowOverwrite
    )

    Assert-CharacterMetadataInputs
    $characterSnapshot = Get-TextFileSnapshot -Path $characterOutputPath
    $offsetSnapshot = Get-TextFileSnapshot -Path $offsetOutputPath
    $characterLines = @(Split-TextLines -Content $characterSnapshot.Content)
    $entries = @(Get-CharacterSpriteEntries -Lines $characterLines)
    $targetCount = @($entries | Where-Object { $_.Id -eq $Id }).Count

    # Validate both destination files before starting any UI automation.
    $null = Read-OffsetYamlContent -Content $offsetSnapshot.Content
    if ($targetCount -eq 1) {
        $targetEntry = @($entries | Where-Object { $_.Id -eq $Id })[0]
        $null = Get-EntryMetadataLines -Lines $characterLines -Entry $targetEntry
        Assert-EntryActionSchema -Lines $characterLines -Entry $targetEntry
    }
    if ($targetCount -eq 1 -and -not $AllowOverwrite) {
        throw "Character sprite ID $Id already exists. Confirm overwrite, then rerun with -Overwrite."
    }

    return [PSCustomObject]@{
        CharacterSnapshot = $characterSnapshot
        OffsetSnapshot = $offsetSnapshot
        ExistingEntry = $targetCount -eq 1
    }
}

function Assert-SelfTest {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw "Self-test failed: $Message"
    }
}

function New-SelfTestCapturedFrames {
    param([int]$FirstFrameId)

    $captured = [ordered]@{}
    $nextFrameId = $FirstFrameId
    $directionIndex = 0
    foreach ($direction in $directions) {
        $captured[$direction] = [ordered]@{}
        foreach ($actionName in $actionNames) {
            $values = New-Object System.Collections.Generic.List[int]
            if ($actionName -eq "attack") {
                $values.Add($nextFrameId)
                $values.Add($nextFrameId + 1)
                $values.Add($nextFrameId + 1)
            }
            elseif ($actionName -eq "throw") {
                $values.Add(900000 + ($directionIndex * 10))
                $values.Add(900001 + ($directionIndex * 10))
            }
            else {
                $values.Add($nextFrameId)
            }
            $captured[$direction][$actionName] = $values
            $nextFrameId += 10
        }
        $directionIndex++
    }

    return $captured
}

function Invoke-SelfTest {
    $newLine = "`n"
    $captured = New-SelfTestCapturedFrames -FirstFrameId 1000
    $existingEntryLines = @(
        Get-CharacterEntryLines -CapturedFrames $captured -Id 240 -MetadataLines $null
    )
    $existingEntryLines[0] = $existingEntryLines[0] + " (manual)"
    $existingEntryLines[1] = "    attackImpactFrameNumberList: [2]"
    $characterLines = New-Object System.Collections.Generic.List[string]
    $characterLines.Add("sprite: # self-test")
    foreach ($line in $existingEntryLines) {
        $characterLines.Add($line)
    }
    $characterLines.Add("############################################################")
    $characterLines.Add("")
    $characterContent = [string]::Join($newLine, [string[]]$characterLines.ToArray())

    $appendResult = Update-CharacterSpriteContent `
        -Content $characterContent `
        -NewLine $newLine `
        -CapturedFrames $captured `
        -Id 241 `
        -AllowOverwrite $false `
        -AllowCommentUpdate $false
    Assert-SelfTest `
        -Condition ($appendResult.Mode -eq "appended") `
        -Message "missing ID was not appended"
    Assert-SelfTest `
        -Condition ($appendResult.Content.Contains("  - id: 241 # axe: #")) `
        -Message "appended ID does not use the expected weapon"
    Assert-SelfTest `
        -Condition ($appendResult.Content.Contains("    attackImpactFrameNumberList: [3]")) `
        -Message "new entry does not use the last attack frame position"

    $duplicateRejected = $false
    try {
        $null = Update-CharacterSpriteContent `
            -Content $characterContent `
            -NewLine $newLine `
            -CapturedFrames $captured `
            -Id 240 `
            -AllowOverwrite $false `
            -AllowCommentUpdate $false
    }
    catch {
        $duplicateRejected = $_.Exception.Message.Contains("already exists")
    }
    Assert-SelfTest -Condition $duplicateRejected -Message "existing ID was not rejected without overwrite"

    $overwriteResult = Update-CharacterSpriteContent `
        -Content $characterContent `
        -NewLine $newLine `
        -CapturedFrames $captured `
        -Id 240 `
        -AllowOverwrite $true `
        -AllowCommentUpdate $false
    Assert-SelfTest `
        -Condition ($overwriteResult.Content.Contains("    attackImpactFrameNumberList: [2]")) `
        -Message "overwrite changed existing impact frames"
    Assert-SelfTest `
        -Condition ($overwriteResult.Content.Contains("(manual)")) `
        -Message "overwrite discarded a still-valid manual comment"

    $differentCaptured = New-SelfTestCapturedFrames -FirstFrameId 2000
    $commentChangeRejected = $false
    try {
        $null = Update-CharacterSpriteContent `
            -Content $characterContent `
            -NewLine $newLine `
            -CapturedFrames $differentCaptured `
            -Id 240 `
            -AllowOverwrite $true `
            -AllowCommentUpdate $false
    }
    catch {
        $commentChangeRejected = $_.Exception.Message.Contains("Generated range comments differ")
    }
    Assert-SelfTest `
        -Condition $commentChangeRejected `
        -Message "changed comments were not rejected"

    $commentUpdateResult = Update-CharacterSpriteContent `
        -Content $characterContent `
        -NewLine $newLine `
        -CapturedFrames $differentCaptured `
        -Id 240 `
        -AllowOverwrite $true `
        -AllowCommentUpdate $true
    Assert-SelfTest `
        -Condition (-not $commentUpdateResult.Content.Contains("(manual)")) `
        -Message "approved comment replacement kept a stale manual suffix"
    Assert-SelfTest `
        -Condition ($commentUpdateResult.Content.Contains("    attackImpactFrameNumberList: [2]")) `
        -Message "approved comment replacement changed existing impact frames"

    $existingOffsets = Read-OffsetYamlContent -Content "# metadata`n10: [1,2,30,40]`n20: [3,4,50,60]`n"
    $capturedOffsets = New-Object "System.Collections.Generic.Dictionary[int,object]"
    $capturedOffsets.Add(20, [PSCustomObject]@{ OffsetX = 3; OffsetY = 4 })
    $null = Confirm-FrameOffsets -ExistingOffsets $existingOffsets -CapturedOffsets $capturedOffsets
    Assert-SelfTest -Condition ($existingOffsets[20].Width -eq 50 -and $existingOffsets[20].Height -eq 60) -Message "frame dimensions were not parsed"

    $missingOffsets = New-Object "System.Collections.Generic.Dictionary[int,object]"
    $missingOffsets.Add(30, [PSCustomObject]@{ OffsetX = 5; OffsetY = 6 })
    $missingRejected = $false
    try {
        $null = Confirm-FrameOffsets -ExistingOffsets $existingOffsets -CapturedOffsets $missingOffsets
    }
    catch {
        $missingRejected = $_.Exception.Message.Contains("Frame metadata is missing")
    }
    Assert-SelfTest -Condition $missingRejected -Message "missing four-field metadata was not rejected"

    $conflictingOffsets = New-Object "System.Collections.Generic.Dictionary[int,object]"
    $conflictingOffsets.Add(20, [PSCustomObject]@{ OffsetX = 99; OffsetY = 4 })
    $conflictRejected = $false
    try {
        $null = Confirm-FrameOffsets -ExistingOffsets $existingOffsets -CapturedOffsets $conflictingOffsets
    }
    catch {
        $conflictRejected = $_.Exception.Message.Contains("Offset conflict")
    }
    Assert-SelfTest -Condition $conflictRejected -Message "conflicting offset was not rejected"

    $transactionDirectory = [System.IO.Path]::Combine(
        [System.IO.Path]::GetTempPath(),
        "sa-character-extract-$([Guid]::NewGuid().ToString('N'))"
    )
    [void][System.IO.Directory]::CreateDirectory($transactionDirectory)
    try {
        $transactionCharacterPath = [System.IO.Path]::Combine($transactionDirectory, "character.sprite.yaml")
        $transactionOffsetPath = [System.IO.Path]::Combine($transactionDirectory, "offset.yaml")
        $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($transactionCharacterPath, "old-character`n", $utf8WithoutBom)
        [System.IO.File]::WriteAllText($transactionOffsetPath, "# metadata`n10: [1,2,30,40]`n", $utf8WithoutBom)
        $transactionCharacterSnapshot = Get-TextFileSnapshot -Path $transactionCharacterPath
        $transactionOffsetSnapshot = Get-TextFileSnapshot -Path $transactionOffsetPath
        Write-OutputFilesTransactionally `
            -CharacterSnapshot $transactionCharacterSnapshot `
            -CharacterContent "new-character`n" `
            -OffsetSnapshot $transactionOffsetSnapshot `
            -OffsetContent $transactionOffsetSnapshot.Content `
            -WriteOffset $false
        Assert-SelfTest `
            -Condition ([System.IO.File]::ReadAllText($transactionCharacterPath) -eq "new-character`n") `
            -Message "transaction did not replace character content"
        Assert-SelfTest `
            -Condition ([System.IO.File]::ReadAllText($transactionOffsetPath) -eq "# metadata`n10: [1,2,30,40]`n") `
            -Message "transaction changed read-only offset content"
    }
    finally {
        if ([System.IO.Directory]::Exists($transactionDirectory)) {
            [System.IO.Directory]::Delete($transactionDirectory, $true)
        }
    }

    $realCharacterSnapshot = Get-TextFileSnapshot -Path $characterOutputPath
    $realCharacterLines = @(Split-TextLines -Content $realCharacterSnapshot.Content)
    $realEntries = @(Get-CharacterSpriteEntries -Lines $realCharacterLines)
    foreach ($entry in $realEntries) {
        $null = Get-EntryMetadataLines -Lines $realCharacterLines -Entry $entry
        Assert-EntryActionSchema -Lines $realCharacterLines -Entry $entry
    }
    $completedRealCharacterContent = Complete-CharacterMetadata -Content $realCharacterSnapshot.Content -CharacterSnapshot $realCharacterSnapshot
    Assert-SelfTest -Condition ([string]::Equals($completedRealCharacterContent, $realCharacterSnapshot.Content, [System.StringComparison]::Ordinal)) -Message "formal metadata generator changed the normalized real character config"
    $realOffsetSnapshot = Get-TextFileSnapshot -Path $offsetOutputPath
    $realOffsets = Read-OffsetYamlContent -Content $realOffsetSnapshot.Content
    Assert-SelfTest -Condition ($realOffsets.Count -gt 0) -Message "real offset YAML is empty"

    Write-Status "Self-test passed: append, overwrite, comment guard, metadata seed, formal metadata staging, four-field offset validation, and real file compatibility."
}

function Invoke-Extraction {
if ($SelfTest) {
    Invoke-SelfTest
    exit 0
}

$preflight = $null
if (-not $Probe) {
    $preflight = Get-ExtractionPreflight -Id $AnimationIndex -AllowOverwrite $Overwrite
}

$process = Find-ExtractorProcess -Path $ExecutablePath
if ($null -eq $process) {
    $startArguments = @{
        FilePath = $ExecutablePath
        WorkingDirectory = [System.IO.Path]::GetDirectoryName($ExecutablePath)
        PassThru = $true
    }
    $process = Start-Process @startArguments
}

$windowHandle = Wait-MainWindow -Process $process -TimeoutSeconds $StartupTimeoutSeconds

if ($Probe) {
    Write-ControlProbe -WindowHandle $windowHandle
    exit 0
}

[CharacterExtractorNative]::ShowWindow($windowHandle, 5) | Out-Null
[CharacterExtractorNative]::SetForegroundWindow($windowHandle) | Out-Null

$root = [System.Windows.Automation.AutomationElement]::FromHandle($windowHandle)
if ($null -eq $root) {
    throw "UI Automation could not attach to the extractor window."
}

$animationElement = Get-UiaElement -Root $root -AutomationId $controlIds.AnimationIndex -Description "animation index"
$actionElement = Get-UiaElement -Root $root -AutomationId $controlIds.ActionIndex -Description "action index"
$frameElement = Get-UiaElement -Root $root -AutomationId $controlIds.FrameIndex -Description "frame index"
$totalFramesElement = Get-UiaElement -Root $root -AutomationId $controlIds.TotalFrames -Description "total frames"
$totalActionsElement = Get-UiaElement -Root $root -AutomationId $controlIds.TotalActions -Description "total actions"
$sequenceElement = Get-UiaElement -Root $root -AutomationId $controlIds.CurrentSequence -Description "current sequence"
$specifiedSequenceElement = Get-UiaElement -Root $root -AutomationId $controlIds.SpecifiedSequence -Description "specified sequence"
$offsetXElement = Get-UiaElement -Root $root -AutomationId $controlIds.OffsetX -Description "image offset X"
$offsetYElement = Get-UiaElement -Root $root -AutomationId $controlIds.OffsetY -Description "image offset Y"

$nativeControls = @([CharacterExtractorNative]::EnumerateChildren($windowHandle))
$autoPlayHandle = Get-NativeControlHandle -Controls $nativeControls -ControlId $controlIds.AutoPlay -Description "automatic playback"
$animationHandle = Get-NativeControlHandle -Controls $nativeControls -ControlId ([int]$controlIds.AnimationIndex) -Description "animation index"
$animationSpinnerHandle = Get-NativeControlHandle -Controls $nativeControls -ControlId $controlIds.AnimationSpinner -Description "animation spinner"
$actionHandle = Get-NativeControlHandle -Controls $nativeControls -ControlId ([int]$controlIds.ActionIndex) -Description "action index"
$actionSpinnerHandle = Get-NativeControlHandle -Controls $nativeControls -ControlId $controlIds.ActionSpinner -Description "action spinner"
$frameHandle = Get-NativeControlHandle -Controls $nativeControls -ControlId ([int]$controlIds.FrameIndex) -Description "frame index"
$frameSpinnerHandle = Get-NativeControlHandle -Controls $nativeControls -ControlId $controlIds.FrameSpinner -Description "frame spinner"

Disable-AutoPlay -ButtonHandle $autoPlayHandle
$setAnimationArguments = @{
    Element = $animationElement
    ControlHandle = $animationHandle
    SpinnerHandle = $animationSpinnerHandle
    ExpectedValue = $AnimationIndex
    Description = "animation index"
    WindowHandle = $windowHandle
    DelayMilliseconds = $RefreshDelayMilliseconds
}
Set-NumericElement @setAnimationArguments

$totalActions = Read-IntegerElement -Element $totalActionsElement -Description "total actions"
$expectedActionCount = $directions.Count * $actionNames.Count
if ($totalActions -ne $expectedActionCount) {
    throw "Expected $expectedActionCount actions for animation $AnimationIndex, but the extractor reports $totalActions."
}

$capturedFrames = [ordered]@{}
foreach ($direction in $directions) {
    $capturedFrames[$direction] = [ordered]@{}
    foreach ($actionName in $actionNames) {
        $capturedFrames[$direction][$actionName] = New-Object System.Collections.Generic.List[int]
    }
}
$capturedOffsets = New-Object "System.Collections.Generic.Dictionary[int,object]"

$totalCapturedFrames = 0
for ($actionIndex = 1; $actionIndex -le $expectedActionCount; $actionIndex++) {
    $setActionArguments = @{
        Element = $actionElement
        ControlHandle = $actionHandle
        SpinnerHandle = $actionSpinnerHandle
        ExpectedValue = $actionIndex
        Description = "action index"
        WindowHandle = $windowHandle
        DelayMilliseconds = $RefreshDelayMilliseconds
    }
    Set-NumericElement @setActionArguments

    $frameCount = Read-IntegerElement -Element $totalFramesElement -Description "total frames"
    if ($frameCount -lt 1) {
        throw "Action $actionIndex has an invalid frame count: $frameCount."
    }

    $directionIndex = [int][Math]::Floor(($actionIndex - 1) / $actionNames.Count)
    $actionNameIndex = ($actionIndex - 1) % $actionNames.Count
    $direction = $directions[$directionIndex]
    $actionName = $actionNames[$actionNameIndex]
    Write-Status "Extracting action $actionIndex/$expectedActionCount ($direction.$actionName), frames: $frameCount"

    for ($frameIndex = 1; $frameIndex -le $frameCount; $frameIndex++) {
        $setFrameArguments = @{
            Element = $frameElement
            ControlHandle = $frameHandle
            SpinnerHandle = $frameSpinnerHandle
            ExpectedValue = $frameIndex
            Description = "frame index"
            WindowHandle = $windowHandle
            DelayMilliseconds = $RefreshDelayMilliseconds
        }
        Set-NumericElement @setFrameArguments

        $readFrameDataArguments = @{
            AnimationElement = $animationElement
            ActionElement = $actionElement
            FrameElement = $frameElement
            SequenceElement = $sequenceElement
            SpecifiedSequenceElement = $specifiedSequenceElement
            OffsetXElement = $offsetXElement
            OffsetYElement = $offsetYElement
            ExpectedAnimation = $AnimationIndex
            ExpectedAction = $actionIndex
            ExpectedFrame = $frameIndex
            DelayMilliseconds = $RefreshDelayMilliseconds
        }
        $frameData = Read-StableFrameData @readFrameDataArguments
        $frameId = [int]$frameData.FrameId
        if ($frameId -lt 1) {
            throw "Action $actionIndex frame $frameIndex returned an invalid frame ID: $frameId"
        }

        $capturedFrames[$direction][$actionName].Add($frameId)
        if ($capturedOffsets.ContainsKey($frameId)) {
            $existingOffset = $capturedOffsets[$frameId]
            if ($existingOffset.OffsetX -ne $frameData.OffsetX -or $existingOffset.OffsetY -ne $frameData.OffsetY) {
                throw "Captured inconsistent offsets for frame ID ${frameId}: [$($existingOffset.OffsetX),$($existingOffset.OffsetY)] and [$($frameData.OffsetX),$($frameData.OffsetY)]."
            }
        }
        else {
            $capturedOffsets.Add($frameId, [PSCustomObject]@{
                OffsetX = [int]$frameData.OffsetX
                OffsetY = [int]$frameData.OffsetY
            })
        }
        $totalCapturedFrames++
    }
}

foreach ($direction in $directions) {
    foreach ($actionName in $actionNames) {
        if ($capturedFrames[$direction][$actionName].Count -lt 1) {
            throw "Extraction is incomplete: $direction.$actionName has no frames."
        }
    }
}

$finalAnimationIndex = Read-IntegerElement -Element $animationElement -Description "animation index"
if ($finalAnimationIndex -ne $AnimationIndex) {
    throw "Animation changed during extraction: expected $AnimationIndex, got $finalAnimationIndex."
}

$null = Get-AttackFrameCount -CapturedFrames $capturedFrames
$characterUpdate = Update-CharacterSpriteContent `
    -Content $preflight.CharacterSnapshot.Content `
    -NewLine $preflight.CharacterSnapshot.NewLine `
    -CapturedFrames $capturedFrames `
    -Id $AnimationIndex `
    -AllowOverwrite $Overwrite `
    -AllowCommentUpdate $UpdateComments
$existingOffsets = Read-OffsetYamlContent -Content $preflight.OffsetSnapshot.Content
$null = Confirm-FrameOffsets -ExistingOffsets $existingOffsets -CapturedOffsets $capturedOffsets
$completedCharacterContent = Complete-CharacterMetadata -Content $characterUpdate.Content -CharacterSnapshot $preflight.CharacterSnapshot
Assert-OnlyTargetCharacterEntryChanged -BeforeContent $characterUpdate.Content -AfterContent $completedCharacterContent -Id $AnimationIndex
$completedEntryYaml = Get-CharacterEntryYaml -Content $completedCharacterContent -NewLine $preflight.CharacterSnapshot.NewLine -Id $AnimationIndex

Write-OutputFilesTransactionally `
    -CharacterSnapshot $preflight.CharacterSnapshot `
    -CharacterContent $completedCharacterContent `
    -OffsetSnapshot $preflight.OffsetSnapshot `
    -OffsetContent $preflight.OffsetSnapshot.Content `
    -WriteOffset $false

Write-Status "Extraction complete. Animation: $AnimationIndex; mode: $($characterUpdate.Mode); actions: $expectedActionCount; frames: $totalCapturedFrames; verified offsets: $($capturedOffsets.Count); character: $characterOutputPath; offsets: $offsetOutputPath"
[Console]::Out.Write($completedEntryYaml)
}
function Get-CharacterMetadataPythonPath {
    $commands = @(
        Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue
    )
    if ($commands.Count -eq 0) {
        throw "python.exe is required to generate character sprite metadata."
    }

    return $commands[0].Source
}

function Assert-CharacterMetadataInputs {
    $requiredPaths = @(
        $characterMetadataToolPath,
        $characterSpriteDataPath,
        $characterSpriteAddressPath
    )
    foreach ($path in $requiredPaths) {
        if (-not [System.IO.File]::Exists($path)) {
            throw "Required character metadata input does not exist: $path"
        }
    }

    $null = Get-CharacterMetadataPythonPath
}

function Complete-CharacterMetadata {
    param(
        [string]$Content,
        [object]$CharacterSnapshot
    )

    Assert-CharacterMetadataInputs
    $characterDirectory = [System.IO.Path]::GetDirectoryName($CharacterSnapshot.Path)
    $characterName = [System.IO.Path]::GetFileName($CharacterSnapshot.Path)
    $temporaryPath = [System.IO.Path]::Combine(
        $characterDirectory,
        ".${characterName}.metadata.$([Guid]::NewGuid().ToString('N')).yaml"
    )

    try {
        [System.IO.File]::WriteAllBytes(
            $temporaryPath,
            (ConvertTo-Utf8Bytes -Content $Content -HasBom $CharacterSnapshot.HasBom)
        )
        $pythonPath = Get-CharacterMetadataPythonPath
        $metadataArguments = @(
            "-X",
            "utf8",
            $characterMetadataToolPath,
            "--spr",
            $characterSpriteDataPath,
            "--spr-address",
            $characterSpriteAddressPath,
            "--config",
            $temporaryPath,
            "--write"
        )
        $metadataOutput = @(& $pythonPath $metadataArguments)
        $metadataExitCode = $LASTEXITCODE
        foreach ($line in $metadataOutput) {
            Write-Status ([string]$line)
        }
        if ($metadataExitCode -ne 0) {
            throw "Character metadata generator failed with exit code $metadataExitCode. No formal configuration was changed."
        }

        $completedSnapshot = Get-TextFileSnapshot -Path $temporaryPath
        if ($completedSnapshot.HasBom -ne $CharacterSnapshot.HasBom) {
            throw "Character metadata generator changed the UTF-8 BOM state."
        }
        if ($completedSnapshot.NewLine -ne $CharacterSnapshot.NewLine) {
            throw "Character metadata generator changed the line-ending style."
        }

        $completedLines = @(Split-TextLines -Content $completedSnapshot.Content)
        $completedEntries = @(Get-CharacterSpriteEntries -Lines $completedLines)
        foreach ($entry in $completedEntries) {
            $null = Get-EntryMetadataLines -Lines $completedLines -Entry $entry
            Assert-EntryActionSchema -Lines $completedLines -Entry $entry
        }

        return $completedSnapshot.Content
    }
    finally {
        Remove-TemporaryFile -Path $temporaryPath
    }
}
function Get-CharacterContentWithoutTargetEntry {
    param(
        [string]$Content,
        [int]$Id
    )

    $lines = @(Split-TextLines -Content $Content)
    $entries = @(Get-CharacterSpriteEntries -Lines $lines)
    if (@($entries | Where-Object { $_.Id -eq $Id }).Count -ne 1) {
        throw "Character content must contain exactly one target sprite ID $Id."
    }

    $resultLines = New-Object System.Collections.Generic.List[string]
    $cursor = 0
    foreach ($entry in $entries) {
        while ($cursor -lt $entry.StartIndex) {
            $resultLines.Add($lines[$cursor])
            $cursor++
        }

        if ($entry.Id -eq $Id) {
            $resultLines.Add("__TARGET_CHARACTER_SPRITE_ENTRY__")
        }
        else {
            while ($cursor -lt $entry.EndIndex) {
                $resultLines.Add($lines[$cursor])
                $cursor++
            }
        }
        $cursor = $entry.EndIndex
    }
    while ($cursor -lt $lines.Count) {
        $resultLines.Add($lines[$cursor])
        $cursor++
    }

    return [string]::Join([char]10, [string[]]$resultLines.ToArray())
}

function Assert-OnlyTargetCharacterEntryChanged {
    param(
        [string]$BeforeContent,
        [string]$AfterContent,
        [int]$Id
    )

    $beforeWithoutTarget = Get-CharacterContentWithoutTargetEntry -Content $BeforeContent -Id $Id
    $afterWithoutTarget = Get-CharacterContentWithoutTargetEntry -Content $AfterContent -Id $Id
    if (-not [string]::Equals(
        $beforeWithoutTarget,
        $afterWithoutTarget,
        [System.StringComparison]::Ordinal
    )) {
        throw "Character metadata generation changed content outside sprite ID $Id."
    }
}

function Get-CharacterEntryYaml {
    param(
        [string]$Content,
        [string]$NewLine,
        [int]$Id
    )

    $lines = @(Split-TextLines -Content $Content)
    $entries = @(Get-CharacterSpriteEntries -Lines $lines)
    $targetEntries = @($entries | Where-Object { $_.Id -eq $Id })
    if ($targetEntries.Count -ne 1) {
        throw "Character content must contain exactly one target sprite ID $Id."
    }

    $targetEntry = $targetEntries[0]
    $entryLines = New-Object System.Collections.Generic.List[string]
    for ($index = $targetEntry.StartIndex; $index -lt $targetEntry.EndIndex; $index++) {
        $entryLines.Add($lines[$index])
    }
    return [string]::Join($NewLine, [string[]]$entryLines.ToArray()) + $NewLine
}

Invoke-Extraction
