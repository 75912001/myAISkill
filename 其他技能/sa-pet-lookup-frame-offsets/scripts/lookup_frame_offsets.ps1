[CmdletBinding(DefaultParameterSetName = "Lookup")]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "Lookup")]
    [Alias("FrameIds")]
    [ValidateNotNullOrEmpty()]
    [string[]]$FrameId,

    [Parameter(Mandatory = $true, ParameterSetName = "Probe")]
    [switch]$Probe,

    [string]$ExecutablePath,

    [string]$OffsetPath = "D:\src\github.com\sa.project\server\docs\offset.yaml",

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

$OffsetPath = [System.IO.Path]::GetFullPath($OffsetPath)
$offsetDirectory = [System.IO.Path]::GetDirectoryName($OffsetPath)
if (-not [System.IO.Directory]::Exists($offsetDirectory)) {
    throw "Frame metadata directory does not exist: $offsetDirectory"
}

if (-not $Probe) {
    $requestedFrameIds = New-Object System.Collections.Generic.List[int]
    $uniqueFrameIds = New-Object "System.Collections.Generic.HashSet[int]"
    foreach ($rawValue in $FrameId) {
        foreach ($token in [regex]::Split($rawValue.Trim(), '[,\s]+')) {
            if ([string]::IsNullOrWhiteSpace($token)) {
                continue
            }

            $parsedValue = 0
            if (-not [int]::TryParse($token, [ref]$parsedValue)) {
                throw "Frame ID is not a valid integer: $token"
            }
            if ($parsedValue -lt 1) {
                throw "Frame ID must be greater than zero: $parsedValue"
            }
            if (-not $uniqueFrameIds.Add($parsedValue)) {
                throw "Duplicate frame ID in request: $parsedValue"
            }
            $requestedFrameIds.Add($parsedValue)
        }
    }
    if ($requestedFrameIds.Count -eq 0) {
        throw "At least one frame ID is required."
    }
}

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class PetOffsetLookupNative
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
    private static extern bool EnumChildWindows(
        IntPtr hWndParent,
        EnumWindowProc callback,
        IntPtr lParam
    );

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(
        IntPtr hWnd,
        StringBuilder className,
        int maxCount
    );

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(
        IntPtr hWnd,
        StringBuilder text,
        int maxCount
    );

    [DllImport("user32.dll")]
    private static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out Rect rect);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern int GetDlgCtrlID(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int command);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(
        IntPtr hWnd,
        uint message,
        IntPtr wParam,
        IntPtr lParam
    );

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SendMessageW")]
    private static extern IntPtr SendMessageText(
        IntPtr hWnd,
        uint message,
        IntPtr wParam,
        string lParam
    );

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SendMessageW")]
    private static extern IntPtr SendMessageBuffer(
        IntPtr hWnd,
        uint message,
        IntPtr wParam,
        StringBuilder lParam
    );

    public static void SetControlText(IntPtr control, string text)
    {
        IntPtr result = SendMessageText(control, 0x000C, IntPtr.Zero, text);
        if (result == IntPtr.Zero)
        {
            throw new InvalidOperationException("Could not set edit control text.");
        }
    }

    public static string ReadControlText(IntPtr control)
    {
        int textLength = SendMessage(control, 0x000E, IntPtr.Zero, IntPtr.Zero).ToInt32();
        var text = new StringBuilder(Math.Max(textLength + 1, 2));
        SendMessageBuffer(control, 0x000D, new IntPtr(text.Capacity), text);
        return text.ToString();
    }

    public static void ClickButton(IntPtr control)
    {
        SendMessage(control, 0x00F5, IntPtr.Zero, IntPtr.Zero);
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
    CurrentSequence = "450"
    SpecifiedSequence = "530"
    Confirm = 540
    OffsetX = "400"
    OffsetY = "370"
    AutoPlay = 500
}

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

    $control = $Controls |
        Where-Object { $_.ControlId -eq $ControlId } |
        Select-Object -First 1
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

function Disable-AutoPlay {
    param([IntPtr]$ButtonHandle)

    $bmGetCheck = 0x00F0
    $bmClick = 0x00F5
    $checked = [PetOffsetLookupNative]::SendMessage(
        $ButtonHandle,
        $bmGetCheck,
        [IntPtr]::Zero,
        [IntPtr]::Zero
    ).ToInt64()

    if ($checked -ne 0) {
        [PetOffsetLookupNative]::SendMessage(
            $ButtonHandle,
            $bmClick,
            [IntPtr]::Zero,
            [IntPtr]::Zero
        ) | Out-Null
        Start-Sleep -Milliseconds 100
    }

    $finalState = [PetOffsetLookupNative]::SendMessage(
        $ButtonHandle,
        $bmGetCheck,
        [IntPtr]::Zero,
        [IntPtr]::Zero
    ).ToInt64()
    if ($finalState -ne 0) {
        throw "Failed to disable automatic frame playback."
    }
}

