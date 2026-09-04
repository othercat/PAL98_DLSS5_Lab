[CmdletBinding()]
param(
    [ValidateRange(320, 7680)]
    [int]$ClientWidth = 640,

    [ValidateRange(200, 4320)]
    [int]$ClientHeight = 400
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$labRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$packageRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $labRoot))
$palExe = Join-Path $packageRoot 'PAL.EXE'
$logPath = Join-Path $labRoot 'window-helper.log'

function Write-WindowLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    $line = ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
    Write-Host $line
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $palExe -PathType Leaf)) {
    throw "PAL.EXE is missing: $palExe"
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class PalLabWindow
{
    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct MONITORINFO
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }

    private const uint MONITOR_DEFAULTTONEAREST = 2;
    private const int GWL_STYLE = -16;
    private const int WS_POPUP = unchecked((int)0x80000000);
    private const int WS_CAPTION = 0x00C00000;
    private const int WS_SYSMENU = 0x00080000;
    private const int WS_THICKFRAME = 0x00040000;
    private const int WS_MINIMIZEBOX = 0x00020000;
    private const int WS_MAXIMIZEBOX = 0x00010000;
    private const uint SWP_NOSIZE = 0x0001;
    private const uint SWP_NOMOVE = 0x0002;
    private const uint SWP_NOZORDER = 0x0004;
    private const uint SWP_NOACTIVATE = 0x0010;
    private const uint SWP_FRAMECHANGED = 0x0020;

    [DllImport("user32.dll", EntryPoint = "GetWindowLongW", SetLastError = true)]
    private static extern int GetWindowLong(IntPtr hWnd, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongW", SetLastError = true)]
    private static extern int SetWindowLong(IntPtr hWnd, int index, int value);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetClientRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(
        IntPtr hWnd,
        IntPtr insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags);

    // Returns 1 when the style or size changed, 0 when already correct, and a negative value on failure.
    public static int EnsureClientSize(IntPtr hWnd, int targetWidth, int targetHeight)
    {
        if (hWnd == IntPtr.Zero)
            return -1;

        bool changed = false;
        int style = GetWindowLong(hWnd, GWL_STYLE);
        int windowedStyle = (style & ~WS_POPUP & ~WS_THICKFRAME & ~WS_MAXIMIZEBOX) |
                            WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX;
        if (windowedStyle != style)
        {
            SetWindowLong(hWnd, GWL_STYLE, windowedStyle);
            if (!SetWindowPos(
                hWnd,
                IntPtr.Zero,
                0,
                0,
                0,
                0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED))
                return -3;
            changed = true;
        }

        RECT client;
        RECT window;
        if (!GetClientRect(hWnd, out client) || !GetWindowRect(hWnd, out window))
            return -1;

        int clientWidth = client.Right - client.Left;
        int clientHeight = client.Bottom - client.Top;
        if (clientWidth == targetWidth && clientHeight == targetHeight)
            return changed ? 1 : 0;

        int frameWidth = Math.Max(0, (window.Right - window.Left) - clientWidth);
        int frameHeight = Math.Max(0, (window.Bottom - window.Top) - clientHeight);
        int outerWidth = targetWidth + frameWidth;
        int outerHeight = targetHeight + frameHeight;
        int x = window.Left;
        int y = window.Top;

        IntPtr monitor = MonitorFromWindow(hWnd, MONITOR_DEFAULTTONEAREST);
        MONITORINFO monitorInfo = new MONITORINFO();
        monitorInfo.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
        if (monitor != IntPtr.Zero && GetMonitorInfo(monitor, ref monitorInfo))
        {
            int workWidth = monitorInfo.rcWork.Right - monitorInfo.rcWork.Left;
            int workHeight = monitorInfo.rcWork.Bottom - monitorInfo.rcWork.Top;
            x = monitorInfo.rcWork.Left + Math.Max(0, (workWidth - outerWidth) / 2);
            y = monitorInfo.rcWork.Top + Math.Max(0, (workHeight - outerHeight) / 2);
        }

        return SetWindowPos(
            hWnd,
            IntPtr.Zero,
            x,
            y,
            outerWidth,
            outerHeight,
            SWP_NOZORDER | SWP_NOACTIVATE) ? 1 : -2;
    }
}
'@

$matching = @(Get-CimInstance Win32_Process -Filter "Name='PAL.EXE'" -ErrorAction SilentlyContinue | Where-Object {
    try { ([System.IO.Path]::GetFullPath($_.ExecutablePath) -ieq $palExe) } catch { $false }
})

if ($matching.Count -gt 1) {
    throw 'More than one PAL.EXE from this package is running.'
}

if ($matching.Count -eq 1) {
    $process = Get-Process -Id $matching[0].ProcessId -ErrorAction Stop
    Write-WindowLog "Attached to PAL.EXE PID $($process.Id)."
}
else {
    $process = Start-Process -FilePath $palExe -WorkingDirectory $packageRoot -PassThru
    Write-WindowLog "Started PAL.EXE PID $($process.Id)."
}

Write-WindowLog "Enforcing a centered ${ClientWidth}x${ClientHeight} client area for this PAL.EXE only."
$resizeObserved = $false
$failureLogged = $false

while (-not $process.HasExited) {
    $process.Refresh()
    $windowHandle = [IntPtr]$process.MainWindowHandle
    if ($windowHandle -ne [IntPtr]::Zero) {
        $resizeResult = [PalLabWindow]::EnsureClientSize($windowHandle, $ClientWidth, $ClientHeight)
        if ($resizeResult -eq 1 -and -not $resizeObserved) {
            Write-WindowLog "Window resized successfully to ${ClientWidth}x${ClientHeight}."
            $resizeObserved = $true
        }
        elseif ($resizeResult -lt 0 -and -not $failureLogged) {
            Write-WindowLog "WARNING: SetWindowPos failed with helper result $resizeResult; monitoring continues."
            $failureLogged = $true
        }
    }
    Start-Sleep -Milliseconds 250
}

$process.WaitForExit()
Write-WindowLog "PAL.EXE exited with code $($process.ExitCode)."
exit $process.ExitCode
