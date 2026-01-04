function global:bcm {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('list', 'up', 'down', 'switch', 'show', 'run', 'stop', 'status', 'check', 'doctor', 'info', 'preview', 'build', 'help', 'version')]
        [string]$Command,

        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$Rest
    )

    # === 全局路径配置 ===
    if (-not $env:bcm_home) {
        Write-Host "❌ `$env:bcm_home is not set." -ForegroundColor Red
        Write-Host "💡 Set it to your BongoCatMver root folder (e.g., 'E:\BongoCatMver')" -ForegroundColor DarkGray
        return
    }

    $root = Resolve-Path $env:bcm_home -ErrorAction SilentlyContinue
    if (-not $root -or -not (Test-Path $root)) {
        Write-Host "❌ Invalid `$env:bcm_home: $($env:bcm_home)" -ForegroundColor Red
        return
    }

    $appDir      = Join-Path $root "BongoCatMver"
    $sourcesDir  = Join-Path $root "Sources"
    $recordFile  = Join-Path $appDir ".bcm-skin"

    # === 辅助函数 ===
    function Get-CurrentSkin {
        if (Test-Path $recordFile) {
            return (Get-Content $recordFile -Raw).Trim()
        }
        return $null
    }

    function Get-SkinFromLinks {
        $imgTarget = $null
        $configTarget = $null

        $imgPath = Join-Path $appDir "img"
        if (Test-Path $imgPath) {
            $item = Get-Item $imgPath -ErrorAction SilentlyContinue
            if ($item -and $item.Target) {
                $imgTarget = Split-Path $item.Target -Leaf
            }
        }

        $configPath = Join-Path $appDir "config.json"
        if (Test-Path $configPath) {
            $item = Get-Item $configPath -ErrorAction SilentlyContinue
            if ($item -and $item.Target) {
                $configTarget = Split-Path (Split-Path $item.Target -Parent) -Leaf
            }
        }

        if ($imgTarget -and $imgTarget -eq $configTarget) {
            return $imgTarget
        }
        return $null
    }

