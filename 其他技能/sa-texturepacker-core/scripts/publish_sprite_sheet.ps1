[CmdletBinding(DefaultParameterSetName = "Publish")]
param(
    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Publish")]
    [ValidateNotNullOrEmpty()]
    [string]$SourceDirectory,

    [Parameter(Mandatory = $true, ParameterSetName = "Publish")]
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory,

    [Parameter(ParameterSetName = "Publish")]
    [switch]$Overwrite,

    [Parameter(Mandatory = $true, ParameterSetName = "SelfTest")]
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$texturePackerGuiPath = "C:\Program Files\CodeAndWeb\TexturePacker\bin\TexturePackerGUI.exe"
$texturePackerProjectPath = "D:\src\github.com\sa.project\sa.desktop\TexturePacker.tps"
if (-not $SelfTest) {
    $OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
}
$supportedSpriteSuffixes = @(
    ".pvr.ccz",
    ".pvr.gz",
    ".astc",
    ".basis",
    ".bmp",
    ".dds",
    ".gif",
    ".ico",
    ".jpeg",
    ".jpg",
    ".ktx",
    ".ktx2",
    ".pbm",
    ".pgm",
    ".pkm",
    ".png",
    ".ppm",
    ".psd",
    ".pvr",
    ".pvrtc",
    ".svg",
    ".svgz",
    ".tga",
    ".tif",
    ".tiff",
    ".webp",
    ".xbm",
    ".xpm"
)
$addSpriteButtonPatterns = @(
    "(?i)^add sprites?$",
    "(?i)add.*sprite",
    "^添加精灵$",
    "添加.*精灵"
)
$deleteSpriteButtonPatterns = @(
    "(?i)^delete sprites?$",
    "(?i)delete.*sprite",
    "(?i)^remove sprites?$",
    "(?i)remove.*sprite",
    "^删除精灵$",
    "删除.*精灵"
)
$publishButtonPatterns = @(
    "(?i)^publish sprite sheet$",
    "(?i)publish.*sprite",
    "^发布精灵表$",
    "发布.*精灵"
)
$script:activeTexturePackerProcessId = 0

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$nativeSource = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Automation;

public sealed class TexturePackerAsyncInvoke
{
    private readonly ManualResetEvent done = new ManualResetEvent(false);

    public string Error { get; internal set; }

    internal void Complete()
    {
        done.Set();
    }

    public bool Wait(int milliseconds)
    {
        return done.WaitOne(milliseconds);
    }
}

public static class TexturePackerSingleWindowNative
{
    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumChildWindows(
        IntPtr parent,
        EnumWindowsProc callback,
        IntPtr lParam
    );

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(
        IntPtr hWnd,
        out uint processId
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
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern int GetDlgCtrlID(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool SetCursorPos(int x, int y);

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out Rect rectangle);

    [DllImport("user32.dll")]
    private static extern void mouse_event(
        uint flags,
        uint dx,
        uint dy,
        uint data,
        UIntPtr extraInfo
    );

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SendMessageTimeoutW")]
    private static extern IntPtr SendMessageTimeoutText(
        IntPtr hWnd,
        uint message,
        IntPtr wParam,
        string lParam,
        uint flags,
        uint timeout,
        out IntPtr result
    );

    [DllImport("user32.dll")]
    private static extern bool PostMessage(
        IntPtr hWnd,
        uint message,
        IntPtr wParam,
        IntPtr lParam
    );

    public static IntPtr[] FindVisibleWindowsByTitle(string expectedTitlePart)
    {
        var windows = new List<IntPtr>();
        EnumWindows((window, _) =>
        {
            if (!IsWindowVisible(window))
            {
                return true;
            }

            var text = new StringBuilder(1024);
            GetWindowText(window, text, text.Capacity);
            if (text.ToString().IndexOf(
                    expectedTitlePart,
                    StringComparison.OrdinalIgnoreCase
                ) >= 0)
            {
                windows.Add(window);
            }
            return true;
        }, IntPtr.Zero);
        return windows.ToArray();
    }

    public static int GetProcessId(IntPtr window)
    {
        uint processId;
        GetWindowThreadProcessId(window, out processId);
        return checked((int)processId);
    }

    public static IntPtr FindFileDialog(int processId)
    {
        var result = IntPtr.Zero;
        EnumWindows((window, _) =>
        {
            uint ownerProcessId;
            GetWindowThreadProcessId(window, out ownerProcessId);
            if (ownerProcessId != processId || !IsWindowVisible(window))
            {
                return true;
            }

            var className = new StringBuilder(256);
            GetClassName(window, className, className.Capacity);
            if (className.ToString() == "#32770" &&
                FindChild(window, 1148, "Edit") != IntPtr.Zero &&
                FindChild(window, 1, "Button") != IntPtr.Zero)
            {
                result = window;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return result;
    }

    public static IntPtr FindAnyDialog(int processId)
    {
        var result = IntPtr.Zero;
        EnumWindows((window, _) =>
        {
            uint ownerProcessId;
            GetWindowThreadProcessId(window, out ownerProcessId);
            if (ownerProcessId != processId || !IsWindowVisible(window))
            {
                return true;
            }

            var className = new StringBuilder(256);
            GetClassName(window, className, className.Capacity);
            if (className.ToString() == "#32770")
            {
                result = window;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return result;
    }

    public static void SubmitFiles(IntPtr dialog, string fileList)
    {
        var fileNameEdit = FindChild(dialog, 1148, "Edit");
        var openButton = FindChild(dialog, 1, "Button");
        if (fileNameEdit == IntPtr.Zero || openButton == IntPtr.Zero)
        {
            throw new InvalidOperationException(
                "The file dialog controls were not found."
            );
        }

        IntPtr result;
        const uint WM_SETTEXT = 0x000C;
        const uint BM_CLICK = 0x00F5;
        const uint SMTO_ABORTIFHUNG = 0x0002;
        if (SendMessageTimeoutText(
                fileNameEdit,
                WM_SETTEXT,
                IntPtr.Zero,
                fileList,
                SMTO_ABORTIFHUNG,
                5000,
                out result
            ) == IntPtr.Zero)
        {
            throw new InvalidOperationException(
                "Setting the file dialog names timed out."
            );
        }
        if (!PostMessage(openButton, BM_CLICK, IntPtr.Zero, IntPtr.Zero))
        {
            throw new InvalidOperationException(
                "Clicking the file dialog Open button failed."
            );
        }
    }

    public static void SetFileNameText(IntPtr dialog, string text)
    {
        var fileNameEdit = FindChild(dialog, 1148, "Edit");
        if (fileNameEdit == IntPtr.Zero)
        {
            throw new InvalidOperationException(
                "The file dialog name field was not found."
            );
        }

        IntPtr result;
        const uint WM_SETTEXT = 0x000C;
        const uint SMTO_ABORTIFHUNG = 0x0002;
        if (SendMessageTimeoutText(
                fileNameEdit,
                WM_SETTEXT,
                IntPtr.Zero,
                text,
                SMTO_ABORTIFHUNG,
                5000,
                out result
            ) == IntPtr.Zero)
        {
            throw new InvalidOperationException(
                "Clearing the file dialog name field timed out."
            );
        }
    }

    public static void ClickOpenButton(IntPtr dialog)
    {
        var openButton = FindChild(dialog, 1, "Button");
        if (openButton == IntPtr.Zero)
        {
            throw new InvalidOperationException(
                "The file dialog Open button was not found."
            );
        }

        const uint BM_CLICK = 0x00F5;
        if (!PostMessage(openButton, BM_CLICK, IntPtr.Zero, IntPtr.Zero))
        {
            throw new InvalidOperationException(
                "Clicking the file dialog Open button failed."
            );
        }
    }

    public static void ClickCancelButton(IntPtr dialog)
    {
        var cancelButton = FindChild(dialog, 2, "Button");
        if (cancelButton == IntPtr.Zero)
        {
            return;
        }

        const uint BM_CLICK = 0x00F5;
        PostMessage(cancelButton, BM_CLICK, IntPtr.Zero, IntPtr.Zero);
    }

    public static bool FocusFileList(IntPtr dialog)
    {
        var shellView = FindChildByClass(dialog, "SHELLDLL_DefView");
        if (shellView == IntPtr.Zero)
        {
            return false;
        }

        Rect rectangle;
        if (!GetWindowRect(shellView, out rectangle) ||
            rectangle.Right <= rectangle.Left ||
            rectangle.Bottom <= rectangle.Top)
        {
            return false;
        }

        SetForegroundWindow(dialog);
        ClickScreenPoint(
            rectangle.Left + (rectangle.Right - rectangle.Left) / 2,
            rectangle.Top + (rectangle.Bottom - rectangle.Top) / 2
        );
        return true;
    }

    public static void ClickScreenPoint(int x, int y)
    {
        const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
        const uint MOUSEEVENTF_LEFTUP = 0x0004;
        SetCursorPos(x, y);
        mouse_event(
            MOUSEEVENTF_LEFTDOWN,
            0,
            0,
            0,
            UIntPtr.Zero
        );
        mouse_event(
            MOUSEEVENTF_LEFTUP,
            0,
            0,
            0,
            UIntPtr.Zero
        );
    }

    public static TexturePackerAsyncInvoke InvokeButtonAsync(
        IntPtr window,
        string[] namePatterns
    )
    {
        var result = new TexturePackerAsyncInvoke();
        var thread = new Thread(() =>
        {
            try
            {
                var root = AutomationElement.FromHandle(window);
                var elements = root.FindAll(
                    TreeScope.Descendants,
                    Condition.TrueCondition
                );
                foreach (AutomationElement element in elements)
                {
                    if (element.Current.ControlType != ControlType.Button)
                    {
                        continue;
                    }

                    var name = element.Current.Name ?? "";
                    var matched = false;
                    foreach (var pattern in namePatterns)
                    {
                        if (Regex.IsMatch(name, pattern))
                        {
                            matched = true;
                            break;
                        }
                    }
                    if (!matched)
                    {
                        continue;
                    }

                    var invoke = (InvokePattern)element.GetCurrentPattern(
                        InvokePattern.Pattern
                    );
                    invoke.Invoke();
                    return;
                }
                throw new InvalidOperationException(
                    "The requested TexturePacker button was not found."
                );
            }
            catch (Exception exception)
            {
                result.Error = exception.Message;
            }
            finally
            {
                result.Complete();
            }
        });
        thread.IsBackground = true;
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        return result;
    }

    private static IntPtr FindChild(
        IntPtr parent,
        int controlId,
        string expectedClass
    )
    {
        var result = IntPtr.Zero;
        EnumChildWindows(parent, (child, _) =>
        {
            if (GetDlgCtrlID(child) != controlId)
            {
                return true;
            }

            var className = new StringBuilder(256);
            GetClassName(child, className, className.Capacity);
            if (className.ToString() == expectedClass)
            {
                result = child;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return result;
    }

    private static IntPtr FindChildByClass(
        IntPtr parent,
        string expectedClass
    )
    {
        var result = IntPtr.Zero;
        EnumChildWindows(parent, (child, _) =>
        {
            var className = new StringBuilder(256);
            GetClassName(child, className, className.Capacity);
            if (className.ToString() == expectedClass)
            {
                result = child;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return result;
    }
}
"@
Add-Type -TypeDefinition $nativeSource -ReferencedAssemblies @(
    "UIAutomationClient",
    "UIAutomationTypes"
)

function Get-SupportedSpriteSuffix {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName
    )

    foreach ($suffix in $supportedSpriteSuffixes) {
        if ($FileName.EndsWith(
                $suffix,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
            return $suffix
        }
    }
    return $null
}

function Get-ExpectedSpriteName {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$SourceFile
    )

    $suffix = Get-SupportedSpriteSuffix -FileName $SourceFile.Name
    if ($null -eq $suffix) {
        throw "不支持的精灵文件: $($SourceFile.Name)"
    }
    return $SourceFile.Name.Substring(
        0,
        $SourceFile.Name.Length - $suffix.Length
    )
}

function Get-FileState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    $file = Get-Item -LiteralPath $Path -Force
    return [PSCustomObject]@{
        Length = $file.Length
        LastWriteTimeUtc = $file.LastWriteTimeUtc
    }
}

function Test-FileStateChanged {
    param(
        [AllowNull()]
        [object]$Before,

        [AllowNull()]
        [object]$After
    )

    if ($null -eq $After) {
        return $false
    }
    if ($null -eq $Before) {
        return $true
    }
    return (
        $Before.Length -ne $After.Length -or
        $Before.LastWriteTimeUtc -ne $After.LastWriteTimeUtc
    )
}

function Get-ProjectWindow {
    $projectFileName = [System.IO.Path]::GetFileName($texturePackerProjectPath)
    $windowHandles = @(
        [TexturePackerSingleWindowNative]::FindVisibleWindowsByTitle(
            $projectFileName
        )
    )
    $matchingWindows = @(
        $windowHandles |
            Where-Object {
                $processId = [TexturePackerSingleWindowNative]::GetProcessId($_)
                $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
                $null -ne $process -and
                    $process.ProcessName -eq "TexturePackerGUI"
            }
    )
    if ($matchingWindows.Count -eq 0) {
        throw (
            "没有找到已打开的 TexturePacker.tps 工作窗口. " +
            "请先用指定程序打开: $texturePackerProjectPath"
        )
    }
    if ($matchingWindows.Count -gt 1) {
        throw "找到多个 TexturePacker.tps 工作窗口, 请只保留一个."
    }

    $windowHandle = $matchingWindows[0]
    $processId = [TexturePackerSingleWindowNative]::GetProcessId($windowHandle)
    $process = Get-Process -Id $processId -ErrorAction Stop
    if (-not [string]::IsNullOrWhiteSpace($process.Path)) {
        $actualExecutablePath = [System.IO.Path]::GetFullPath($process.Path)
        $expectedExecutablePath = [System.IO.Path]::GetFullPath(
            $texturePackerGuiPath
        )
        if (-not $actualExecutablePath.Equals(
                $expectedExecutablePath,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
            throw "当前窗口不是指定的 TexturePacker GUI: $actualExecutablePath"
        }
    }

    return [PSCustomObject]@{
        Handle = $windowHandle
        Process = $process
    }
}

function Get-WindowElements {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$WindowHandle
    )

    $root = [System.Windows.Automation.AutomationElement]::FromHandle(
        $WindowHandle
    )
    $elements = New-Object System.Collections.Generic.List[object]
    $elements.Add($root)
    $descendants = $root.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition
    )
    foreach ($element in $descendants) {
        $elements.Add($element)
    }
    return $elements.ToArray()
}

function Get-SpriteTreeItems {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$WindowHandle
    )

    return @(
        Get-WindowElements -WindowHandle $WindowHandle |
            Where-Object {
                $_.Current.ControlType -eq
                    [System.Windows.Automation.ControlType]::TreeItem
            }
    )
}

function Find-Button {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$WindowHandle,

        [Parameter(Mandatory = $true)]
        [string[]]$NamePatterns
    )

    foreach ($element in (Get-WindowElements -WindowHandle $WindowHandle)) {
        if ($element.Current.ControlType -ne
            [System.Windows.Automation.ControlType]::Button) {
            continue
        }
        foreach ($pattern in $NamePatterns) {
            if ($element.Current.Name -match $pattern) {
                return $element
            }
        }
    }
    return $null
}

function Wait-ButtonEnabled {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$WindowHandle,

        [Parameter(Mandatory = $true)]
        [string[]]$NamePatterns,

        [ValidateRange(1, 120)]
        [int]$TimeoutSeconds = 60
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $button = Find-Button `
            -WindowHandle $WindowHandle `
            -NamePatterns $NamePatterns
        if ($null -ne $button -and $button.Current.IsEnabled) {
            return
        }
        Start-Sleep -Milliseconds 250
    }
    throw "TexturePacker 按钮在 $TimeoutSeconds 秒内没有变为可用状态."
}

function Remove-AllSprites {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$WindowHandle,

        [Parameter(Mandatory = $true)]
        [int]$ProcessId
    )

    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $treeItems = @(Get-SpriteTreeItems -WindowHandle $WindowHandle)
        }
        catch {
            Start-Sleep -Milliseconds 250
            continue
        }
        if ($treeItems.Count -eq 0) {
            return
        }

        $dialog = [TexturePackerSingleWindowNative]::FindAnyDialog($ProcessId)
        if ($dialog -ne [IntPtr]::Zero) {
            throw "清空精灵列表前发现对话框, 已停止以避免键盘输入作用于错误窗口."
        }

        [void][TexturePackerSingleWindowNative]::SetForegroundWindow($WindowHandle)
        Start-Sleep -Milliseconds 300

        $treeItems = @(Get-SpriteTreeItems -WindowHandle $WindowHandle)
        if ($treeItems.Count -eq 0) {
            return
        }

        $itemBounds = $treeItems[0].Current.BoundingRectangle
        if ($itemBounds.Width -le 30 -or $itemBounds.Height -le 0) {
            throw "左侧精灵项没有可点击区域."
        }
        [TexturePackerSingleWindowNative]::ClickScreenPoint(
            [int]($itemBounds.Left + 30),
            [int]($itemBounds.Top + $itemBounds.Height / 2)
        )
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.SendKeys]::SendWait("^a")
        Start-Sleep -Milliseconds 300

        # 删除必须通过 TexturePacker 自身按钮完成, 禁止向当前焦点发送全局 Delete.
        Wait-ButtonEnabled `
            -WindowHandle $WindowHandle `
            -NamePatterns $deleteSpriteButtonPatterns `
            -TimeoutSeconds 5
        $deleteInvoke = [TexturePackerSingleWindowNative]::InvokeButtonAsync(
            $WindowHandle,
            $deleteSpriteButtonPatterns
        )
        if (-not $deleteInvoke.Wait(30000)) {
            throw "TexturePacker 删除精灵操作没有正常结束."
        }
        if (-not [string]::IsNullOrWhiteSpace($deleteInvoke.Error)) {
            throw "TexturePacker 删除精灵失败: $($deleteInvoke.Error)"
        }
        Start-Sleep -Milliseconds 500

        $dialog = [TexturePackerSingleWindowNative]::FindAnyDialog($ProcessId)
        if ($dialog -ne [IntPtr]::Zero) {
            throw "清空精灵列表时出现确认对话框, 已停止且未代替用户确认."
        }
    }
    throw "左侧精灵列表没有在 120 秒内清空."
}

function Add-Sprites {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$WindowHandle,

        [Parameter(Mandatory = $true)]
        [int]$ProcessId,

        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo[]]$SourceFiles
    )

    Wait-ButtonEnabled `
        -WindowHandle $WindowHandle `
        -NamePatterns $addSpriteButtonPatterns `
        -TimeoutSeconds 15
    $invoke = [TexturePackerSingleWindowNative]::InvokeButtonAsync(
        $WindowHandle,
        $addSpriteButtonPatterns
    )

    $dialog = [IntPtr]::Zero
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while ([DateTime]::UtcNow -lt $deadline) {
        $dialog = [TexturePackerSingleWindowNative]::FindFileDialog($ProcessId)
        if ($dialog -ne [IntPtr]::Zero) {
            break
        }
        if ($invoke.Wait(0)) {
            if (-not [string]::IsNullOrWhiteSpace($invoke.Error)) {
                throw "打开添加精灵对话框失败: $($invoke.Error)"
            }
            throw "添加精灵按钮没有打开文件选择对话框."
        }
        Start-Sleep -Milliseconds 100
    }
    if ($dialog -eq [IntPtr]::Zero) {
        throw "添加精灵文件选择对话框在 15 秒内没有出现."
    }

    [TexturePackerSingleWindowNative]::SubmitFiles(
        $dialog,
        $SourceFiles[0].Directory.FullName
    )
    Start-Sleep -Seconds 3
    $dialog = [TexturePackerSingleWindowNative]::FindFileDialog($ProcessId)
    if ($dialog -eq [IntPtr]::Zero) {
        throw "添加精灵文件选择对话框没有进入源文件夹."
    }
    [TexturePackerSingleWindowNative]::SetFileNameText($dialog, "")

    $fileListFocused = $false
    $focusDeadline = [DateTime]::UtcNow.AddSeconds(15)
    while ([DateTime]::UtcNow -lt $focusDeadline) {
        $dialog = [TexturePackerSingleWindowNative]::FindFileDialog($ProcessId)
        if ($dialog -ne [IntPtr]::Zero -and
            [TexturePackerSingleWindowNative]::FocusFileList($dialog)) {
            $fileListFocused = $true
            break
        }
        Start-Sleep -Milliseconds 200
    }
    if (-not $fileListFocused) {
        throw "无法聚焦添加精灵文件列表."
    }

    [System.Windows.Forms.SendKeys]::SendWait("^a")
    Start-Sleep -Milliseconds 200
    [TexturePackerSingleWindowNative]::ClickOpenButton($dialog)

    if (-not $invoke.Wait(30000)) {
        throw "添加精灵文件选择对话框在 30 秒内没有完成."
    }
    if (-not [string]::IsNullOrWhiteSpace($invoke.Error)) {
        throw "添加精灵失败: $($invoke.Error)"
    }

    $loadDeadline = [DateTime]::UtcNow.AddSeconds(60)
    while ([DateTime]::UtcNow -lt $loadDeadline) {
        try {
            $treeItems = @(Get-SpriteTreeItems -WindowHandle $WindowHandle)
        }
        catch {
            Start-Sleep -Milliseconds 250
            continue
        }
        if ($treeItems.Count -gt 0) {
            return
        }
        Start-Sleep -Milliseconds 250
    }
    throw "添加精灵后左侧列表仍为空."
}

function Get-ElementValue {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Automation.AutomationElement]$Element
    )

    try {
        $pattern = $Element.GetCurrentPattern(
            [System.Windows.Automation.ValuePattern]::Pattern
        )
        return $pattern.Current.Value
    }
    catch {
        return $null
    }
}

function Set-OutputDataFile {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$WindowHandle,

        [Parameter(Mandatory = $true)]
        [string]$DataFilePath
    )

    $candidateEdits = @(
        Get-WindowElements -WindowHandle $WindowHandle |
            Where-Object {
                if ($_.Current.ControlType -ne
                    [System.Windows.Automation.ControlType]::Edit) {
                    return $false
                }
                $value = Get-ElementValue -Element $_
                return (
                    $null -ne $value -and
                    $value -match "(?i)\.tpsheet$"
                )
            }
    )
    if ($candidateEdits.Count -ne 1) {
        throw (
            "无法唯一识别 TexturePacker 的数据文件输入框, 实际匹配 {0} 个." -f
            $candidateEdits.Count
        )
    }

    $valuePattern = $candidateEdits[0].GetCurrentPattern(
        [System.Windows.Automation.ValuePattern]::Pattern
    )
    $valuePattern.SetValue($DataFilePath)
    Start-Sleep -Milliseconds 300
    $actualValue = Get-ElementValue -Element $candidateEdits[0]
    if ($null -eq $actualValue -or
        -not $actualValue.EndsWith(
            [System.IO.Path]::GetFileName($DataFilePath),
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        throw "TexturePacker 数据文件名设置失败: $actualValue"
    }
}

function Confirm-OverwriteDialog {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$DialogHandle
    )

    $dialog = [System.Windows.Automation.AutomationElement]::FromHandle(
        $DialogHandle
    )
    $elements = $dialog.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition
    )
    $dialogText = @(
        $elements |
            ForEach-Object { $_.Current.Name } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    ) -join " "
    if ($dialogText -notmatch "(?i)overwrite|replace|覆盖|替换") {
        throw "发布时出现非覆盖确认对话框, 已停止: $dialogText"
    }

    foreach ($element in $elements) {
        if ($element.Current.ControlType -ne
            [System.Windows.Automation.ControlType]::Button) {
            continue
        }
        if ($element.Current.Name -match
            "(?i)^(yes|replace|overwrite)|^(是|覆盖|替换)") {
            $invoke = $element.GetCurrentPattern(
                [System.Windows.Automation.InvokePattern]::Pattern
            )
            $invoke.Invoke()
            return
        }
    }
    throw "覆盖确认对话框中没有找到确认按钮."
}

function Get-DialogText {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$DialogHandle
    )

    $dialog = [System.Windows.Automation.AutomationElement]::FromHandle(
        $DialogHandle
    )
    $elements = $dialog.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition
    )
    return @(
        $elements |
            ForEach-Object { $_.Current.Name } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    ) -join " "
}

