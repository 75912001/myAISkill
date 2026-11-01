[CmdletBinding(DefaultParameterSetName = "Extract")]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "Extract")]
    [ValidateRange(1, 2147483647)]
    [int]$AnimationIndex,

    [Parameter(Mandatory = $true, ParameterSetName = "Probe")]
    [switch]$Probe,

    [string]$ExecutablePath,

    [ValidateRange(1, 120)]
    [int]$StartupTimeoutSeconds = 15,

    [ValidateRange(10, 5000)]
    [int]$RefreshDelayMilliseconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Keep this script ASCII-compatible so Windows PowerShell 5.1 can read it without a BOM.
if ([string]::IsNullOrWhiteSpace($ExecutablePath)) {
    $ExecutablePath = ConvertFrom-Json '"D:\\\u8f6f\u4ef6\\\u7d20\u6750\u5bfc\u51fa\u5de5\u5177\\\u77f3\u5668\u65f6\u4ee3\u8d44\u6e90\u63d0\u53d6\u5668.exe"'
}

$ExecutablePath = [System.IO.Path]::GetFullPath($ExecutablePath)
if (-not [System.IO.File]::Exists($ExecutablePath)) {
    throw "Extractor executable does not exist: $ExecutablePath"
}

$fullOutputPath = $null
$offsetOutputPath = $null
if (-not $Probe) {
    $outputDirectory = "D:\src\github.com\sa.project\server\config"
    if (-not [System.IO.Directory]::Exists($outputDirectory)) {
        throw "Output directory does not exist: $outputDirectory"
    }

    $fullOutputPath = [System.IO.Path]::Combine($outputDirectory, "${AnimationIndex}.yaml")
    $offsetOutputPath = "D:\src\github.com\sa.project\server\docs\offset.yaml"
    if ([System.IO.File]::Exists($fullOutputPath)) {
        throw "Output file already exists; refusing to overwrite: $fullOutputPath"
    }
    if (-not [System.IO.File]::Exists($offsetOutputPath)) {
        throw "Frame metadata YAML does not exist: $offsetOutputPath"
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class PetExtractorNative
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
    "faint",
    "hurt",
    "defense",
    "stand",
    "walk",
    "attackShort"
)

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
        [PetExtractorNative]::FocusControl($WindowHandle, $ControlHandle)
        Start-Sleep -Milliseconds 30
        $emSetSel = 0x00B1
        [PetExtractorNative]::SendMessage(
            $ControlHandle,
            $emSetSel,
            [IntPtr]::Zero,
            [IntPtr](-1)
        ) | Out-Null
        [System.Windows.Forms.SendKeys]::SendWait($ExpectedValue.ToString([System.Globalization.CultureInfo]::InvariantCulture))
        Start-Sleep -Milliseconds 30

        if ($ExpectedValue -gt 1) {
            [PetExtractorNative]::ClickUpDown($SpinnerHandle, $false)
            Start-Sleep -Milliseconds $DelayMilliseconds
            [PetExtractorNative]::ClickUpDown($SpinnerHandle, $true)
        }
        else {
            [PetExtractorNative]::ClickUpDown($SpinnerHandle, $true)
            Start-Sleep -Milliseconds $DelayMilliseconds
            [PetExtractorNative]::ClickUpDown($SpinnerHandle, $false)
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
        [PetExtractorNative]::ClickUpDown($SpinnerHandle, $clickUp)
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
    $checked = [PetExtractorNative]::SendMessage(
        $ButtonHandle,
        $bmGetCheck,
        [IntPtr]::Zero,
        [IntPtr]::Zero
    ).ToInt64()

    if ($checked -ne 0) {
        [PetExtractorNative]::SendMessage(
            $ButtonHandle,
            $bmClick,
            [IntPtr]::Zero,
            [IntPtr]::Zero
        ) | Out-Null
        Start-Sleep -Milliseconds 100
    }

    $finalState = [PetExtractorNative]::SendMessage(
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
        [PetExtractorNative]::EnumerateChildren($WindowHandle) |
            Sort-Object Top, Left
    )

    [PSCustomObject]@{
        ProcessWindowHandle = $WindowHandle.ToInt64()
        UiaControls = $uiaRows
        NativeControls = $nativeRows
    } | ConvertTo-Json -Depth 6
}

function Format-SequenceRangeComment {
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

    return "# [$minimum,$maximum] $($uniqueValues.Count) $fileCountLabel"
}

function Format-SpriteYaml {
    param([System.Collections.IDictionary]$CapturedFrames)

    $lines = New-Object System.Collections.Generic.List[string]
    $allValues = New-Object System.Collections.Generic.List[int]
    foreach ($direction in $directions) {
        foreach ($actionName in $actionNames) {
            foreach ($value in $CapturedFrames[$direction][$actionName]) {
                $allValues.Add([int]$value)
            }
        }
    }

    $spriteComment = Format-SequenceRangeComment -Values $allValues
    $lines.Add("    sprite: $spriteComment")
    foreach ($direction in $directions) {
        $directionValues = New-Object System.Collections.Generic.List[int]
        foreach ($actionName in $actionNames) {
            foreach ($value in $CapturedFrames[$direction][$actionName]) {
                $directionValues.Add([int]$value)
            }
        }

        $directionComment = Format-SequenceRangeComment -Values $directionValues
        $lines.Add("      ${direction}: $directionComment")
        foreach ($actionName in $actionNames) {
            $values = [string]::Join(",", [int[]]$CapturedFrames[$direction][$actionName])
            $lines.Add("        ${actionName}: [$values]")
        }
    }
    return [string]::Join([Environment]::NewLine, $lines) + [Environment]::NewLine
}

function Read-OffsetYaml {
    param([string]$Path)

    $offsets = New-Object "System.Collections.Generic.Dictionary[int,object]"
    if (-not [System.IO.File]::Exists($Path)) {
        return ,$offsets
    }

    $lineNumber = 0
    foreach ($rawLine in [System.IO.File]::ReadAllLines($Path)) {
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
        if (-not [int]::TryParse($match.Groups["frameId"].Value, [ref]$frameId) -or $frameId -lt 1) {
            throw "Invalid frame ID in offset YAML at line ${lineNumber}: $line"
        }
        if (-not [int]::TryParse($match.Groups["offsetX"].Value, [ref]$offsetX)) {
            throw "Invalid X offset in offset YAML at line ${lineNumber}: $line"
        }
        if (-not [int]::TryParse($match.Groups["offsetY"].Value, [ref]$offsetY)) {
            throw "Invalid Y offset in offset YAML at line ${lineNumber}: $line"
        }
        if ($offsets.ContainsKey($frameId)) {
            throw "Duplicate frame ID in offset YAML at line ${lineNumber}: $frameId"
        }

        $offsets.Add($frameId, [PSCustomObject]@{
            OffsetX = $offsetX
            OffsetY = $offsetY
        })
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
function Write-NewUtf8File {
    param(
        [string]$Path,
        [string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    $stream = $null
    $writer = $null
    try {
        $stream = New-Object System.IO.FileStream(
            $Path,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        $writer = New-Object System.IO.StreamWriter($stream, $encoding)
        $writer.Write($Content)
    }
    finally {
        if ($null -ne $writer) {
            $writer.Dispose()
        }
        elseif ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

if (-not $Probe) {
    # Validate existing shared offsets before starting any UI automation.
    $null = Read-OffsetYaml -Path $offsetOutputPath
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

[PetExtractorNative]::ShowWindow($windowHandle, 5) | Out-Null
[PetExtractorNative]::SetForegroundWindow($windowHandle) | Out-Null

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

$nativeControls = @([PetExtractorNative]::EnumerateChildren($windowHandle))
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
if ($totalActions -ne 56) {
    throw "Expected 56 actions for animation $AnimationIndex, but the extractor reports $totalActions."
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
for ($actionIndex = 1; $actionIndex -le 56; $actionIndex++) {
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

    $directionIndex = [int][Math]::Floor(($actionIndex - 1) / 7)
    $actionNameIndex = ($actionIndex - 1) % 7
    $direction = $directions[$directionIndex]
    $actionName = $actionNames[$actionNameIndex]
    Write-Status "Extracting action $actionIndex/56 ($direction.$actionName), frames: $frameCount"

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

$yaml = Format-SpriteYaml -CapturedFrames $capturedFrames
$existingOffsets = Read-OffsetYaml -Path $offsetOutputPath
Confirm-FrameOffsets -ExistingOffsets $existingOffsets -CapturedOffsets $capturedOffsets

Write-NewUtf8File -Path $fullOutputPath -Content $yaml

Write-Status "Extraction complete. Animation: $AnimationIndex; actions: 56; frames: $totalCapturedFrames; verified offsets: $($capturedOffsets.Count); output: $fullOutputPath; metadata: $offsetOutputPath"
[Console]::Out.Write($yaml)