# === 内部函数：获取窗口信息（基于你提供的逻辑，去 global 化）===
function Get-BcmWindowInfo {
    param([int]$ProcessId)

    if (-not ('WindowUtils.WindowHelper' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace WindowUtils {
    public class WindowHelper {
        [DllImport("user32.dll")]
        public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr child, string className, string windowTitle);

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        public static RECT? GetWindowRectByProcessId(int pid) {
            IntPtr hwnd = IntPtr.Zero;
            while ((hwnd = FindWindowEx(IntPtr.Zero, hwnd, null, null)) != IntPtr.Zero) {
                uint processId;
                GetWindowThreadProcessId(hwnd, out processId);
                if (processId == pid && IsWindowVisible(hwnd)) {
                    RECT rect;
                    if (GetWindowRect(hwnd, out rect)) {
                        return rect;
                    }
                }
            }
            return null;
        }
    }
}
"@
    }

    $rect = [WindowUtils.WindowHelper]::GetWindowRectByProcessId($ProcessId)
    if ($rect) {
        $width  = $rect.Right - $rect.Left
        $height = $rect.Bottom - $rect.Top
        [PSCustomObject]@{
            PID    = $ProcessId
            Left   = $rect.Left
            Top    = $rect.Top
            Width  = $width
            Height = $height
        }
    }
}
    # === 主命令分发 ===
    switch ($Command) {
        'list' {
            if (-not (Test-Path $sourcesDir)) {
                Write-Host "❌ Sources directory not found: $sourcesDir" -ForegroundColor Red
                return
            }
            $skins = Get-ChildItem $sourcesDir -Directory | ForEach-Object {
                $name = $_.Name
                $hasImg = Test-Path (Join-Path $_.FullName "img") -PathType Container
                $hasConfig = Test-Path (Join-Path $_.FullName "config.json") -PathType Leaf
                if ($hasImg -and $hasConfig) {
                    "✅ $name"
                } else {
                    "⚠️ (incomplete) $name"
                }
            }
            if ($skins) {
                $skins
            } else {
                Write-Host "No skins found in Sources/" -ForegroundColor Gray
            }
        }

        'up' {
            if ($Rest.Count -eq 0) {
                Write-Host "❌ Usage: bcm up <skin>" -ForegroundColor Red
                return
            }
            $skinName = $Rest[0]
            $skinPath = Join-Path $sourcesDir $skinName
            if (-not (Test-Path $skinPath -PathType Container)) {
                Write-Host "❌ Skin '$skinName' not found in Sources/" -ForegroundColor Red
                return
            }

            $srcImg = Join-Path $skinPath "img"
            $srcConfig = Join-Path $skinPath "config.json"
            $dstImg = Join-Path $appDir "img"
            $dstConfig = Join-Path $appDir "config.json"

            if (-not (Test-Path $srcImg -PathType Container)) {
                Write-Host "❌ Missing 'img' folder in skin: $skinName" -ForegroundColor Red
                return
            }
            if (-not (Test-Path $srcConfig -PathType Leaf)) {
                Write-Host "❌ Missing 'config.json' in skin: $skinName" -ForegroundColor Red
                return
            }

            # Clean up existing
            if (Test-Path $dstImg) { Remove-Item $dstImg -Recurse -Force }
            if (Test-Path $dstConfig) { Remove-Item $dstConfig -Force }

            # Create links
            try {
                cmd /c mklink /j "$dstImg" "$srcImg" *>$null
                New-Item -ItemType SymbolicLink -Path $dstConfig -Target $srcConfig *>$null
                Set-Content $recordFile $skinName
                Write-Host "✅ Activated skin: $skinName" -ForegroundColor Green
            } catch {
                Write-Host "❌ Failed to create links. Run as Administrator or enable Developer Mode." -ForegroundColor Red
            }
        }

        'down' {
            $dstImg = Join-Path $appDir "img"
            $dstConfig = Join-Path $appDir "config.json"
            if (Test-Path $dstImg) { Remove-Item $dstImg -Recurse -Force }
            if (Test-Path $dstConfig) { Remove-Item $dstConfig -Force }
            if (Test-Path $recordFile) { Remove-Item $recordFile -Force }
            Write-Host "✅ Deactivated current skin." -ForegroundColor Green
        }

        'switch' {
            if ($Rest.Count -eq 0) {
                Write-Host "❌ Usage: bcm switch <skin>" -ForegroundColor Red
                return
            }
            & $MyInvocation.MyCommand.ScriptBlock -Command 'down' @{}
            & $MyInvocation.MyCommand.ScriptBlock -Command 'up' -Rest $Rest
        }

        'show' {
            $current = Get-CurrentSkin
            if ($current) {
                $current
            } else {
                Write-Host "<none>" -ForegroundColor Gray
            }
        }

        'run' {
            $launchScript = Join-Path $appDir "launch.ps1"
            if (-not (Test-Path $launchScript -PathType Leaf)) {
                Write-Host "❌ Launch script not found: launch.ps1" -ForegroundColor Red
                return
            }

            $imgPath    = Join-Path $appDir "img"
            $configPath = Join-Path $appDir "config.json"

            if (-not (Test-Path $imgPath -PathType Container) -or -not (Test-Path $configPath -PathType Leaf)) {
                Write-Host "⚠️  No skin configured. Please run 'bcm up <skin>' first." -ForegroundColor Yellow
                return
            }

            $current = Get-CurrentSkin
            if ($current) {
                Write-Host "🚀 Launching with skin: $current" -ForegroundColor Green
            } else {
                Write-Host "🚀 Launching..." -ForegroundColor Green
            }

            & $launchScript
        }

        'stop' {
            $pidFile = Join-Path $appDir ".bcm-pid"

            if (-not (Test-Path $pidFile -PathType Leaf)) {
                Write-Host "ℹ️  .bcm-pid file not found. BongoCat Mver may not be running via 'bcm run'." -ForegroundColor Yellow
                return
            }

            $pidContent = (Get-Content $pidFile -Raw).Trim()

            # 校验 PID 格式
            if ($pidContent -notmatch '^\d+$') {
                Write-Host "❌ Invalid content in .bcm-pid: '$pidContent' (expected a number)" -ForegroundColor Red
                return
            }

            $targetPid = [int]$pidContent

            # 尝试获取进程
            $process = $null
            try {
                $process = Get-Process -Id $targetPid -ErrorAction Stop
            } catch {
                if ($_.Exception.Message -like "*not found*") {
                    Write-Host "✅ Process with PID ${targetPid} has already exited." -ForegroundColor Green
                    return
                } else {
                    Write-Host "⚠️  Failed to query process PID ${targetPid}: $_" -ForegroundColor Yellow
                    return
                }
            }

            # 验证进程名（标准化比较）
            $expectedName = "bongo cat mver"
            $actualName = $process.ProcessName.ToLower().Replace(' ', '')
            $expectedNorm = $expectedName.Replace(' ', '')

            if ($actualName -ne $expectedNorm) {
                Write-Host "⚠️  PID ${targetPid} belongs to '$($process.ProcessName)', not 'Bongo Cat Mver'." -ForegroundColor Yellow
                Write-Host "💡 Skipping termination for safety." -ForegroundColor DarkGray
                return
            }

            # 终止进程
            try {
                Stop-Process -Id $targetPid -Force
                Write-Host "🛑 Successfully stopped Bongo Cat Mver (PID: ${targetPid})" -ForegroundColor Green
            } catch {
                Write-Host "❌ Failed to stop process (PID: ${targetPid}): $_" -ForegroundColor Red
                Write-Host "💡 You may need to run as Administrator or close it manually." -ForegroundColor DarkGray
            }
        }

        'check' {
            $imgPath      = Join-Path $appDir "img"
            $configPath   = Join-Path $appDir "config.json"

            $recordedSkin = Get-CurrentSkin
            $recoveredSkin = Get-SkinFromLinks
            $activeSkin = if ($recordedSkin) { $recordedSkin } else { $recoveredSkin }

            $imgExists = Test-Path $imgPath -PathType Container
            $configExists = Test-Path $configPath -PathType Leaf

            if (-not $imgExists -and -not $configExists) {
                Write-Host "⚠️  No active skin." -ForegroundColor Yellow
                Write-Host "💡 Run 'bcm up <skin>' to activate one." -ForegroundColor DarkGray
                return
            }

            if ($activeSkin) {
                $skinValid = Test-Path (Join-Path $sourcesDir $activeSkin) -PathType Container
                Write-Host "Current skin: $activeSkin" -ForegroundColor Cyan
                if (-not $skinValid) {
                    Write-Host "❌ Skin not found in Sources/ (orphaned)" -ForegroundColor Red
                }
            } else {
                Write-Host "Current skin: unknown" -ForegroundColor Gray
            }

            # img
            if ($imgExists) {
                $item = Get-Item $imgPath -ErrorAction SilentlyContinue
                if ($item -and ($item.LinkType -eq "Junction" -or $item.LinkType -eq "SymbolicLink")) {
                    Write-Host "✅ img → valid junction/symlink" -ForegroundColor Green
                } else {
                    Write-Host "⚠️  img → exists but is a regular folder (not link)" -ForegroundColor Yellow
                }
            } else {
                Write-Host "❌ img → missing" -ForegroundColor Red
            }

            # config.json
            if ($configExists) {
                $item = Get-Item $configPath -ErrorAction SilentlyContinue
                if ($item -and $item.LinkType -eq "SymbolicLink") {
                    Write-Host "✅ config.json → valid symlink" -ForegroundColor Green
                } else {
                    Write-Host "⚠️  config.json → exists but is a regular file (not link)" -ForegroundColor Yellow
                }
            } else {
                Write-Host "❌ config.json → missing" -ForegroundColor Red
            }

            # Health summary
            $imgOk = $imgExists -and (Get-Item $imgPath -ErrorAction SilentlyContinue).LinkType -ne $null
            $configOk = $configExists -and (Get-Item $configPath -ErrorAction SilentlyContinue).LinkType -eq "SymbolicLink"
            $skinValid = if ($activeSkin) { Test-Path (Join-Path $sourcesDir $activeSkin) } else { $false }

            if ($imgOk -and $configOk -and $skinValid) {
                Write-Host "✨ Skin is fully healthy." -ForegroundColor Green
            } elseif ($imgExists -and $configExists) {
                Write-Host "🔧 Skin files exist, but links may be broken. Consider reactivating." -ForegroundColor DarkYellow
                Write-Host "💡 Run 'bcm down' then 'bcm up $activeSkin' to repair." -ForegroundColor DarkGray
            } else {
                Write-Host "💥 Skin is broken. Activation required." -ForegroundColor Red
                Write-Host "💡 Run 'bcm up <skin>' to fix." -ForegroundColor DarkGray
            }
        }

        'doctor' {
            Write-Host "🔍 BongoCat Mver Environment Check" -ForegroundColor Cyan

            Write-Host "✅ `$env:bcm_home = $env:bcm_home"

            if (-not (Test-Path $appDir -PathType Container)) {
                Write-Host "❌ Missing application directory: $appDir" -ForegroundColor Red
                return
            }
            Write-Host "✅ Application directory: $appDir"

            if (-not (Test-Path $sourcesDir -PathType Container)) {
                Write-Host "❌ Missing Sources directory: $sourcesDir" -ForegroundColor Red
                Write-Host "💡 Create it and place skins inside." -ForegroundColor DarkGray
                return
            }
            Write-Host "✅ Sources directory: $sourcesDir"

            $launchScript = Join-Path $appDir "launch.ps1"
            if (Test-Path $launchScript -PathType Leaf) {
                Write-Host "✅ Launch script: present"
            } else {
                Write-Host "⚠️  launch.ps1 not found" -ForegroundColor Yellow
            }

            $validSkins = Get-ChildItem $sourcesDir -Directory | Where-Object {
                (Test-Path (Join-Path $_.FullName "img") -PathType Container) -and
                (Test-Path (Join-Path $_.FullName "config.json") -PathType Leaf)
            }
            if ($validSkins.Count -eq 0) {
                Write-Host "⚠️  No valid skins found in Sources/" -ForegroundColor Yellow
                Write-Host "💡 A valid skin must contain 'img/' and 'config.json'" -ForegroundColor DarkGray
            } else {
                Write-Host "✅ Found $($validSkins.Count) valid skin(s) in Sources/"
            }

            $current = Get-CurrentSkin
            if ($current) {
                Write-Host "ℹ️  Current skin: $current"
            }

            Write-Host "`n✨ Environment check complete!" -ForegroundColor Green
        }

        'info' {
            if ($Rest.Count -eq 0) {
                Write-Host "❌ Usage: bcm info <skin>" -ForegroundColor Red
                return
            }

            $skinName = $Rest[0]
            $skinPath = Join-Path $sourcesDir $skinName

            if (-not (Test-Path $skinPath -PathType Container)) {
                Write-Host "❌ Skin '$skinName' not found in Sources/" -ForegroundColor Red
                return
            }

            $infoFile = Join-Path $skinPath "skin.json"

            if (-not (Test-Path $infoFile -PathType Leaf)) {
                Write-Host "❌ Skin '$skinName' has no skin.json metadata file." -ForegroundColor Yellow
                Write-Host "💡 Authors can add it to provide info like name, author, and license." -ForegroundColor DarkGray
                return
            }

            try {
                $meta = Get-Content $infoFile -Raw | ConvertFrom-Json
            } catch {
                Write-Host "⚠️  skin.json exists but is not valid JSON." -ForegroundColor Yellow
                return
            }

            $name       = if ($meta.PSObject.Properties.Name -contains 'name')       { $meta.name }       else { $skinName }
            $author     = if ($meta.PSObject.Properties.Name -contains 'author')     { $meta.author }     else { "<unknown>" }
            $version    = if ($meta.PSObject.Properties.Name -contains 'version')    { $meta.version }    else { "<unknown>" }
            $license    = if ($meta.PSObject.Properties.Name -contains 'license')    { $meta.license }    else { "<not specified>" }
            $compatible = if ($meta.PSObject.Properties.Name -contains 'bongocatMver'){ $meta.bongocatMver} else { "<not specified>" }
            $homepage   = if ($meta.PSObject.Properties.Name -contains 'homepage')   { $meta.homepage }   else { $null }
            $desc       = if ($meta.PSObject.Properties.Name -contains 'description'){ $meta.description }else { $null }

            Write-Host "Name:       $name" -ForegroundColor Cyan
            Write-Host "Author:     $author" -ForegroundColor Green
            Write-Host "Version:    $version" -ForegroundColor Gray
            Write-Host "License:    $license" -ForegroundColor Magenta
            Write-Host "Compatible: BongoCat Mver $compatible" -ForegroundColor Gray

            if ($homepage) {
                Write-Host "Homepage:   $homepage" -ForegroundColor Cyan
            }

            if ($desc) {
                Write-Host "Description:" -ForegroundColor Gray
                ($desc -split '\n') | ForEach-Object { Write-Host "  $_" }
            }
        }

        'preview' {
            if ($Rest.Count -eq 0) {
                Write-Host "❌ Usage: bcm preview <skin>" -ForegroundColor Red
                return
            }

            $skinName = $Rest[0]
            $skinPath = Join-Path $sourcesDir $skinName

            if (-not (Test-Path $skinPath -PathType Container)) {
                Write-Host "❌ Skin '$skinName' not found in Sources/" -ForegroundColor Red
                return
            }

            # 查找预览图（按优先级）
            $previewExtensions = @('.png', '.jpg', '.jpeg', '.gif')
            $previewFile = $null
            foreach ($ext in $previewExtensions) {
                $candidate = Join-Path $skinPath ("preview" + $ext)
                if (Test-Path $candidate -PathType Leaf) {
                    $previewFile = $candidate
                    break
                }
            }

            if (-not $previewFile) {
                Write-Host "🖼️  No preview image found for skin '$skinName'." -ForegroundColor Yellow
                Write-Host "💡 Expected: preview.png, preview.jpg, preview.gif, etc." -ForegroundColor DarkGray
                return
            }

            # 检查预览命令
            if (-not $env:bcm_previewcmd) {
                Write-Host "⚠️  `$env:bcm_previewcmd is not set." -ForegroundColor Yellow
                Write-Host "💡 Set it to your terminal's image display command, e.g.:" -ForegroundColor DarkGray
                Write-Host "     `$env:bcm_previewcmd = 'kitty +kitten icat'" -ForegroundColor Cyan
                Write-Host "     `$env:bcm_previewcmd = 'wezterm imgcat'" -ForegroundColor Cyan
                Write-Host "     `$env:bcm_previewcmd = 'Invoke-Item'  # fallback to default viewer" -ForegroundColor Cyan
                return
            }

            $fullPath = Resolve-Path $previewFile
            $cmd = $env:bcm_previewcmd
            $argsList = @($fullPath.Path)

            try {
                # 分割命令（支持带空格的命令，如 "kitty +kitten icat"）
                if ($cmd -match '\s') {
                    # 假设第一个词是程序，其余是参数
                    $tokens = $cmd -split '\s+', 2
                    $exe = $tokens[0]
                    $extraArgs = if ($tokens.Count -gt 1) { $tokens[1] } else { "" }
                    $allArgs = "$extraArgs $(($fullPath.Path | ConvertTo-Json -Compress))"
                    # 更安全的方式：用 Start-Process 并传参
                    $processArgs = @($extraArgs.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries))
                    $processArgs += $fullPath.Path
                    Start-Process -FilePath $exe -ArgumentList $processArgs -NoNewWindow
                } else {
                    # 简单命令，如 "start", "imgcat"
                    & $cmd $fullPath.Path
                }
                Write-Host "👁️  Previewing: $($fullPath.Path)" -ForegroundColor Green
            } catch {
                Write-Host "❌ Failed to run preview command: $cmd" -ForegroundColor Red
                Write-Host "Error: $_" -ForegroundColor DarkRed
            }
        }

        'build' {
            $pidFile = Join-Path $appDir ".bcm-pid"
            $windowFile = Join-Path $appDir ".bcm-window"

            # (1) 检查 .bcm-pid 是否存在
            if (-not (Test-Path $pidFile -PathType Leaf)) {
                Write-Host "ℹ️  .bcm-pid file not found. BongoCat Mver may not be running via 'bcm run'." -ForegroundColor Yellow
                return
            }

            # (2) 读取并校验 PID 格式
            $pidContent = (Get-Content $pidFile -Raw).Trim()
            if ($pidContent -notmatch '^\d+$') {
                Write-Host "❌ Invalid content in .bcm-pid: '$pidContent' (expected a number)" -ForegroundColor Red
                return
            }

            $targetPid = [int]$pidContent

            # (3) 验证进程是否存在且名称正确
            $process = $null
            try {
                $process = Get-Process -Id $targetPid -ErrorAction Stop
            } catch {
                Write-Host "❌ Process with PID ${targetPid} does not exist." -ForegroundColor Red
                return
            }

            # 标准化进程名比较（处理空格和大小写）
            $actualName = $process.ProcessName.ToLower().Replace(' ', '')
            $expectedName = "bongocatmver"  # 注意：PowerShell 返回的 ProcessName 是 "Bongo Cat Mver" → 去空格后为 "bongocatmver"

            if ($actualName -ne $expectedName) {
                Write-Host "⚠️  PID ${targetPid} belongs to '$($process.ProcessName)', not 'Bongo Cat Mver'." -ForegroundColor Yellow
                Write-Host "💡 Skipping .bcm-window update for safety." -ForegroundColor DarkGray
                return
            }

            # (4) 获取窗口信息
            Write-Host "🔍 Fetching window info for PID ${targetPid}..." -ForegroundColor Cyan
            $winInfo = Get-BcmWindowInfo -ProcessId $targetPid

            if ($null -eq $winInfo) {
                Write-Host "❌ Failed to retrieve window information (window may be hidden or minimized)." -ForegroundColor Red
                return
            }

            # (5) 构造配置对象并写入 .bcm-window
            $config = [ordered]@{
                x      = $winInfo.Left
                y      = $winInfo.Top
                width  = $winInfo.Width
                height = $winInfo.Height
            }

            try {
                $jsonContent = $config | ConvertTo-Json -Compress
                Set-Content -Path $windowFile -Value $jsonContent -Encoding UTF8 -Force
                Write-Host "✅ Successfully wrote window config to ${windowFile}:" -ForegroundColor Green
                Write-Host "   Position: ($($winInfo.Left), $($winInfo.Top))" -ForegroundColor Gray
                Write-Host "   Size: $($winInfo.Width)×$($winInfo.Height)" -ForegroundColor Gray
            } catch {
                Write-Host "❌ Failed to write ${windowFile}: $_" -ForegroundColor Red
            }
        }

        'status' {
            $pidFile = Join-Path $appDir ".bcm-pid"

            if (-not (Test-Path $pidFile -PathType Leaf)) {
                Write-Host "ℹ️  BongoCat Mver is not running (via 'bcm run')." -ForegroundColor Yellow
                return
            }

            $pidContent = (Get-Content $pidFile -Raw).Trim()
            if ($pidContent -notmatch '^\d+$') {
                Write-Host "❌ Invalid content in .bcm-pid: '$pidContent' (expected a number)" -ForegroundColor Red
                return
            }

            $targetPid = [int]$pidContent

            $process = $null
            try {
                $process = Get-Process -Id $targetPid -ErrorAction Stop
            } catch {
                Write-Host "❌ Process with PID ${targetPid} does not exist." -ForegroundColor Red
                return
            }

            $actualName = $process.ProcessName.ToLower().Replace(' ', '')
            if ($actualName -ne "bongocatmver") {
                Write-Host "⚠️  PID ${targetPid} belongs to '$($process.ProcessName)', not 'Bongo Cat Mver'." -ForegroundColor Yellow
                Write-Host "💡 This may not be a bcm-managed instance." -ForegroundColor DarkGray
                return
            }

            Write-Host "BongoCat Mver is running." -ForegroundColor Green
            Write-Host "  PID:      ${targetPid}" -ForegroundColor Gray
            Write-Host "  Memory:   $(($process.WorkingSet64 / 1MB).ToString("F1")) MB" -ForegroundColor Gray
            Write-Host "  CPU Time: $($process.TotalProcessorTime.ToString('hh\:mm\:ss'))" -ForegroundColor Gray

            $winInfo = Get-BcmWindowInfo -ProcessId $targetPid
            if ($winInfo) {
                Write-Host "  Position: ($($winInfo.Left), $($winInfo.Top))" -ForegroundColor Gray
                Write-Host "  Size:     $($winInfo.Width)×$($winInfo.Height)" -ForegroundColor Gray
            } else {
                Write-Host "  Window:   Not found (may be hidden/minimized)" -ForegroundColor Yellow
            }
        }
        'help' {
            Write-Host @"
BongoCat Mver Skin & Process Manager (bcm) - v1.0.0

USAGE:
  bcm <command> [args]

SKIN MANAGEMENT:
  list                List all available skins in Sources/
  up <skin>           Activate a skin by creating symlinks
  down                Deactivate current skin (remove links & record)
  switch <skin>       Switch to another skin (down + up)
  show                Show currently active skin name
  check               Show detailed activation status and health check

LAUNCH & PROCESS:
  run                 Launch BongoCat Mver (requires active skin)
  stop                Stop the running BongoCat Mver instance (via .bcm-pid)
  status              Show runtime info: PID, memory, CPU, window position/size
  build               Save current window geometry to .bcm-window (for launch)

UTILITIES:
  doctor              Diagnose environment setup issues
  info <skin>         Show skin metadata from skin.json
  preview <skin>      Preview skin using `$env:bcm_previewcmd
  help                Show this help message
  version             Show version info
"@ -ForegroundColor Cyan
        }

        'version' {
            Write-Host "BongoCat Mver Skin Manager (bcm) - v2.0.0"
        }
    }
}