function Close-PublishResultDialog {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$DialogHandle
    )

    try {
        $dialog = [System.Windows.Automation.AutomationElement]::FromHandle(
            $DialogHandle
        )
        $elements = $dialog.FindAll(
            [System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition
        )
        foreach ($element in $elements) {
            if ($element.Current.ControlType -ne
                [System.Windows.Automation.ControlType]::Button) {
                continue
            }
            if ($element.Current.Name -match
                "(?i)^(ok|close)|^(确定|关闭)") {
                $invoke = $element.GetCurrentPattern(
                    [System.Windows.Automation.InvokePattern]::Pattern
                )
                $invoke.Invoke()
                return $true
            }
        }
    }
    catch {
        return $false
    }
    return $false
}

function Test-PublishedOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataFilePath,

        [Parameter(Mandatory = $true)]
        [string]$TextureFilePath,

        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo[]]$SourceFiles
    )

    $dataFile = Get-Item -LiteralPath $DataFilePath -Force
    $textureFile = Get-Item -LiteralPath $TextureFilePath -Force
    if ($dataFile.Length -eq 0 -or $textureFile.Length -eq 0) {
        throw "发布结果包含空文件."
    }

    try {
        $sheet = Get-Content -LiteralPath $DataFilePath -Raw -Encoding UTF8 |
            ConvertFrom-Json
    }
    catch {
        throw "发布的 .tpsheet 不是有效 JSON: $($_.Exception.Message)"
    }
    if (@($sheet.textures).Count -ne 1) {
        throw "发布的 .tpsheet 必须只包含一个纹理."
    }
    if ([System.IO.Path]::GetFileName($sheet.textures[0].image) -ne
        [System.IO.Path]::GetFileName($TextureFilePath)) {
        throw "发布的 .tpsheet 没有引用对应 PNG."
    }

    $expectedNames = @(
        $SourceFiles |
            ForEach-Object { Get-ExpectedSpriteName -SourceFile $_ } |
            Sort-Object
    )
    $actualNames = @(
        $sheet.textures[0].sprites |
            ForEach-Object { $_.filename } |
            Sort-Object
    )
    if ($actualNames.Count -ne $expectedNames.Count) {
        throw (
            "输出精灵数不匹配: 预期 {0}, 实际 {1}." -f
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
        throw "输出精灵名称与源文件不一致."
    }
}