function Set-SpecifiedSequence {
    param(
        [IntPtr]$EditHandle,
        [IntPtr]$ConfirmHandle,
        [int]$ExpectedValue,
        [int]$DelayMilliseconds
    )

    $expectedText = $ExpectedValue.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    [PetOffsetLookupNative]::SetControlText($EditHandle, $expectedText)

    $deadline = [DateTime]::UtcNow.AddSeconds(2)
    $lastText = ""
    do {
        Start-Sleep -Milliseconds $DelayMilliseconds
        try {
            $lastText = [PetOffsetLookupNative]::ReadControlText($EditHandle).Trim()
            $actualValue = 0
            if (
                [int]::TryParse($lastText, [ref]$actualValue) -and
                $actualValue -eq $ExpectedValue
            ) {
                [PetOffsetLookupNative]::ClickButton($ConfirmHandle)
                return
            }
        }
        catch {
            # The edit control may be temporarily empty while the application refreshes.
        }
    } while ([DateTime]::UtcNow -lt $deadline)

    throw "Failed to verify specified sequence input: expected $ExpectedValue, native input is '$lastText'."
}

function Read-StableOffset {
    param(
        [System.Windows.Automation.AutomationElement]$SpecifiedSequenceElement,
        [System.Windows.Automation.AutomationElement]$CurrentSequenceElement,
        [System.Windows.Automation.AutomationElement]$OffsetXElement,
        [System.Windows.Automation.AutomationElement]$OffsetYElement,
        [int]$ExpectedFrameId,
        [int]$DelayMilliseconds
    )

    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    $lastSample = ""
    $matchingSamples = 0
    $lastError = "UI values did not stabilize."

    do {
        Start-Sleep -Milliseconds $DelayMilliseconds
        try {
            $specifiedSequence = Read-IntegerElement `
                -Element $SpecifiedSequenceElement `
                -Description "specified sequence"
            $currentSequence = Read-IntegerElement `
                -Element $CurrentSequenceElement `
                -Description "current sequence"
            $offsetX = Read-IntegerElement `
                -Element $OffsetXElement `
                -Description "image offset X"
            $offsetY = Read-IntegerElement `
                -Element $OffsetYElement `
                -Description "image offset Y"

            if ($specifiedSequence -ne $ExpectedFrameId) {
                throw "Specified sequence changed to $specifiedSequence."
            }
            if ($currentSequence -ne $ExpectedFrameId) {
                throw "Current sequence is $currentSequence."
            }

            $sample = "$currentSequence|$offsetX|$offsetY"
            if ($sample -eq $lastSample) {
                $matchingSamples++
            }
            else {
                $lastSample = $sample
                $matchingSamples = 1
            }

            if ($matchingSamples -ge 2) {
                return [PSCustomObject]@{
                    FrameId = $ExpectedFrameId
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

    throw "Failed to read stable offset for frame ID ${ExpectedFrameId}: $lastError"
}

function Write-ControlProbe {
    param([IntPtr]$WindowHandle)

    $root = [System.Windows.Automation.AutomationElement]::FromHandle($WindowHandle)
    if ($null -eq $root) {
        throw "UI Automation could not attach to the extractor window."
    }

    $requiredIds = @(
        $controlIds.CurrentSequence,
        $controlIds.SpecifiedSequence,
        $controlIds.Confirm.ToString(),
        $controlIds.OffsetX,
        $controlIds.OffsetY,
        $controlIds.AutoPlay.ToString()
    )
    $rows = @()
    foreach ($automationId in $requiredIds) {
        $element = Get-UiaElement `
            -Root $root `
            -AutomationId $automationId `
            -Description "probe control"
        $current = $element.Current
        $rows += [PSCustomObject]@{
            Name = $current.Name
            AutomationId = $current.AutomationId
            ControlType = $current.ControlType.ProgrammaticName
            ClassName = $current.ClassName
            Enabled = $current.IsEnabled
        }
    }

    $nativeRows = @(
        [PetOffsetLookupNative]::EnumerateChildren($WindowHandle) |
            Where-Object {
                $_.ControlId -in @(
                    [int]$controlIds.SpecifiedSequence,
                    $controlIds.Confirm,
                    $controlIds.AutoPlay
                )
            } |
            Sort-Object ControlId
    )

    [PSCustomObject]@{
        ProcessWindowHandle = $WindowHandle.ToInt64()
        RequiredUiaControls = $rows
        RequiredNativeControls = $nativeRows
    } | ConvertTo-Json -Depth 5
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

        $parsedFrameId = 0
        $offsetX = 0
        $offsetY = 0
        if (-not [int]::TryParse($match.Groups["frameId"].Value, [ref]$parsedFrameId) -or $parsedFrameId -lt 1) {
            throw "Invalid frame ID in offset YAML at line ${lineNumber}: $line"
        }
        if (-not [int]::TryParse($match.Groups["offsetX"].Value, [ref]$offsetX)) {
            throw "Invalid X offset in offset YAML at line ${lineNumber}: $line"
        }
        if (-not [int]::TryParse($match.Groups["offsetY"].Value, [ref]$offsetY)) {
            throw "Invalid Y offset in offset YAML at line ${lineNumber}: $line"
        }
        if ($offsets.ContainsKey($parsedFrameId)) {
            throw "Duplicate frame ID in offset YAML at line ${lineNumber}: $parsedFrameId"
        }

        $offsets.Add($parsedFrameId, [PSCustomObject]@{
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

    return $CapturedOffsets.Count
}
$existingOffsets = $null
if (-not $Probe) {
    # Validate the complete shared file before starting any UI automation.
    $existingOffsets = Read-OffsetYaml -Path $OffsetPath
}

$process = Find-ExtractorProcess -Path $ExecutablePath
if ($null -eq $process) {
    $process = Start-Process `
        -FilePath $ExecutablePath `
        -WorkingDirectory ([System.IO.Path]::GetDirectoryName($ExecutablePath)) `
        -PassThru
}

$windowHandle = Wait-MainWindow `
    -Process $process `
    -TimeoutSeconds $StartupTimeoutSeconds

if ($Probe) {
    Write-ControlProbe -WindowHandle $windowHandle
    exit 0
}

[PetOffsetLookupNative]::ShowWindow($windowHandle, 5) | Out-Null
[PetOffsetLookupNative]::SetForegroundWindow($windowHandle) | Out-Null

$root = [System.Windows.Automation.AutomationElement]::FromHandle($windowHandle)
if ($null -eq $root) {
    throw "UI Automation could not attach to the extractor window."
}

$currentSequenceElement = Get-UiaElement `
    -Root $root `
    -AutomationId $controlIds.CurrentSequence `
    -Description "current sequence"
$specifiedSequenceElement = Get-UiaElement `
    -Root $root `
    -AutomationId $controlIds.SpecifiedSequence `
    -Description "specified sequence"
$offsetXElement = Get-UiaElement `
    -Root $root `
    -AutomationId $controlIds.OffsetX `
    -Description "image offset X"
$offsetYElement = Get-UiaElement `
    -Root $root `
    -AutomationId $controlIds.OffsetY `
    -Description "image offset Y"

$nativeControls = @([PetOffsetLookupNative]::EnumerateChildren($windowHandle))
$autoPlayHandle = Get-NativeControlHandle `
    -Controls $nativeControls `
    -ControlId $controlIds.AutoPlay `
    -Description "automatic playback"
$specifiedSequenceHandle = Get-NativeControlHandle `
    -Controls $nativeControls `
    -ControlId ([int]$controlIds.SpecifiedSequence) `
    -Description "specified sequence"
$confirmHandle = Get-NativeControlHandle `
    -Controls $nativeControls `
    -ControlId $controlIds.Confirm `
    -Description "confirm"

Disable-AutoPlay -ButtonHandle $autoPlayHandle

$capturedOffsets = New-Object "System.Collections.Generic.Dictionary[int,object]"
$currentLookupIndex = 0
foreach ($requestedFrameId in $requestedFrameIds) {
    $currentLookupIndex++
    Write-Status "Looking up frame $currentLookupIndex/$($requestedFrameIds.Count): $requestedFrameId"

    Set-SpecifiedSequence `
        -EditHandle $specifiedSequenceHandle `
        -ConfirmHandle $confirmHandle `
        -ExpectedValue $requestedFrameId `
        -DelayMilliseconds $RefreshDelayMilliseconds

    $captured = Read-StableOffset `
        -SpecifiedSequenceElement $specifiedSequenceElement `
        -CurrentSequenceElement $currentSequenceElement `
        -OffsetXElement $offsetXElement `
        -OffsetYElement $offsetYElement `
        -ExpectedFrameId $requestedFrameId `
        -DelayMilliseconds $RefreshDelayMilliseconds

    $capturedOffsets.Add($requestedFrameId, [PSCustomObject]@{
        OffsetX = [int]$captured.OffsetX
        OffsetY = [int]$captured.OffsetY
    })
}

$existingOffsets = Read-OffsetYaml -Path $OffsetPath
$verifiedCount = Confirm-FrameOffsets `
    -ExistingOffsets $existingOffsets `
    -CapturedOffsets $capturedOffsets
$capturedRows = @(
    foreach ($capturedFrameId in @($capturedOffsets.Keys | Sort-Object)) {
        $offset = $capturedOffsets[$capturedFrameId]
        [PSCustomObject]@{
            FrameId = $capturedFrameId
            OffsetX = $offset.OffsetX
            OffsetY = $offset.OffsetY
        }
    }
)

$result = [PSCustomObject]@{
    RequestedCount = $requestedFrameIds.Count
    CapturedCount = $capturedOffsets.Count
    VerifiedCount = $verifiedCount
    MetadataPath = $OffsetPath
    CapturedOffsets = $capturedRows
}

Write-Status "Offset lookup complete. Requested: $($result.RequestedCount); captured: $($result.CapturedCount); verified: $($result.VerifiedCount); metadata: $OffsetPath"
$result | ConvertTo-Json -Depth 4