function Invoke-SelfTest {
    # This mode tests pure file validation without querying or operating any GUI window.
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sa-texturepacker-core-test-" + [Guid]::NewGuid().ToString("N"))
    try {
        [void](New-Item -ItemType Directory -Path $testRoot)
        $sourcePath = Join-Path $testRoot "101.PNG"
        $compressedPath = Join-Path $testRoot "202.pvr.ccz"
        [System.IO.File]::WriteAllBytes($sourcePath, [byte[]]@(1))
        [System.IO.File]::WriteAllBytes($compressedPath, [byte[]]@(2))
        $sourceFiles = @((Get-Item -LiteralPath $sourcePath), (Get-Item -LiteralPath $compressedPath))
        if ((Get-ExpectedSpriteName $sourceFiles[0]) -cne "101" -or
            (Get-ExpectedSpriteName $sourceFiles[1]) -cne "202" -or
            $null -ne (Get-SupportedSpriteSuffix "notes.txt")) {
            throw "Sprite filename validation self-test failed."
        }
        $dataPath = Join-Path $testRoot "atlas.tpsheet"
        $texturePath = Join-Path $testRoot "atlas.png"
        [System.IO.File]::WriteAllBytes($texturePath, [byte[]]@(3))
        $validSheet = '{"textures":[{"image":"atlas.png","sprites":[{"filename":"101"},{"filename":"202"}]}]}'
        [System.IO.File]::WriteAllText($dataPath, $validSheet)
        Test-PublishedOutput -DataFilePath $dataPath -TextureFilePath $texturePath -SourceFiles $sourceFiles
        foreach ($candidate in @(
            "",
            "{",
            $validSheet.Replace("atlas.png", "wrong.png"),
            $validSheet.Replace('"202"', '"303"'),
            '{"textures":[{"image":"atlas.png","sprites":[{"filename":"101"}]}]}'
        )) {
            [System.IO.File]::WriteAllText($dataPath, $candidate)
            $rejected = $false
            try {
                Test-PublishedOutput -DataFilePath $dataPath -TextureFilePath $texturePath -SourceFiles $sourceFiles
            }
            catch {
                $rejected = $true
            }
            if (-not $rejected) {
                throw "Invalid published output was accepted."
            }
        }
        # Same-directory callers must prepare old outputs before the GUI's select-all import.
        $SourceDirectory = Join-Path $testRoot "atlas"
        $OutputDirectory = $SourceDirectory
        $texturePackerGuiPath = $sourcePath
        $texturePackerProjectPath = $sourcePath
        [void](New-Item -ItemType Directory -Path $SourceDirectory)
        Copy-Item -LiteralPath $sourcePath -Destination $SourceDirectory
        Copy-Item -LiteralPath $texturePath -Destination $SourceDirectory
        function Get-ProjectWindow { throw "Self-test forbids GUI access." }
        $rejected = $false
        try {
            Invoke-Publish
        }
        catch {
            if ($_.Exception.Message -notlike "同目录发布前必须由调用者备份并移出旧输出*") { throw }
            $rejected = $true
        }
        if (-not $rejected) { throw "In-source old output was accepted." }
        if (-not (Test-FileStateChanged -Before $null -After ([PSCustomObject]@{ Length = 1; LastWriteTimeUtc = [DateTime]::UtcNow }))) {
            throw "New output detection self-test failed."
        }
        Write-Host "TexturePacker core self-test passed without GUI access." -ForegroundColor Green
    }
    finally {
        if (Test-Path -LiteralPath $testRoot -PathType Container) {
            $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
            $expectedParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
            if ([System.IO.Path]::GetDirectoryName($resolvedTestRoot).TrimEnd('\') -ne $expectedParent -or
                [System.IO.Path]::GetFileName($resolvedTestRoot) -notlike "sa-texturepacker-core-test-*") {
                throw "Refusing to remove unexpected self-test directory."
            }
            Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
        }
    }
}

function Invoke-Publish {
    if (-not (Test-Path -LiteralPath $texturePackerGuiPath -PathType Leaf)) {
        throw "找不到指定 TexturePacker GUI: $texturePackerGuiPath"
    }
    if (-not (Test-Path -LiteralPath $texturePackerProjectPath -PathType Leaf)) {
        throw "找不到固定 TexturePacker 工程: $texturePackerProjectPath"
    }
    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        throw "输出目录不存在: $OutputDirectory"
    }
    if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
        throw "精灵源文件夹不存在: $SourceDirectory"
    }

    $sourceDirectoryInfo = Get-Item -LiteralPath $SourceDirectory -Force
    $spriteName = $sourceDirectoryInfo.Name
    if ([string]::IsNullOrWhiteSpace($spriteName) -or
        $spriteName.IndexOfAny(
            [System.IO.Path]::GetInvalidFileNameChars()
        ) -ge 0) {
        throw "源文件夹名称不能作为精灵名称: $spriteName"
    }

    $dataFilePath = Join-Path $OutputDirectory ($spriteName + ".tpsheet")
    $textureFilePath = Join-Path $OutputDirectory ($spriteName + ".png")
    $excludedSourcePaths = New-Object System.Collections.Generic.HashSet[string](
        [System.StringComparer]::OrdinalIgnoreCase
    )
    [void]$excludedSourcePaths.Add([System.IO.Path]::GetFullPath($dataFilePath))
    [void]$excludedSourcePaths.Add([System.IO.Path]::GetFullPath($textureFilePath))
    $sourceFiles = @(
        Get-ChildItem -LiteralPath $sourceDirectoryInfo.FullName -Force |
            Where-Object {
                -not $_.PSIsContainer -and
                -not $excludedSourcePaths.Contains($_.FullName)
            } |
            Sort-Object -Property FullName
    )
    if ($sourceFiles.Count -eq 0) {
        throw "精灵源文件夹内没有可导入的普通文件."
    }
    $unsupportedFiles = @(
        $sourceFiles |
            Where-Object {
                $null -eq (Get-SupportedSpriteSuffix -FileName $_.Name)
            }
    )
    if ($unsupportedFiles.Count -gt 0) {
        throw (
            "源文件夹包含不支持的文件: {0}" -f
            (($unsupportedFiles | ForEach-Object { $_.Name }) -join ", ")
        )
    }
    $duplicateNames = @(
        $sourceFiles |
            ForEach-Object { Get-ExpectedSpriteName -SourceFile $_ } |
            Group-Object |
            Where-Object { $_.Count -gt 1 } |
            ForEach-Object { $_.Name }
    )
    if ($duplicateNames.Count -gt 0) {
        throw "源文件产生重复精灵名称: $($duplicateNames -join ", ")"
    }

    $existingOutputs = @(
        @($dataFilePath, $textureFilePath) |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
    )
    # The GUI imports all visible files; callers must move old in-source outputs aside first.
    if ($existingOutputs.Count -gt 0 -and
        [System.IO.Path]::GetFullPath($sourceDirectoryInfo.FullName).TrimEnd('\') -eq $OutputDirectory.TrimEnd('\')) {
        throw "同目录发布前必须由调用者备份并移出旧输出, 避免 GUI 将图集重新导入为源帧."
    }
    if ($existingOutputs.Count -gt 0 -and -not $Overwrite) {
        throw (
            "输出已存在, 用户确认覆盖后才能使用 -Overwrite: {0}" -f
            ($existingOutputs -join ", ")
        )
    }

    $projectWindow = Get-ProjectWindow
    $processId = $projectWindow.Process.Id
    $script:activeTexturePackerProcessId = $processId
    $existingFileDialog = [TexturePackerSingleWindowNative]::FindFileDialog(
        $processId
    )
    if ($existingFileDialog -ne [IntPtr]::Zero) {
        [TexturePackerSingleWindowNative]::ClickCancelButton($existingFileDialog)
        Start-Sleep -Milliseconds 300
    }
    $existingDialog = [TexturePackerSingleWindowNative]::FindAnyDialog($processId)
    if ($existingDialog -ne [IntPtr]::Zero -and
        -not (Close-PublishResultDialog -DialogHandle $existingDialog)) {
        throw "TexturePacker 存在无法安全关闭的对话框."
    }
    Write-Output ("SPRITE_NAME={0}" -f $spriteName)
    Write-Output ("SOURCE_FILE_COUNT={0}" -f $sourceFiles.Count)
    Write-Output ("GUI_PROCESS_ID={0}" -f $processId)

    Remove-AllSprites `
        -WindowHandle $projectWindow.Handle `
        -ProcessId $processId
    Add-Sprites `
        -WindowHandle $projectWindow.Handle `
        -ProcessId $processId `
        -SourceFiles $sourceFiles
    Set-OutputDataFile `
        -WindowHandle $projectWindow.Handle `
        -DataFilePath $dataFilePath
    Wait-ButtonEnabled `
        -WindowHandle $projectWindow.Handle `
        -NamePatterns $publishButtonPatterns `
        -TimeoutSeconds 60
    # TexturePacker 会在批量导入完成前提前启用发布按钮, 需要等待后台排版和预览稳定.
    Start-Sleep -Seconds 5
    Wait-ButtonEnabled `
        -WindowHandle $projectWindow.Handle `
        -NamePatterns $publishButtonPatterns `
        -TimeoutSeconds 60

    $dataStateBefore = Get-FileState -Path $dataFilePath
    $textureStateBefore = Get-FileState -Path $textureFilePath
    $publishInvoke = [TexturePackerSingleWindowNative]::InvokeButtonAsync(
        $projectWindow.Handle,
        $publishButtonPatterns
    )

    $overwriteConfirmed = $false
    $unchangedOutputAccepted = $false
    $publishDeadline = [DateTime]::UtcNow.AddSeconds(120)
    while ([DateTime]::UtcNow -lt $publishDeadline) {
        $dialog = [TexturePackerSingleWindowNative]::FindAnyDialog($processId)
        if ($dialog -ne [IntPtr]::Zero) {
            $dialogText = Get-DialogText -DialogHandle $dialog
            if ($dialogText -match "(?i)结果图像为空|result image is empty") {
                [void](Close-PublishResultDialog -DialogHandle $dialog)
                throw "TexturePacker 发布失败: 结果图像为空."
            }
            if (Close-PublishResultDialog -DialogHandle $dialog) {
                Start-Sleep -Milliseconds 100
            }
            elseif ($Overwrite -and -not $overwriteConfirmed) {
                Confirm-OverwriteDialog -DialogHandle $dialog
                $overwriteConfirmed = $true
            }
            else {
                throw "发布时出现无法安全关闭的对话框."
            }
        }

        $dataStateAfter = Get-FileState -Path $dataFilePath
        $textureStateAfter = Get-FileState -Path $textureFilePath
        $outputChanged =
            (Test-FileStateChanged $dataStateBefore $dataStateAfter) -and
            (Test-FileStateChanged $textureStateBefore $textureStateAfter)
        $outputReady =
            $null -ne $dataStateAfter -and
            $null -ne $textureStateAfter -and
            $dataStateAfter.Length -gt 0 -and
            $textureStateAfter.Length -gt 0
        if ($outputReady -and $publishInvoke.Wait(0)) {
            if ($outputChanged) {
                break
            }
            if ($Overwrite) {
                try {
                    Test-PublishedOutput `
                        -DataFilePath $dataFilePath `
                        -TextureFilePath $textureFilePath `
                        -SourceFiles $sourceFiles
                    $unchangedOutputAccepted = $true
                    break
                }
                catch {
                    # 当前输出与本次输入不一致时继续等待 TexturePacker 写入, 不接受旧文件.
                }
            }
        }
        if ($publishInvoke.Wait(0) -and
            -not [string]::IsNullOrWhiteSpace($publishInvoke.Error)) {
            throw "发布精灵表失败: $($publishInvoke.Error)"
        }
        Start-Sleep -Milliseconds 250
    }

    $dataStateAfter = Get-FileState -Path $dataFilePath
    $textureStateAfter = Get-FileState -Path $textureFilePath
    if ((-not (Test-FileStateChanged $dataStateBefore $dataStateAfter) -or
        -not (Test-FileStateChanged $textureStateBefore $textureStateAfter)) -and
        -not $unchangedOutputAccepted) {
        throw "TexturePacker 没有在 120 秒内生成两个输出文件."
    }
    if (-not $publishInvoke.Wait(30000)) {
        throw "TexturePacker 发布操作没有正常结束."
    }
    if (-not [string]::IsNullOrWhiteSpace($publishInvoke.Error)) {
        throw "发布精灵表失败: $($publishInvoke.Error)"
    }

    $outputValidated = $false
    $validationError = $null
    $validationDeadline = [DateTime]::UtcNow.AddSeconds(120)
    while ([DateTime]::UtcNow -lt $validationDeadline) {
        try {
            Test-PublishedOutput `
                -DataFilePath $dataFilePath `
                -TextureFilePath $textureFilePath `
                -SourceFiles $sourceFiles
            $outputValidated = $true
            break
        }
        catch {
            $validationError = $_.Exception.Message
            Start-Sleep -Milliseconds 500
        }
    }
    if (-not $outputValidated) {
        throw "发布结果验证失败: $validationError"
    }
    Remove-AllSprites `
        -WindowHandle $projectWindow.Handle `
        -ProcessId $processId

    Write-Output ("OUTPUT_FILE={0}" -f $dataFilePath)
    Write-Output ("OUTPUT_FILE={0}" -f $textureFilePath)
    Write-Output "OUTPUT_FILE_COUNT=2"
    Write-Host "TexturePacker 精灵表发布成功, 左侧精灵列表已清空." -ForegroundColor Green
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
    if ($script:activeTexturePackerProcessId -gt 0) {
        $fileDialog = [TexturePackerSingleWindowNative]::FindFileDialog(
            $script:activeTexturePackerProcessId
        )
        if ($fileDialog -ne [IntPtr]::Zero) {
            [TexturePackerSingleWindowNative]::ClickCancelButton($fileDialog)
        }
        $resultDialog = [TexturePackerSingleWindowNative]::FindAnyDialog(
            $script:activeTexturePackerProcessId
        )
        if ($resultDialog -ne [IntPtr]::Zero) {
            [void](Close-PublishResultDialog -DialogHandle $resultDialog)
        }
    }
    Write-Host ("TexturePacker 精灵表发布失败: {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}
